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

# Kill existing instance if running
pkill -f "claude_monitor$" 2>/dev/null || true
sleep 0.5

# Launch
echo "Launching Claude Monitor..."
"$BINARY" &
disown 2>/dev/null

echo "Claude Monitor is running."
