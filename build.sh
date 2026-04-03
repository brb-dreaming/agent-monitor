#!/bin/bash
# ~/.claude/monitor/build.sh
# Compile and launch Claude Monitor floating panel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_FILE="$SCRIPT_DIR/claude_monitor.swift"
BINARY="$SCRIPT_DIR/claude_monitor"

echo "Compiling Claude Monitor..."
swiftc "$SWIFT_FILE" \
    -o "$BINARY" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework Combine \
    -framework Security \
    -parse-as-library \
    -suppress-warnings \
    2>&1

if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

echo "Build successful."

# Create config.json from template if it doesn't exist
CONFIG_FILE="$SCRIPT_DIR/config.json"
DEFAULT_CONFIG="$SCRIPT_DIR/config.default.json"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$DEFAULT_CONFIG" ]; then
    cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
    echo "Created config.json from config.default.json"
fi

# Always sync voice-cache.sh to hooks directory (keeps it up to date with repo)
HOOKS_DIR="$HOME/.claude/hooks"
VOICE_CACHE_SRC="$SCRIPT_DIR/voice-cache.sh"
VOICE_CACHE_DST="$HOOKS_DIR/voice-cache.sh"
if [ -f "$VOICE_CACHE_SRC" ]; then
    mkdir -p "$HOOKS_DIR"
    cp "$VOICE_CACHE_SRC" "$VOICE_CACHE_DST"
    chmod +x "$VOICE_CACHE_DST"
    echo "Synced voice-cache.sh to $HOOKS_DIR"
fi

# Always sync monitor.sh and monitor_permission.py to hooks directory
for hook in monitor.sh monitor_permission.py; do
    if [ -f "$SCRIPT_DIR/$hook" ]; then
        cp "$SCRIPT_DIR/$hook" "$HOOKS_DIR/$hook"
        chmod +x "$HOOKS_DIR/$hook"
        echo "Synced $hook to $HOOKS_DIR"
    fi
done

# Initialize voice cache directory + phrases.json (only creates if missing — user edits are preserved)
VOICE_CACHE_DIR="$HOME/.claude/voice-cache"
mkdir -p "$VOICE_CACHE_DIR"
if [ ! -f "$VOICE_CACHE_DIR/phrases.json" ] && [ -f "$SCRIPT_DIR/phrases.json" ]; then
    cp "$SCRIPT_DIR/phrases.json" "$VOICE_CACHE_DIR/phrases.json"
    echo "Created phrases.json in $VOICE_CACHE_DIR"
fi

# Kill existing instance if running
pkill -f "claude_monitor$" 2>/dev/null || true
sleep 0.5

# Launch
echo "Launching Claude Monitor..."
"$BINARY" &
disown 2>/dev/null

echo "Claude Monitor is running."
