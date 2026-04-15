# Architecture

Technical deep-dive into how Claude Monitor works.

## Overview

Claude Monitor has three components: a **bash hook script** for session lifecycle events, a **Python hook script** for permission granting, and a **SwiftUI app** that displays the floating panel.

```
┌─────────────────────┐     JSON files      ┌────────────────────┐
│  monitor.sh (hook)  │ ──────────────────── │  claude_monitor    │
│                     │   ~/.claude/monitor  │  (SwiftUI app)     │
│  - Lifecycle events │   /sessions/{id}.json│                    │
│  - Writes session   │                      │  - Polls sessions  │
│    JSON             │                      │    every 500ms     │
│  - Triggers TTS     │                      │  - Floating panel  │
└─────────────────────┘                      │  - Click to switch │
                                             │                    │
┌──────────────────────────┐  Unix socket    │  - Permission      │
│  monitor_permission.py   │ ────────────────│    buttons         │
│                          │ ~/.claude/      │                    │
│  - PermissionRequest hook│  monitor/       │  - Usage quota     │
│                          │  monitor.sock   │                    │
│  - Blocks until response │                 │    tracking        │
└──────────────────────────┘                 └────────┬───────────┘
                                                      │
                                  Keychain + OAuth API │ (every 5min)
                                                      │
                                             ┌────────▼───────────┐
                                             │  Anthropic API     │
                                             │  /api/oauth/usage  │
                                             └────────────────────┘
```

Session tracking uses the filesystem — the hook writes JSON files; the app reads them. Permission granting uses a Unix domain socket for real-time, blocking IPC.

## Hook Script (`monitor.sh`)

Handles 5 Claude Code lifecycle events (PermissionRequest is handled separately):

```bash
monitor.sh <event>   # receives hook JSON on stdin
```

### Event Flow

1. **Parse input** — reads JSON from stdin, extracts `session_id` and `cwd`
2. **Detect terminal** — walks the process tree to find the parent shell's TTY
3. **Write session file** — creates or updates `~/.claude/monitor/sessions/{id}.json`
4. **Announce** — optionally speaks status via macOS `say` or ElevenLabs API

### Terminal Detection

Hook subprocesses can't use the `tty` command (stdin is piped). Instead, the script walks up the process tree via `ps -o ppid=` to find the first ancestor with a real TTY device:

```
Hook process (stdin = pipe, no tty)
  └── parent shell (bash/zsh)
       └── Claude Code process
            └── shell on TTY ← found: /dev/ttys018
```

For iTerm2, the `ITERM_SESSION_ID` environment variable is used directly (set by iTerm2 on session creation). For WezTerm, `WEZTERM_PANE` provides the pane ID.

### Atomic Writes

All file operations use the tmp-and-rename pattern to prevent the SwiftUI app from reading partial JSON:

```bash
jq '...' > "${file}.tmp" && mv "${file}.tmp" "$file"
```

### TTS Integration

Three providers, same interface. The provider is selected by `tts_provider` in `config.json`:

**macOS `say` (default)**
- Uses `say -v "voice" -r rate "text"`. Note: the `announce.volume` setting only applies to the `cache` and `elevenlabs` providers (via `afplay -v`)
- Zero setup — works with any installed macOS voice
- Premium voices (Zoe, Ava, etc.) can be downloaded in System Settings → Accessibility → Spoken Content

**Voice cache (recommended for AI voices)**
- Implemented in `voice-cache.sh`, called by `monitor.sh` when `tts_provider` is `"cache"`
- On cache hit: plays `~/.claude/voice-cache/{phrase-key}.mp3` instantly (~10ms via `afplay`)
- On cache miss: calls ElevenLabs API, saves the MP3 to the cache directory, then plays it
- Cache key: phrase lowercased → spaces to dashes → strip non-alphanumeric (e.g., `"my project done"` → `my-project-done.mp3`)
- Reads per-phrase overrides from `~/.claude/voice-cache/phrases.json` (text, stability, style, speed)
- Falls back to macOS `say` if no ElevenLabs credentials

**ElevenLabs real-time (no caching)**
- `curl` POST to `/v1/text-to-speech/{voice_id}`, saves to temp MP3, plays with `afplay -v`
- Temp file is deleted after 30 seconds
- Falls back to macOS `say` on API failure

