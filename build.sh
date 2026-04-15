#!/bin/bash
# ~/.claude/monitor/build.sh
# Compile and launch Claude Monitor floating panel

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_FILE="$SCRIPT_DIR/claude_monitor.swift"
BINARY="$SCRIPT_DIR/claude_monitor"

# Check dependencies
if ! command -v swiftc >/dev/null 2>&1; then
    echo "Error: Swift compiler not found."
    echo "Install Xcode Command Line Tools: xcode-select --install"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq not found. The hook scripts require it."
    echo "Install with: brew install jq"
    exit 1
fi

echo "Compiling Claude Monitor..."
swiftc "$SWIFT_FILE" \
    -O \
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

if [ "${CLAUDE_MONITOR_BUILD_ONLY:-0}" = "1" ]; then
    echo "Skipping restart (CLAUDE_MONITOR_BUILD_ONLY=1)."
    exit 0
fi

# Create config.json from template if it doesn't exist
CONFIG_FILE="$SCRIPT_DIR/config.json"
DEFAULT_CONFIG="$SCRIPT_DIR/config.default.json"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$DEFAULT_CONFIG" ]; then
    cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
    echo "Created config.json from config.default.json"
fi

# Ensure runtime directories exist before launch so the app can arm its file watcher immediately
mkdir -p "$SCRIPT_DIR/sessions"

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

# Always sync monitor scripts to hooks directory
for hook in monitor.sh monitor_permission.py codex_notify.py install_codex_notify.py session_cleanup.py; do
    if [ -f "$SCRIPT_DIR/$hook" ]; then
        cp "$SCRIPT_DIR/$hook" "$HOOKS_DIR/$hook"
        chmod +x "$HOOKS_DIR/$hook"
        echo "Synced $hook to $HOOKS_DIR"
    fi
done

# Install the Codex launcher wrapper without touching the user's global Codex config.
BIN_DIR="$HOME/.claude/bin"
if [ -f "$SCRIPT_DIR/codex-monitor.sh" ]; then
    mkdir -p "$BIN_DIR"
    cp "$SCRIPT_DIR/codex-monitor.sh" "$BIN_DIR/codex-monitor"
    chmod +x "$BIN_DIR/codex-monitor"
    echo "Installed codex-monitor to $BIN_DIR"
fi

if [ -f "$HOOKS_DIR/install_codex_notify.py" ]; then
    python3 "$HOOKS_DIR/install_codex_notify.py"
fi

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
