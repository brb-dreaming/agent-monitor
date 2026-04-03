# Configuration Reference

Configuration lives in `~/.claude/monitor/config.json`. This file is **gitignored** — your personal settings (voice IDs, API paths, saved voices) are never committed.

On first build, `build.sh` copies `config.default.json` → `config.json` if it doesn't exist. To reset to defaults, delete `config.json` and rebuild.

Changes are picked up by the hook script on the next event and by the SwiftUI app when it re-reads config. Changes made through the settings popover are written to `config.json` immediately.

## Full Default Config

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
  "say": {
    "voice": "Zoe (Premium)",
    "rate": 200
  },
  "announce": {
    "enabled": true,
    "on_done": true,
    "on_attention": true,
    "on_start": false,
    "volume": 0.5
  },
  "usage": {
    "enabled": true
  },
  "voices": []
}
```

## Fields

### `tts_provider`

Which TTS engine to use for voice announcements.

| Value | Description |
|-------|-------------|
| `"say"` | macOS built-in speech synthesizer (default, no setup needed) |
| `"cache"` | ElevenLabs with local caching — generates each phrase once, saves as MP3, replays instantly on future announcements (recommended for AI voices) |
| `"elevenlabs"` | ElevenLabs real-time — fresh API call per announcement, no caching (useful for experimenting with voice settings) |

### `elevenlabs`

ElevenLabs configuration. Only used when `tts_provider` is `"elevenlabs"`.

The ElevenLabs integration has two phases:

1. **Voice generation** (one-time) — click "Generate voice" in settings to create a custom AI voice from `voice_design_prompt`. The voice is permanently saved to your ElevenLabs account and its `voice_id` is stored in config.
2. **Announcements** (ongoing) — each announcement ("project done", "backend needs attention") is a short real-time API call using the saved `voice_id`. Usage is minimal since announcements are only a few words.

If the API call fails, the monitor falls back to macOS `say` for that announcement.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `env_file` | string | `"~/.env"` | Path to `.env` file containing `ELEVENLABS_API_KEY` (supports `~`) |
| `voice_id` | string | — | ElevenLabs voice ID to use for TTS. Set automatically when you generate or select a voice in the settings popover |
| `model` | string | `"eleven_multilingual_v2"` | ElevenLabs model ID for real-time announcements |
| `stability` | number | `0.5` | Voice stability (0.0–1.0). Higher = more consistent, lower = more expressive |
| `similarity_boost` | number | `0.75` | Voice similarity boost (0.0–1.0). Higher = closer to the original voice |
| `voice_design_prompt` | string | *(included)* | Text prompt describing the voice to generate. Used by the "Generate voice" button in settings. Customize this before generating to get a different voice character |
| `voice_design_name` | string | `"claude-monitor"` | Name for the generated voice in your ElevenLabs account |

### `say`

macOS `say` command configuration. Only used when `tts_provider` is `"say"`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `voice` | string | `"Zoe (Premium)"` | macOS voice name. Run `say -v '?'` to list all installed voices. Install premium voices in System Settings → Accessibility → Spoken Content → Manage Voices |
| `rate` | number | `200` | Speaking rate in words per minute |

### `announce`

Controls when and how voice announcements are made.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Master toggle. Also controllable from the settings popover |
| `on_done` | boolean | `true` | Announce when a session finishes |
| `on_attention` | boolean | `true` | Announce when a session needs permission |
| `on_start` | boolean | `false` | Announce when a new session starts |
| `volume` | number | `0.5` | Announcement volume from `0.0` (silent) to `1.0` (full system volume) |

### `usage`

Controls the usage quota tracking feature. When disabled, no credentials are read and no API calls are made.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Toggle usage tracking on/off. Also controllable from the settings popover. When off, the bar chart icon is hidden and no credentials are accessed |

### `voices`

Array of saved voices that appear in the settings voice picker. Voices are added here automatically when you generate a voice, paste a voice ID, or select from your library.

```json
{
  "voices": [
    { "id": "some-voice-id", "name": "my custom voice" }
  ]
}
```

The voice picker shows these saved voices **plus** any voices from your ElevenLabs library (fetched via API on launch). Saved voices always appear first.

## ElevenLabs `.env` File

Copy the included [`.env.example`](../.env.example) to wherever you keep secrets and add your key:

```bash
cp .env.example ~/.env
# edit ~/.env and paste your ELEVENLABS_API_KEY
```

Point to it with `elevenlabs.env_file` in `config.json`. The path supports `~` for home directory.

The API key is used for:
- **Voice generation** (one-time) — designing and saving a custom voice to your ElevenLabs account
- **Announcements** (ongoing) — real-time text-to-speech for short status phrases
- **Voice library** — fetching your voices for the picker in settings
- **Voice name resolution** — looking up a voice name when you paste a voice ID

The free ElevenLabs tier is sufficient for typical usage — announcements are short phrases (2-5 words) and only fire on session completion or permission requests.

## Header Bar Controls

The panel header bar contains the following controls (left to right):

| Control | Icon | Description |
|---------|------|-------------|
| Collapse toggle | ▶ / ▼ | Click to collapse/expand the session list. State persists across restarts |
| Status summary | colored dots | Counts of attention (orange), working (cyan), and done (green) sessions |
| Session count | number | Total active sessions |
| Usage | 📊 | Opens the usage quota popover. Icon tints green/yellow/red based on worst quota. Hidden when usage tracking is disabled |
| Settings | ⚙️ | Opens the settings popover |

## Usage Popover

Click the bar chart icon (📊) in the header to see your Claude Code quota:

- **Session (5h)** — progress bar + reset countdown for the rolling 5-hour usage window
- **Weekly (7d)** — progress bar + reset countdown for the rolling 7-day window
- **Per-model breakdown** — Opus and Sonnet usage shown separately when non-zero
- **Credits** — extra usage spend vs. limit, shown when enabled on your plan
- **Refresh button** — manually triggers a fetch (rate-limited to once per 2 minutes)

### How credentials are read

The usage feature requires an OAuth token from Claude Code. It reads credentials automatically from:

1. `~/.claude/.credentials.json` (if it exists)
2. macOS Keychain — service `Claude Code-credentials`

The token is **cached in memory** after the first read. The Keychain is only accessed again when the token approaches expiry. On the first access, macOS will prompt you to allow `claude_monitor` to read the credential — click **Always Allow** to avoid future prompts.

If you see "No credentials", make sure you're logged in to Claude Code via OAuth (`claude login`).

### Polling behavior

| Setting | Value |
|---------|-------|
| Poll interval | Every 5 minutes |
| Popover open | Re-fetches only if last data is > 2 minutes old |
| On rate limit (429) | Backs off: 5min → 10min → 15min (cap) |
| On auth failure (401) | Clears cached token, retries on next poll |
| On success after backoff | Resets to 5 minutes |

## Settings Popover

Click the gear icon in the panel header to access settings at runtime:

- **Refresh sessions** — scans for running Claude processes and creates session files for any that aren't tracked
- **Usage tracking on/off** — toggles `usage.enabled`. When off, hides the bar chart icon and stops all credential access and API polling
- **Voice on/off** — toggles `announce.enabled`
- **Voice picker** — select from saved + library voices
- **Paste voice ID** — reads your clipboard, resolves the voice name via API, saves it to the `voices` array
- **Generate voice** — designs a custom AI voice from `voice_design_prompt`, saves it to your ElevenLabs account, and sets it as the active voice. Only appears when a design prompt is configured.

Changes made through the popover are persisted to `config.json` immediately.