**Voice selection flow**:
1. A `voice_id` is stored in `config.json`
2. The `voice_id` is used by both `cache` and `elevenlabs` providers

All providers run in the background (`&` + `disown`) to avoid blocking the hook.

## Permission Hook (`monitor_permission.py`)

Handles `PermissionRequest` events via Unix domain socket IPC. This is separate from `monitor.sh` because permission granting requires blocking — the hook must wait for the user's decision before returning a response to Claude Code.

### Why Unix sockets?

Claude Code's `PermissionRequest` hook has a race condition: if the hook takes more than ~1-2 seconds to respond, Claude Code shows its own terminal dialog regardless. File-based polling (write a file, wait for response file) is too slow. A Unix socket lets the Python hook block on `sock.recv()` and get an instant response when the user clicks a button.

### Flow

```
1. Claude Code fires PermissionRequest hook
2. monitor_permission.py starts:
   a. Writes {session_id}.permission file (tool name, command, etc.)
   b. Connects to ~/.claude/monitor/monitor.sock
   c. Sends permission details as JSON
   d. Blocks on sock.recv() — waiting for user decision
3. Swift app detects .permission file → shows Allow/Deny/Terminal buttons
4. User clicks a button:
   a. Swift app writes response JSON to the socket connection
   b. Python hook receives it, outputs decision JSON to stdout
   c. Claude Code reads the hook output and proceeds
5. .permission file is cleaned up
```

### Graceful degradation

If the monitor app isn't running (socket doesn't exist), the Python hook exits silently with code 0 and no output. Claude Code then falls back to its standard terminal permission dialog.

The hook has a 24-hour timeout (`86400` seconds in settings.json) to allow waiting indefinitely for the user.

## SwiftUI App (`claude_monitor.swift`)

Single-file SwiftUI app, compiled to a standalone binary.

### Key Classes

| Class | Role |
|-------|------|
| `SessionReader` | Polls `sessions/` directory every 500ms, decodes JSON, sorts by priority |
| `PermissionSocketServer` | Unix domain socket server — accepts connections from permission hooks, routes responses |
| `UsageFetcher` | Reads OAuth credentials from Keychain/file, polls Anthropic usage API, caches token + data |
| `ConfigManager` | Reads/writes `config.json`, manages voice selection |
| `VoiceFetcher` | Fetches ElevenLabs voice library via API |
| `FloatingPanel` | `NSPanel` subclass — borderless, always-on-top, non-activating |
| `ClickHostingView` | `NSHostingView` with `acceptsFirstMouse` for click-through, transparent background |
| `ThinScroller` | Custom `NSScroller` subclass for the themed scrollbar |

### Panel Behavior

The panel uses `NSPanel` with `.nonactivatingPanel` style, which means:
- It floats above all windows without stealing keyboard focus
- It follows you across all Spaces (`canJoinAllSpaces`)
- It doesn't appear in the Dock or Cmd+Tab switcher (`.accessory` activation policy)
- Buttons work via AppKit-level interception, even with `isMovableByWindowBackground`

**Known tradeoff**: `nonactivatingPanel` popovers can't receive keyboard input. The voice ID selector uses clipboard paste as a workaround.

### Auto-Resize

The panel grows downward from its top edge. A KVO observer on `fittingSize` adjusts the frame whenever content changes:

```
Top edge (anchored) ──────────────
│  Header bar                    │
│  Session 1                     │
│  Session 2                     │
│  Session 3 (new — panel grows) │
Bottom edge (moves down) ────────
```

### Session Lifecycle Management

**Liveness check**: Every 5 seconds, the app checks if each session's TTY still has processes running. If the terminal tab was closed (no processes on TTY), the session file is removed automatically.

**Discovery**: On startup and when the refresh button is clicked, the app discovers running Claude Code sessions that hooks missed. It cross-references `ps` (for claude processes with TTYs), `wezterm cli list` (for pane→TTY mapping), and iTerm2 AppleScript (for session IDs). It resolves each process's working directory via `lsof`, skips `cwd=/` (a launcher artifact), detects the correct terminal type, and creates session files for any that aren't already tracked.

### Terminal Tab Switching

Three strategies based on terminal type:

