# Claude Monitor

A floating macOS dashboard for Claude Code sessions with voice announcements, permission granting, and usage tracking.

## Project structure

- `claude_monitor.swift` — single-file SwiftUI app (floating panel)
- `build.sh` — compile, sync hooks, create config, launch
- `monitor.sh` — lifecycle hook script (SessionStart/Stop/etc + TTS)
- `monitor_permission.py` — permission granting via Unix socket IPC
- `voice-cache.sh` — ElevenLabs TTS with local MP3 caching
- `config.default.json` — default config template (tracked in git, safe defaults)
- `config.json` — user's live config (gitignored, created from template on first build)
- `phrases.json` — per-phrase voice tuning template

## Skins

Three built-in skins, selectable from the settings popover:

1. **Glass** (default) — Pure frosted glass with background blur. Clean white text, colored status dots as the only color signal. Uses `NSVisualEffectView` with configurable blur/opacity/tint via `GlassConfig`. Tint saturation slider available in settings when active. 16px corner radius, hairline border.

2. **Obsidian** — Dark neumorphic skin inspired by dark-on-dark UI design. Solid dark gradient background (no blur-through), top-edge highlight that fades along the sides, deep shadow. All depth comes from shadows, not strokes. Muted grey text with status dots as the only color. 16px corner radius.

3. **Terminal** — Retro phosphor green CRT aesthetic. Monospaced font throughout, near-black background with green tint, warm phosphor green text hierarchy. 6px corner radius for an angular feel.

## Installation guidance

When a user asks you to install Claude Monitor, **ask them about their voice preferences before creating the config**. Walk them through these choices:

### Voice provider (`tts_provider`)

There are three options. Explain each and ask which they'd like:

1. **`say`** (default) — Uses macOS built-in speech. Zero setup, works immediately. Good quality, especially with Premium voices (Zoe, Ava, Tom). Best for: users who want it working right now with no API keys.

2. **`cache`** (recommended for best quality) — Uses ElevenLabs AI voices with smart caching. Each phrase is generated once via API, saved as MP3, and replayed instantly (~10ms) on every future announcement. Only costs one API call per unique phrase. Best for: users who want high-quality AI voice without per-announcement latency. Requires an ElevenLabs API key (free tier works).

3. **`elevenlabs`** (real-time, no caching) — Fresh ElevenLabs API call per announcement. Best for: users experimenting with voice settings who don't want cached audio. Same setup as `cache` but generates audio every time. Note: this adds 1-3 seconds of latency per announcement since the hook blocks until the API responds.

### Announcement events (`announce.*`)

Ask which events they want voice announcements for:
- **`on_done`** (default: on) — "project-name done" when Claude finishes
- **`on_attention`** (default: on) — "project-name needs attention" when permission is needed
- **`on_start`** (default: off) — "project-name starting" when a session begins
- **`volume`** (default: 0.5) — 0.0 to 1.0

### Usage tracking (`usage.enabled`)

Ask if they want to see their Claude Code quota (session + weekly) in the monitor. This reads OAuth credentials from macOS Keychain (one-time permission prompt). Default: on.

### After asking preferences

1. Create `config.json` from `config.default.json` with their chosen settings
2. If they chose `cache` or `elevenlabs`, help them set up their ElevenLabs API key (copy `.env.example` to `~/.env`, paste key)
3. If they chose `cache` or `elevenlabs`, after building, show them the "Generate voice" button in the settings popover to create their custom AI voice

## Build & run

```bash
~/.claude/monitor/build.sh
```

Kill + restart:
```bash
pkill -9 claude_monitor; sleep 1; ~/.claude/monitor/build.sh
```

## Hook architecture

All announce calls in `monitor.sh` MUST be fully detached from the hook process:
```bash
announce "message" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null
```

This is critical because Claude Code waits for all inherited file descriptors to close before considering a hook complete. Without FD redirection, backgrounded TTS (especially ElevenLabs API calls) blocks the hook for the duration of the network request.

## Glass config

The glass skin has independent tuning parameters stored in `config.json` under the `glass` key:
- `blur` — backdrop blur strength (0.0–1.0), controls the CABackdropLayer opacity
- `opacity` — fill/tone layer opacity (0.0–1.0), adds density to the frost
- `tintR/G/B` — tint color RGB (0.0–1.0)
- `tintStrength` — tint layer alpha (0.0–1.0), applied via a CALayer with `softLight` compositing filter

These are manipulated by reaching into `NSVisualEffectView`'s private internal CALayer sublayer tree (backdrop, fill, tone layers) to decouple blur from opacity.

Default: `blur: 1.0, opacity: 0.5, tint: neutral grey, tintStrength: 0.0` (pure frosted glass, no color cast).

## Config defaults

`config.default.json` ships with `tts_provider: "say"` — this is intentional. New users get working voice with zero setup. The `cache` provider is the recommended upgrade path for users who set up ElevenLabs.
