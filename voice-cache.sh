#!/bin/bash
# Voice cache: play pre-generated audio, generate on cache miss via ElevenLabs.
#
# Usage: voice-cache.sh "phrase" [volume]
#
# Checks phrases.json for per-phrase voice settings (stability, style, text overrides).
# Cache key is a sanitized filename from the phrase.
# On miss: calls ElevenLabs API with phrase-specific settings, saves mp3, plays.
# On hit: plays immediately (~10ms).

set -euo pipefail

PHRASE="${1:-}"
VOLUME="${2:-0.5}"

if [ -z "$PHRASE" ]; then
    echo "Usage: voice-cache.sh 'phrase' [volume]" >&2
    exit 1
fi

CACHE_DIR="$HOME/.claude/voice-cache"
CONFIG_FILE="$HOME/.claude/monitor/config.json"
PHRASES_FILE="$CACHE_DIR/phrases.json"

mkdir -p "$CACHE_DIR"

# Generate cache key: lowercase, spaces to dashes, strip non-alnum
PHRASE_LOWER=$(echo "$PHRASE" | tr '[:upper:]' '[:lower:]')
CACHE_KEY=$(echo "$PHRASE_LOWER" | tr ' ' '-' | tr -cd 'a-z0-9-')
CACHE_FILE="$CACHE_DIR/${CACHE_KEY}.mp3"

# Cache hit — just play it
if [ -f "$CACHE_FILE" ]; then
    afplay -v "$VOLUME" "$CACHE_FILE" &
    disown 2>/dev/null
    exit 0
fi

# Cache miss — generate with ElevenLabs

# Read env_file path from config, resolve ~
ENV_FILE=$(jq -r '.elevenlabs.env_file // empty' "$CONFIG_FILE" 2>/dev/null)
ENV_FILE="${ENV_FILE/#\~/$HOME}"

if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    set -a; source "$ENV_FILE"; set +a
fi

VOICE_ID=$(jq -r '.elevenlabs.voice_id // empty' "$CONFIG_FILE" 2>/dev/null)
VOICE_ID="${VOICE_ID:-${ELEVENLABS_VOICE_ID:-}}"
MODEL=$(jq -r '.elevenlabs.model // "eleven_multilingual_v2"' "$CONFIG_FILE" 2>/dev/null)

# Default voice settings from config
DEF_STABILITY=$(jq -r '.elevenlabs.stability // 0.5' "$CONFIG_FILE" 2>/dev/null)
DEF_SIMILARITY=$(jq -r '.elevenlabs.similarity_boost // 0.75' "$CONFIG_FILE" 2>/dev/null)

if [ -z "${ELEVENLABS_API_KEY:-}" ] || [ -z "$VOICE_ID" ]; then
    echo "No ElevenLabs credentials. Cannot generate." >&2
    say -v "Zoe (Premium)" -r 200 "$PHRASE" &
    disown 2>/dev/null
    exit 0
fi

# Check phrases.json for per-phrase settings
JSON_PAYLOAD=$(python3 -c "
import json, sys, os

phrase_lower = sys.argv[1]
model = sys.argv[2]
def_stability = float(sys.argv[3])
def_similarity = float(sys.argv[4])
phrases_file = sys.argv[5]

# Load phrase-specific settings if available
text = phrase_lower  # default: use the phrase as-is
stability = def_stability
similarity = def_similarity
style = 0.0
speed = 1.0
use_speaker_boost = True

if os.path.exists(phrases_file):
    try:
        phrases = json.load(open(phrases_file))
        if phrase_lower in phrases:
            p = phrases[phrase_lower]
            text = p.get('text', phrase_lower)
            stability = p.get('stability', def_stability)
            similarity = p.get('similarity_boost', def_similarity)
            style = p.get('style', 0.0)
            speed = p.get('speed', 1.0)
    except:
        pass

payload = {
    'text': text,
    'model_id': model,
    'voice_settings': {
        'stability': stability,
        'similarity_boost': similarity,
        'style': style,
        'use_speaker_boost': use_speaker_boost
    }
}

print(json.dumps(payload))
" "$PHRASE_LOWER" "$MODEL" "$DEF_STABILITY" "$DEF_SIMILARITY" "$PHRASES_FILE")

# Call ElevenLabs API
HTTP_CODE=$(curl -s -w '%{http_code}' -X POST \
    "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" \
    -o "$CACHE_FILE")

if [ "$HTTP_CODE" = "200" ] && [ -s "$CACHE_FILE" ]; then
    afplay -v "$VOLUME" "$CACHE_FILE" &
    disown 2>/dev/null
else
    rm -f "$CACHE_FILE"
    say -v "Zoe (Premium)" -r 200 "$PHRASE" &
    disown 2>/dev/null
fi
