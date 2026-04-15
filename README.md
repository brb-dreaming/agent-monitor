<div align="center">

# Claude Monitor

**Control all your Claude Code and Codex sessions from one floating panel.**

Grant permissions without switching windows. Hear when Claude finishes or needs you. Track your usage quota. Click to jump to any session. Kill runaway tasks. All from a tiny always-on-top dashboard you can drag anywhere.

<br>

<img src="assets/demo.gif" width="380" alt="Claude Monitor demo" />

<br>
<br>

</div>

---

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

## Requirements

- **macOS 14+** (Sonoma or later) -- macOS only
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** -- logged in via `claude login` (OAuth, needed for usage tracking)
- **Xcode Command Line Tools** -- `xcode-select --install`
- **jq** -- `brew install jq`
- (Optional) [ElevenLabs](https://elevenlabs.io) API key for AI voices

### Terminal compatibility

Session tracking, voice announcements, and permission granting work in **any terminal**. Click-to-switch (jumping to the right tab) depends on terminal-specific integration:

| Terminal | Click-to-switch | Kill session | Notes |
|----------|:-:|:-:|-------|
| Terminal.app | yes | yes | Via AppleScript |
| iTerm2 | yes | yes | Via AppleScript + unique session ID |
| WezTerm | yes | yes | Via `wezterm cli` |
| Ghostty, Warp, kitty, Alacritty | -- | -- | Sessions appear but no click-to-switch. PRs welcome! |
| VS Code / Cursor terminal | -- | -- | Sessions appear but no click-to-switch. PRs welcome! |

## Install

### Quick start (recommended)

```bash
git clone https://github.com/brb-dreaming/claude-monitor.git ~/.claude/monitor
~/.claude/monitor/build.sh
```

Then tell Claude Code:

> Set up Claude Monitor from ~/.claude/monitor. Follow the CLAUDE.md instructions.

Claude will configure hooks, ask about your voice preferences, and get everything wired up.

### Manual setup

<details>
<summary>Click to expand step-by-step instructions</summary>

<br>

#### 1. Install dependencies

```bash
xcode-select --install   # Xcode Command Line Tools (for Swift compiler)
brew install jq           # JSON processor (used by the hook script)
```

#### 2. Clone and build

```bash
git clone https://github.com/brb-dreaming/claude-monitor.git ~/.claude/monitor
~/.claude/monitor/build.sh
```

`build.sh` compiles the Swift app, syncs hook scripts to `~/.claude/hooks/`, installs the Codex notifier into `~/.codex/config.toml`, creates `config.json` from the default template, and launches the floating panel.

#### 3. Configure hooks

Add the following to your `~/.claude/settings.json`. If you already have a `"hooks"` section, **merge** these entries in -- don't replace your existing hooks.

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

#### 4. Launch

```bash
~/.claude/monitor/build.sh
```

The floating panel appears in the top-right corner. Drag to reposition -- it remembers where you put it.

</details>

### Verify it works

1. Open the monitor -- any running Claude Code or Codex sessions appear automatically (startup discovery)
2. Start a new Claude Code session -- it appears as "starting"
3. Send a prompt -- changes to "working" with a prompt preview
4. Let Claude finish -- changes to "done", voice announces
5. Click a session row -- jumps to that terminal tab

Permission granting and usage tracking are discovered naturally during use.

### Codex support

Running Codex windows are discovered automatically and show up in the monitor with a `CODEX` badge.

`build.sh` also configures Codex's global `notify` hook so normal `codex` launches announce completion through the same monitor voice pipeline. No wrapper command is required for end users.

## Features

**Grant permissions remotely**
- Allow or deny tool requests directly from the monitor -- no terminal switching
- Works even when the terminal is hidden or on another Space
- Shows the tool name, icon, and command/file path for each request
- Three options: Allow (proceed), Deny (block), or Terminal (switch to the standard dialog)
- Uses Unix socket IPC for instant, reliable communication

**Voice announcements**
- Speaks when sessions finish or need permission
- Works immediately with macOS built-in voices (zero setup)
- Optional [ElevenLabs](https://elevenlabs.io) AI voices with smart caching -- see [Voice Setup](docs/VOICE.md)
- Per-event toggles and volume control

**Usage quota tracking**
- Session (5h) and weekly (7d) quota at a glance -- click the bar chart icon
- Color-coded progress bars: green (< 50%), yellow (50-80%), red (> 80%)
- Reset countdown timers and per-model breakdown (Opus/Sonnet)
- Bar chart icon tints to reflect your worst quota status
- Reads OAuth credentials from macOS Keychain automatically (one-time prompt)

**Session management**
- Existing Claude and Codex sessions detected automatically on launch -- no setup needed for sessions already running
- Live status for every session: starting, working, done, or needs attention
- Project name, elapsed time, and last prompt preview
- Agent badge shows whether the row is Claude or Codex
- Color-coded status dots (pulsing = working, orange = attention, green = done)
- Click any row to jump to that terminal tab instantly
- Kill any session with one click (hover to reveal the X)
- Stale sessions gray out after 10 minutes; dead sessions auto-removed
- Collapsible panel -- click the chevron to minimize to header-only mode

**Designed to disappear**
- Always-on-top floating panel, visible on all Spaces
- No dock icon, doesn't steal focus from your terminal
- Drag anywhere, position persists across restarts
- Thin custom scrollbar, minimal UI footprint

## Voice

Voice announcements work out of the box using macOS built-in speech. No setup needed.

Fresh installs default to:
- `tts_provider: "say"`
- `say.voice: "Zoe (Premium)"`
- `skin: "glass"`
- `usage.enabled: false`

| Provider | Quality | Setup | Latency |
|----------|---------|-------|---------|
| `say` (default) | Good | None | Instant |
| `cache` (recommended upgrade) | Best | ElevenLabs API key | ~10ms (cached MP3) |
| `elevenlabs` | Best | ElevenLabs API key | 1-3s (live API call) |

Most users should start with `say` and never think about it again. If you want AI-quality voice, the `cache` provider is worth trying: the first time a phrase is announced ("my-project done"), it calls ElevenLabs, saves the MP3 to `~/.claude/voice-cache/`, and every future announcement of that phrase plays back instantly from disk (~10ms, no network). Since announcements follow predictable patterns, you hit the API a handful of times on your first day and never again.

For ElevenLabs modes, you need two things:
- an `ELEVENLABS_API_KEY` in the file pointed to by `elevenlabs.env_file`
- an ElevenLabs `voice_id` in `config.json`, or pasted through the settings panel with **Paste voice ID**

All providers fall back to macOS `say` automatically if anything goes wrong.

For ElevenLabs setup, phrase tuning, cache management, and choosing a `voice_id`, see [docs/VOICE.md](docs/VOICE.md).

## Skins

4 built-in themes, switchable from the settings popover:

| Skin | Style | Background |
|------|-------|------------|
| **Glass** (default) | Pure frosted glass, white text, colored dots only | Transparent with background blur |
| **Obsidian** | Dark neumorphic, carved-from-shadow depth | Solid dark gradient |
| **Terminal** | Refined green-phosphor terminal, monospaced | Near-black with green tint |
| **Teletype** | Warm paper terminal with ink-and-ribbon accents | Opaque cream paper with subtle texture |

Set `"skin"` in `config.json` or use the picker in the settings popover. See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for details.

## How It Works

```
On launch: app discovers existing Claude Code sessions via ps + lsof
        |
        v
Claude Code hook fires -> monitor.sh writes session JSON to ~/.claude/monitor/sessions/{id}.json
        |
        v
Swift app polls directory every 500ms, picks up changes
        |
        v
Floating panel updates: status dot, project name, prompt preview, elapsed time
        |
        v
Click row -> activates the right Terminal/iTerm2/WezTerm tab
TTS -> announces via cached MP3 (instant) or macOS say (default)
```

**Permission granting** uses a separate path:

```
Swift app starts Unix socket server at ~/.claude/monitor/monitor.sock
        |
        v
Claude Code needs permission -> fires PermissionRequest hook
        |
        v
monitor_permission.py connects to the socket, writes .permission file, blocks
        |
        v
Swift app detects .permission file -> shows Allow/Deny/Terminal buttons
        |
        v
User clicks Allow -> app sends response through socket -> hook unblocks -> Claude Code proceeds
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

Configuration lives in `~/.claude/monitor/config.json`. On first build, this is copied from `config.default.json`. Your `config.json` is gitignored so personal settings are never committed.

Full config reference: [docs/CONFIGURATION.md](docs/CONFIGURATION.md)

```json
{
  "tts_provider": "say",
  "say": { "voice": "Zoe (Premium)", "rate": 200 },
  "announce": {
    "enabled": true,
    "on_done": true,
    "on_attention": true,
    "on_start": false,
    "volume": 0.5
  },
  "usage": { "enabled": false },
  "skin": "glass"
}
```

When you change settings through the UI, changes are written to `config.json` immediately. To reset to defaults, delete `config.json` and rebuild.

If you switch `tts_provider` to `cache` or `elevenlabs`, also set `elevenlabs.voice_id` in `config.json` or use **Paste voice ID** in the settings panel.

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
| ElevenLabs mode is silent | Verify `tts_provider`, `elevenlabs.env_file`, and `elevenlabs.voice_id` are all set correctly |
| Panel gone | `pkill -9 claude_monitor && ~/.claude/monitor/build.sh` |
| Wrong position | `defaults delete claude_monitor monitorX && defaults delete claude_monitor monitorY` then rebuild |
| Usage shows "No credentials" | Log in to Claude Code via OAuth (`claude login`). Or disable usage tracking in settings |
| Usage shows "Auth expired" | Re-authenticate with `claude login` |
| Usage shows "Rate limited" | Normal -- the app backs off automatically and retries |
| Keychain prompt keeps appearing | Click "Always Allow" when macOS asks to grant access |

## Uninstall

```bash
pkill claude_monitor
rm -rf ~/.claude/monitor
rm -f ~/.claude/hooks/monitor.sh ~/.claude/hooks/monitor_permission.py ~/.claude/hooks/voice-cache.sh
rm -rf ~/.claude/voice-cache
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
│   ├── config.json            # Your live config (gitignored, created on first build)
│   ├── monitor.sh             # Hook script source (synced to hooks/ on build)
│   ├── monitor_permission.py  # Permission hook source (synced to hooks/ on build)
│   ├── voice-cache.sh         # Voice cache script source (synced to hooks/ on build)
│   ├── monitor.sock           # Unix socket for permission IPC (runtime)
│   ├── phrases.json           # Default phrase tuning template
│   ├── .env.example           # ElevenLabs API key template
│   ├── docs/                  # Architecture, configuration, troubleshooting, voice setup
│   └── sessions/              # Session + permission files (auto-managed, gitignored)
├── hooks/
│   ├── monitor.sh             # Hook script (installed by build.sh)
│   ├── monitor_permission.py  # Permission hook (installed by build.sh)
│   └── voice-cache.sh         # Voice cache (installed by build.sh)
├── voice-cache/               # Cached MP3 announcements (auto-generated)
│   └── phrases.json           # Per-phrase voice settings
└── settings.json              # Claude Code settings (hooks go here)
```

## License

[MIT](LICENSE)

---

<div align="center">
<sub>Built with Claude Code. Naturally.</sub>
</div>
