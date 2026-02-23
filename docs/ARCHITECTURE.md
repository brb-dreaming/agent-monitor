# Architecture

Technical deep-dive into how Claude Monitor works.

## Overview

Claude Monitor has three components: a **bash hook script** for session lifecycle events, a **Python hook script** for permission granting, and a **SwiftUI app** that displays the floating panel.

```
┌─────────────────────┐     JSON files      ┌────────────────────┐
│  monitor.sh (hook)  │ ──────────────────── │  claude_monitor    │
│                     │   ~/.claude/monitor  │  (SwiftUI app)     │
│  - Lifecycle events │   /sessions/{id}.json│                    │
│  - Writes session   │                      │  - Polls every     │
│    JSON             │                      │    500ms           │
│  - Triggers TTS     │                      │  - Floating panel  │
└─────────────────────┘                      │  - Click to switch │
                                             │                    │
┌──────────────────────────┐  Unix socket    │  - Permission      │
│  monitor_permission.py   │ ────────────────│    buttons         │
│                          │ /tmp/claude-    │                    │
│  - PermissionRequest hook│  monitor.sock   │                    │
│  - Blocks until response │                 │                    │
└──────────────────────────┘                 └────────────────────┘
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

For iTerm2, the `ITERM_SESSION_ID` environment variable is used directly (set by iTerm2 on session creation).

### Atomic Writes

All file operations use the tmp-and-rename pattern to prevent the SwiftUI app from reading partial JSON:

```bash
jq '...' > "${file}.tmp" && mv "${file}.tmp" "$file"
```

### TTS Integration

Two providers, same interface:

- **macOS `say`** — uses `osascript` for volume control: `say "text" using "voice" speaking rate N volume V`
- **ElevenLabs** — `curl` POST to `/v1/text-to-speech/{voice_id}`, plays response with `afplay -v`

Both run in the background (`&` + `disown`) to avoid blocking the hook.

## Permission Hook (`monitor_permission.py`)

Handles `PermissionRequest` events via Unix domain socket IPC. This is separate from `monitor.sh` because permission granting requires blocking — the hook must wait for the user's decision before returning a response to Claude Code.

### Why Unix sockets?

Claude Code's `PermissionRequest` hook has a race condition: if the hook takes more than ~1-2 seconds to respond, Claude Code shows its own terminal dialog regardless. File-based polling (write a file, wait for response file) is too slow. A Unix socket lets the Python hook block on `sock.recv()` and get an instant response when the user clicks a button.

### Flow

```
1. Claude Code fires PermissionRequest hook
2. monitor_permission.py starts:
   a. Writes {session_id}.permission file (tool name, command, etc.)
   b. Connects to /tmp/claude-monitor.sock
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

**Discovery**: The refresh button in settings scans for running `claude` processes, finds their TTYs and working directories, and creates session files for any that aren't tracked.

### Terminal Tab Switching

Two strategies based on terminal type:

- **Terminal.app** — AppleScript iterates all windows/tabs, matches `tty of t` against the stored TTY path
- **iTerm2** — AppleScript matches `unique id of s` against the stored `ITERM_SESSION_ID`

### Session Kill

When killing a session:

1. For Terminal.app: `pkill -TERM -t <tty> -f claude` sends SIGTERM to claude processes on that TTY
2. For iTerm2: AppleScript gets the TTY from the iTerm2 session, then uses the same `pkill` approach
3. Session file is cleaned up after 3 seconds

## Session JSON Schema

```json
{
  "session_id": "uuid",
  "status": "starting | working | done | attention",
  "project": "directory-name",
  "cwd": "/absolute/path",
  "terminal": "terminal | iterm2",
  "terminal_session_id": "/dev/ttys018 | w0t0p0:GUID",
  "started_at": "ISO8601",
  "updated_at": "ISO8601",
  "last_prompt": "first 200 chars of last user prompt"
}
```

The decoder uses `decodeIfPresent` with defaults for all fields except `session_id`, making it resilient to schema changes or partial writes.