- **Terminal.app** — AppleScript iterates all windows/tabs, matches `tty of t` against the stored TTY path
- **iTerm2** — AppleScript matches `unique id of s` against the stored `ITERM_SESSION_ID`
- **WezTerm** — `wezterm cli activate-pane --pane-id` focuses the pane directly

### Session Kill

When killing a session:

1. For Terminal.app: `pkill -TERM -t <tty> -f claude` sends SIGTERM to claude processes on that TTY
2. For iTerm2: AppleScript gets the TTY from the iTerm2 session, then uses the same `pkill` approach
3. For WezTerm: `wezterm cli list` resolves pane ID → TTY, then uses the same `pkill` approach
4. Session file is cleaned up after 3 seconds

## Session JSON Schema

```json
{
  "session_id": "uuid",
  "status": "starting | working | done | attention",
  "project": "directory-name",
  "cwd": "/absolute/path",
  "terminal": "terminal | iterm2 | wezterm",
  "terminal_session_id": "/dev/ttys018 | w0t0p0:GUID | 42",
  "started_at": "ISO8601",
  "updated_at": "ISO8601",
  "last_prompt": "first 200 chars of last user prompt"
}
```

The decoder uses `decodeIfPresent` with defaults for all fields except `session_id`, making it resilient to schema changes or partial writes.

## Usage Quota Fetcher (`UsageFetcher`)

Tracks Claude Code usage limits by polling the Anthropic OAuth usage API.

### Credential Reading

The fetcher reads OAuth credentials from two sources (tried in order):

1. **File** — `~/.claude/.credentials.json` (some installs use this)
2. **macOS Keychain** — service `Claude Code-credentials`, via `SecItemCopyMatching`

The Keychain blob is a JSON object with credentials nested under `claudeAiOauth`:

```json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-...",
    "refreshToken": "...",
    "expiresAt": 1773284247432,
    "scopes": ["user:inference", "user:profile", ...],
    "rateLimitTier": "..."
  }
}
```

The token and expiry are **cached in memory** after the first read. The Keychain is only accessed again when the cached token is within 60 seconds of expiring. This avoids repeated macOS Keychain permission prompts (the binary is not code-signed with Keychain entitlements, so macOS prompts the user on each `SecItemCopyMatching` call until "Always Allow" is granted).

### API Endpoint

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <access_token>
anthropic-beta: oauth-2025-04-20
```

Response:

```json
{
  "five_hour": { "utilization": 42.0, "resets_at": "2026-03-11T22:00:00Z" },
  "seven_day": { "utilization": 15.0, "resets_at": "2026-03-14T00:00:00Z" },
  "seven_day_opus": { "utilization": 5.0, "resets_at": "..." },
  "seven_day_sonnet": { "utilization": 10.0, "resets_at": "..." },
  "extra_usage": {
    "is_enabled": true,
    "monthly_limit": 10000,
    "used_credits": 250,
    "utilization": 2.5,
    "currency": "USD"
  }
}
```

- `utilization` is 0-100 (percentage)
- `resets_at` is ISO 8601
- `extra_usage` amounts are in **cents** (divided by 100 for display)
- All fields are optional — missing windows are simply not displayed

### Polling and Rate Limit Handling

| Behavior | Value |
|----------|-------|
| Default poll interval | 5 minutes |
| Minimum fetch gap (popover open) | 2 minutes — stale data is shown rather than re-fetching |
| On HTTP 429 | Exponential backoff: double the interval, cap at 15 minutes |
| On HTTP 401 | Clear cached token, next fetch re-reads Keychain |
| On success after backoff | Reset interval to 5 minutes |

### UI

- **Bar chart icon** in the header bar, between session count and gear icon
- Icon **tints** to reflect the worst quota status (green/yellow/red)
- Clicking opens a popover with progress bars, reset countdowns, and optional credit tracking
- Manual refresh button in the popover triggers an immediate fetch (respects the 2-minute gap)

## Collapsible Panel

The panel header includes a **chevron toggle** (▶/▼) that collapses the session list, leaving only the header bar visible. This state is persisted in `UserDefaults` under the key `monitorExpanded`.

When collapsed, the header still shows:
- Status summary dots (orange/cyan/green counts)
- Total session count
- Usage icon (with quota-aware tinting)
- Settings gear icon

The panel auto-resizes via the existing `fittingSize` KVO observer, so collapsing smoothly shrinks the panel to header height.
