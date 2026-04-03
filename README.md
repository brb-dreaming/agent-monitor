<div align="center">

# Claude Monitor

**A floating macOS dashboard for all your Claude Code sessions.**

See what's working, what's done, and what needs you — at a glance. Grant permissions without switching windows. Hear it too — voice announces when sessions finish or need attention.

<br>

<img src="assets/demo.gif" width="380" alt="Claude Monitor demo" />

<br>
<br>

</div>

---

If you run multiple Claude Code sessions at once, you know the pain: switching tabs to check which one finished, which one is waiting for permission, which one is still thinking. Claude Monitor fixes that.

A tiny always-on-top panel you can drag anywhere on your screen. It shows every active Claude Code session with its status, project name, and last prompt. Click a row to jump straight to that terminal tab.

**And it talks to you.** When a session finishes — *"my-project done."* When one needs permission — *"backend needs attention."* Works out of the box with your Mac's built-in voices. Plug in an [ElevenLabs](https://elevenlabs.io) API key for AI voices, or browse and switch voices from the built-in picker.

<div align="center">
<table>
<tr>
<td><img src="assets/Monitor.png" width="280" alt="Session list" /></td>
<td><img src="assets/Monitor Menu.png" width="280" alt="Settings popover" /></td>
</tr>
<tr>
<td align="center"><sub>Session tracking with live status</sub></td>
<td align="center"><sub>Voice settings + session refresh</sub></td>
</tr>
</table>
</div>

## Features

**Usage quota tracking**
- See your Claude Code session (5h) and weekly (7d) quota at a glance — click the bar chart icon
- Color-coded progress bars: green (< 50%), yellow (50-80%), red (> 80%)
- Reset countdown timers — know exactly when your quota refreshes
- Per-model breakdown (Opus/Sonnet) when applicable
- Extra usage credit tracking if enabled on your plan
- The bar chart icon tints to reflect your worst quota status — subtle early warning
- Reads your OAuth credentials from macOS Keychain automatically (one-time prompt)
- Disable usage tracking entirely from settings if you don't want credential access
- Polls every 5 minutes with smart backoff on rate limits

**Grant permissions remotely**
- Allow or deny tool requests directly from the monitor — no terminal switching needed
- Works even when the terminal window is hidden or on another Space
- Shows the tool name, icon, and command/file path for each request
- Three options: Allow (proceed), Deny (block), or Terminal (switch to terminal for the standard dialog)
- Uses Unix socket IPC for instant, reliable communication with Claude Code

