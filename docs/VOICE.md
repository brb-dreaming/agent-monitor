# Voice Setup

Agent Monitor speaks out loud when sessions finish or need attention. Voice works out of the box with macOS built-in speech -- no setup required.

## Providers

| Provider | Quality | Setup | How it works |
|----------|---------|-------|--------------|
| `say` (default) | Good | None | macOS built-in speech -- works immediately |
| `cache` (recommended) | Best | ElevenLabs API key | Pre-generates audio once per phrase, caches as MP3, instant replay |
| `elevenlabs` | Best | ElevenLabs API key | Real-time API call per announcement (no caching) |

## macOS voices (default -- zero setup)

Voice announcements work out of the box using your Mac's built-in speech synthesizer. The default voice is **Zoe (Premium)** at 50% volume. If Zoe isn't installed, macOS falls back to its system default automatically.

**Installing better voices** (recommended -- they sound much better than the defaults):

1. Open **System Settings** > **Accessibility** > **Spoken Content** > **System Voice** > **Manage Voices**
2. Browse and download voices you like (Zoe, Ava, Tom, etc. -- look for "Premium" or "Enhanced" variants)
3. Update your `config.json` with the exact voice name:

```json
{
  "tts_provider": "say",
  "say": { "voice": "Zoe (Premium)", "rate": 200 }
}
```

Run `say -v '?'` in Terminal to list all installed voices and their exact names.

## Voice cache -- AI voices with instant playback (recommended upgrade)

The `cache` provider gives you ElevenLabs AI voice quality with near-zero latency:

1. When the monitor needs to announce a phrase (e.g., "my-project done"), it checks `~/.claude/voice-cache/` for a cached MP3
2. **Cache hit** -- plays the MP3 instantly (~10ms). No API call, no network, no delay
3. **Cache miss** -- calls ElevenLabs to generate the audio, saves the MP3 to the cache, and plays it

Since announcements follow predictable patterns (`"project-name done"`, `"project-name needs attention"`), most phrases are generated once during your first session with a project and cached forever after.

### Setup

1. **Get an ElevenLabs API key** -- sign up at [elevenlabs.io](https://elevenlabs.io) (free tier works -- you only generate each phrase once)

2. **Save your key** -- copy the included example and add your key:
   ```bash
   cp .env.example ~/.env
   # edit ~/.env and paste your ELEVENLABS_API_KEY
   ```

3. **Choose a voice ID** -- either use an existing voice from your ElevenLabs account or copy a `voice_id` to your clipboard and use **Paste voice ID** in the settings popover.

4. **Switch to cache mode** -- update your `config.json`:
   ```json
   {
     "tts_provider": "cache",
     "elevenlabs": {
       "env_file": "~/.env"
     }
   }
   ```

5. **Done.** The first time each phrase is announced, you'll hear a brief delay while the MP3 is generated. Every time after that, it's instant.

### Phrase tuning

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

The cache key is the phrase lowercased with spaces replaced by dashes: `"my project done"` -> `my-project-done.mp3`.

### Managing the cache

```bash
# See all cached phrases
ls ~/.claude/voice-cache/*.mp3

# Regenerate a specific phrase (delete + next announcement re-generates)
rm ~/.claude/voice-cache/my-project-done.mp3

# Clear entire cache (all phrases regenerate on next use)
rm ~/.claude/voice-cache/*.mp3
```

### Other ways to pick a voice

- **Paste a voice ID** -- copy any voice ID to your clipboard, click "Paste voice ID" in settings -- the app resolves the name and saves it
## ElevenLabs real-time (no caching)

If you prefer fresh API calls for every announcement (e.g., you're experimenting with voice settings), set `tts_provider` to `"elevenlabs"` instead of `"cache"`. Same setup as above, but audio is generated on each announcement and not saved.

## Fallback behavior

Both `cache` and `elevenlabs` providers automatically fall back to macOS `say` if the ElevenLabs API is unavailable (no API key, network error, rate limit). You never miss an announcement.

## Volume and event toggles

All toggleable from the settings popover or directly in `config.json`:

| Setting | Default | Description |
|---------|---------|-------------|
| `announce.enabled` | `true` | Master on/off (also togglable from the gear icon) |
| `announce.volume` | `0.5` | Volume from `0.0` (silent) to `1.0` (full) |
| `announce.on_done` | `true` | Speak when a session finishes |
| `announce.on_attention` | `true` | Speak when a session needs permission |
| `announce.on_start` | `false` | Speak when a session starts |