**Voice announcements**
- Speaks when sessions finish or need permission — no more tab-switching to check
- Works immediately with macOS built-in voices (zero setup)
- Optional [ElevenLabs](https://elevenlabs.io) AI voices with **smart caching** — each phrase is generated once, saved as MP3, and replayed instantly (~10ms) on every future announcement
- One-click voice generation — designs a custom AI voice from an included prompt and saves it to your account
- Phrase tuning — customize punctuation, stability, and style per phrase via `phrases.json`
- Built-in voice picker — browse your ElevenLabs library or paste any voice ID
- Per-event toggles and volume in `config.json`

**See everything**
- Live status for every session: starting, working, done, or needs attention
- Project name, elapsed time, and last prompt preview
- Color-coded status dots (pulsing cyan = working, orange = attention, green = done)
- Stale sessions automatically gray out after 10 minutes
- Collapsible panel — click the chevron to minimize to header-only mode

**Stay in flow**
- Click any row to jump to that terminal tab instantly (Terminal.app + iTerm2)
- Kill any session with one click (hover to reveal the X)
- Dead sessions auto-removed when the terminal tab closes
- Discover missing sessions with the refresh button

**Designed to disappear**
- Always-on-top dark glass panel, visible on all Spaces
- No dock icon, doesn't steal focus from your terminal
- Drag anywhere, position persists across restarts
- Collapse to a tiny header bar when you don't need the session list
- Thin custom scrollbar, minimal UI footprint

## Install

### The easy way (recommended)

Copy this **entire README** into Claude Code (or any coding agent that can edit files) and say:

> Set up Claude Monitor. Create all the files described in the README, configure hooks, compile, and launch.

That's it. The agent will create the files, wire up the hooks, compile the Swift app, and launch the floating panel. Takes about 30 seconds.

### Manual setup

<details>
<summary>Click to expand step-by-step instructions</summary>

<br>

#### 1. Install dependencies

```bash
xcode-select --install   # Xcode Command Line Tools (for Swift compiler)
brew install jq           # JSON processor (used by the hook script)
```

#### 2. Create directories

```bash
mkdir -p ~/.claude/monitor/sessions
mkdir -p ~/.claude/hooks
```

#### 3. Copy files

Clone or download this repo into `~/.claude/monitor/`:

```bash
git clone https://github.com/brb-dreaming/claude-monitor.git ~/.claude/monitor
```

Or download and place these files manually — everything goes in `~/.claude/monitor/`:

| File | Description |
|------|-------------|
| `claude_monitor.swift` | SwiftUI floating panel (single-file app) |
| `build.sh` | Compile + launch script |
| `config.default.json` | Default config template |
| `monitor.sh` | Hook script — lifecycle events + TTS |
| `monitor_permission.py` | Permission hook — Unix socket IPC |
| `voice-cache.sh` | Voice cache — generate once, replay instantly |
| `phrases.json` | Default phrase tuning template |
| `.env.example` | ElevenLabs API key template |

`build.sh` automatically syncs `monitor.sh`, `monitor_permission.py`, and `voice-cache.sh` to `~/.claude/hooks/` on every build, creates `config.json` from the template, and initializes the voice cache directory.

Make the build script executable:

```bash
chmod +x ~/.claude/monitor/build.sh
```

#### 4. Configure hooks

Add the following to your `~/.claude/settings.json`. If you already have a `"hooks"` section, **merge** these entries in — don't replace your existing hooks.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/monitor.sh SessionStart" }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/monitor.sh UserPromptSubmit" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/monitor.sh Stop" }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/monitor.sh Notification" }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 $HOME/.claude/hooks/monitor_permission.py",
            "timeout": 86400
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/hooks/monitor.sh SessionEnd" }
        ]
      }
    ]
  }
}
```

#### 5. Compile and launch

```bash
~/.claude/monitor/build.sh
```

The floating panel appears in the top-right corner. Drag to reposition — it remembers where you put it.

</details>

### Verify it works

1. Start a new Claude Code session — it appears as "starting"
2. Send a prompt — changes to "working" with a prompt preview
3. Let Claude finish — changes to "done", voice announces
4. Trigger a permission prompt — the monitor shows Allow/Deny/Terminal buttons
5. Click Allow — Claude Code proceeds without switching to the terminal
6. Click a session row — jumps to that terminal tab
7. Hover a row and click X — kills that Claude Code session
8. Click the bar chart icon (📊) — see your usage quota and reset timers
9. Click the chevron (▼) next to "Claude" — collapse/expand the session list

## Voice Setup

Claude Monitor speaks out loud when sessions finish or need attention. There are three TTS providers, from simplest to highest quality:

| Provider | Quality | Setup | How it works |
|----------|---------|-------|--------------|
| `say` | Good | None | macOS built-in speech — works immediately |
| `cache` | Best | ElevenLabs API key | Pre-generates audio once per phrase, caches as MP3, instant replay |
| `elevenlabs` | Best | ElevenLabs API key | Real-time API call per announcement (no caching) |

The default is **`say`** — zero setup, works out of the box. If you want AI-quality voice, the **`cache`** provider is recommended: it generates each announcement phrase once via ElevenLabs, saves the MP3 locally, and replays it instantly (~10ms) on every future announcement. You only pay for each unique phrase once.

### macOS voices (default — zero setup)

Voice announcements work out of the box using your Mac's built-in speech synthesizer. The default voice is **Zoe (Premium)** at 50% volume. If Zoe isn't installed, macOS falls back to its system default automatically.

**Installing better voices** (recommended — they sound much better than the defaults):

1. Open **System Settings** → **Accessibility** → **Spoken Content** → **System Voice** → **Manage Voices**
2. Browse and download voices you like (Zoe, Ava, Tom, etc. — look for "Premium" or "Enhanced" variants)
3. Update your `config.json` with the exact voice name:

```json
{
  "tts_provider": "say",
  "say": { "voice": "Zoe (Premium)", "rate": 200 }
}
```

Run `say -v '?'` in Terminal to list all installed voices and their exact names.

### Voice cache — AI voices with instant playback (recommended)

The `cache` provider gives you ElevenLabs AI voice quality with near-zero latency. Here's how it works:

1. When the monitor needs to announce a phrase (e.g., "my-project done"), it checks `~/.claude/voice-cache/` for a cached MP3
2. **Cache hit** — plays the MP3 instantly (~10ms). No API call, no network, no delay
3. **Cache miss** — calls ElevenLabs to generate the audio, saves the MP3 to the cache, and plays it. All future announcements of that phrase are instant

Since announcements follow predictable patterns (`"project-name done"`, `"project-name needs attention"`), most phrases are generated once during your first session with a project and cached forever after.

#### Setup

1. **Get an ElevenLabs API key** — sign up at [elevenlabs.io](https://elevenlabs.io) (free tier works — you only generate each phrase once)

2. **Save your key** — copy the included example and add your key:
   ```bash
   cp .env.example ~/.env
   # edit ~/.env and paste your ELEVENLABS_API_KEY
   ```

3. **Generate a voice** — open the settings popover (gear icon) and click **Generate voice**. This designs a custom AI voice from the included prompt, saves it to your ElevenLabs account, and sets the `voice_id` in your config. One click, done.

4. **Switch to cache mode** — update your `config.json`:
   ```json
   {
     "tts_provider": "cache",
     "elevenlabs": {
       "env_file": "~/.env"
     }
   }
   ```

5. **Done.** The first time each phrase is announced, you'll hear a brief delay while the MP3 is generated. Every time after that, it's instant.

#### Phrase tuning

You can customize how specific phrases sound by editing `~/.claude/voice-cache/phrases.json`. Each phrase can override the text sent to ElevenLabs and tune voice settings independently:

```json
{
  "claude replied": {
    "text": "Claude replied.",
    "stability": 0.55,
    "similarity_boost": 0.75,
    "style": 0.15,
    "speed": 1.0
  }
}
```

This lets you control punctuation (periods for calm, exclamation marks for urgency), stability (lower = more expressive), and style. After editing, delete the corresponding MP3 from `~/.claude/voice-cache/` to regenerate it with the new settings.

The cache key is the phrase lowercased with spaces replaced by dashes: `"my project done"` → `my-project-done.mp3`.

#### Managing the cache

```bash
# See all cached phrases
ls ~/.claude/voice-cache/*.mp3

# Regenerate a specific phrase (delete + next announcement re-generates)
rm ~/.claude/voice-cache/my-project-done.mp3

# Clear entire cache (all phrases regenerate on next use)
rm ~/.claude/voice-cache/*.mp3
```

#### Other ways to pick a voice

- **Browse your library** — the voice picker in settings shows all voices from your ElevenLabs account
- **Paste a voice ID** — copy any voice ID to your clipboard, click "Paste voice ID" in settings — the app resolves the name and saves it
- **Customize the design prompt** — edit `elevenlabs.voice_design_prompt` in `config.json` before generating. The included prompt creates a warm, softly synthetic voice — like a machine that genuinely cares

### ElevenLabs real-time (no caching)

If you prefer fresh API calls for every announcement (e.g., you're experimenting with voice settings), set `tts_provider` to `"elevenlabs"` instead of `"cache"`. Same setup as above, but audio is generated on each announcement and not saved. Falls back to macOS `say` on API failure.

### Fallback behavior

Both `cache` and `elevenlabs` providers automatically fall back to macOS `say` if the ElevenLabs API is unavailable (no API key, network error, rate limit). You never miss an announcement.

### Volume and event toggles

All toggleable from the settings popover or directly in `config.json`:

| Setting | Default | Description |
|---------|---------|-------------|
| `announce.enabled` | `true` | Master on/off (also togglable from the gear icon) |
| `announce.volume` | `0.5` | Volume from `0.0` (silent) to `1.0` (full) |
| `announce.on_done` | `true` | Speak when a session finishes |
| `announce.on_attention` | `true` | Speak when a session needs permission |
| `announce.on_start` | `false` | Speak when a session starts |

## Requirements

- **macOS 14+** (Sonoma or later)
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** — the CLI tool from Anthropic, logged in via `claude login` (OAuth — needed for usage tracking)
- **Xcode Command Line Tools** — `xcode-select --install` (for the Swift compiler)
- **jq** — `brew install jq` (for JSON processing in the hook script)
- **Terminal.app or iTerm2**
- (Optional) [ElevenLabs](https://elevenlabs.io) API key for AI voices

## How It Works

```
Claude Code hook fires
        |
        v
monitor.sh writes session JSON to ~/.claude/monitor/sessions/{id}.json
        |
        v
Swift app polls directory every 500ms, picks up changes
        |
        v
Floating panel updates: status dot, project name, prompt preview, elapsed time
        |
        v
Click row → AppleScript activates the right Terminal/iTerm2 tab
TTS → announces via cached MP3 (instant) or macOS say (default)
```

**Permission granting** uses a separate path:

```
Swift app starts Unix socket server at /tmp/claude-monitor.sock
        |
        v
Claude Code needs permission → fires PermissionRequest hook
        |
        v
monitor_permission.py connects to the socket, writes .permission file, blocks
        |
        v
Swift app detects .permission file → shows Allow/Deny/Terminal buttons
        |
        v
User clicks Allow → app sends response through socket → hook unblocks → Claude Code proceeds
```

**Usage tracking** reads your Claude Code OAuth credentials:

```
Swift app reads OAuth token from macOS Keychain (one-time prompt)
        |
        v
Polls GET https://api.anthropic.com/api/oauth/usage every 5 minutes
        |
        v
Displays session (5h) and weekly (7d) quota bars + reset countdown
        |
        v
Bar chart icon tints green/yellow/red based on worst quota status
```

Each Claude Code lifecycle event maps to a session status:

| Event | Status | Voice |
|-------|--------|-------|
| Session starts | `starting` | Optional (off by default) |
| You send a prompt | `working` | No |
| Claude finishes | `done` | Yes |
| Claude needs permission | `attention` + Allow/Deny buttons | Yes |
| You exit Claude Code | Removed after 5s | No |
| Terminal tab closed | Auto-removed | No |

See [Architecture](docs/ARCHITECTURE.md) for the full technical deep-dive.

## Configuration

Configuration lives in `~/.claude/monitor/config.json`. On first build, this is copied from `config.default.json` — the tracked template with safe defaults. Your `config.json` is gitignored so your personal settings (voice IDs, API paths, saved voices) are never committed.

Full config reference: [docs/CONFIGURATION.md](docs/CONFIGURATION.md)

```json
{
  "tts_provider": "say",
  "elevenlabs": {
    "env_file": "~/.env",
    "model": "eleven_multilingual_v2",
    "stability": 0.5,
    "similarity_boost": 0.75,
    "voice_design_prompt": "Soft, androgynous male voice with a clear synthetic quality...",
    "voice_design_name": "claude-monitor"
  },
  "say": { "voice": "Zoe (Premium)", "rate": 200 },
  "announce": {
    "enabled": true,
    "on_done": true,
    "on_attention": true,
    "on_start": false,
    "volume": 0.5
  },
  "usage": { "enabled": true },
  "voices": []
}
```

When you change settings through the UI (toggle voice, select a voice, disable usage tracking), changes are written to `config.json` immediately. To reset to defaults, delete `config.json` and rebuild — a fresh copy is created from the template.

## Troubleshooting

See [Troubleshooting Guide](docs/TROUBLESHOOTING.md) for detailed solutions. Quick fixes:

| Problem | Fix |
|---------|-----|
| Sessions don't appear | Send a new prompt in that session to trigger the hook |
| Permission buttons missing | Verify `PermissionRequest` hook is in `settings.json` and `monitor_permission.py` exists |
| Allow clicked, nothing happens | Restart the monitor: `pkill -9 claude_monitor && ~/.claude/monitor/build.sh` |
| Click doesn't switch tabs | Check that `terminal_session_id` is set in the session JSON |
| No voice | Verify `announce.enabled` is `true` and `volume` > `0` |
| Wrong voice | Run `say -v '?'` to find the exact voice name, update `say.voice` |
| Panel gone | `pkill -9 claude_monitor && ~/.claude/monitor/build.sh` |
| Wrong position | `defaults delete claude_monitor monitorX && defaults delete claude_monitor monitorY` then rebuild |
| Usage shows "No credentials" | You need to be logged in to Claude Code via OAuth (`claude login`). Or disable usage tracking in settings if you don't want credential access |
| Usage shows "Auth expired" | Re-authenticate with `claude login` — the cached token has expired |
| Usage shows "Rate limited" | Normal — the app backs off automatically (5min → 10min → 15min) and retries |
| Keychain prompt keeps appearing | Click "Always Allow" when macOS asks to grant `claude_monitor` access to "Claude Code-credentials" |

## Uninstall

```bash
pkill claude_monitor
rm -rf ~/.claude/monitor
rm -f ~/.claude/hooks/monitor.sh ~/.claude/hooks/monitor_permission.py ~/.claude/hooks/voice-cache.sh
rm -rf ~/.claude/voice-cache
rm -f /tmp/claude-monitor.sock
```

Then remove the 6 hook entries (`SessionStart`, `UserPromptSubmit`, `Stop`, `Notification`, `PermissionRequest`, `SessionEnd`) from `~/.claude/settings.json`.

## File Layout

```
~/.claude/
├── monitor/
│   ├── claude_monitor.swift    # SwiftUI floating panel (single-file app)
│   ├── claude_monitor          # Compiled binary (after build, gitignored)
│   ├── build.sh               # Compile + launch script
│   ├── config.default.json    # Default config template (tracked in git)
│   ├── config.json            # Your live config (gitignored, created from template on first build)
│   ├── voice-cache.sh         # Voice cache script (copied to hooks/ on first build)
│   ├── phrases.json           # Default phrase tuning template (copied to voice-cache/ on first build)
│   ├── .env.example           # ElevenLabs API key template
│   └── sessions/              # Session + permission files (auto-managed, gitignored)
├── hooks/
│   ├── monitor.sh             # Hook script — lifecycle events + TTS
│   ├── monitor_permission.py  # Permission hook — Unix socket IPC
│   └── voice-cache.sh         # Voice cache — generate once, replay instantly (installed by build.sh)
├── voice-cache/               # Cached MP3 announcements (auto-generated, not tracked)
│   └── phrases.json           # Per-phrase voice settings (stability, style, text overrides)
└── settings.json              # Claude Code settings (hooks go here)
```

## License

[MIT](LICENSE)

---

<div align="center">
<sub>Built with Claude Code. Naturally.</sub>
</div>
