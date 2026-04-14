#!/bin/bash

set -euo pipefail

MONITOR_DIR="${CLAUDE_MONITOR_DIR:-$HOME/.claude/monitor}"
HOOKS_DIR="$HOME/.claude/hooks"
MONITOR_HOOK="$HOOKS_DIR/monitor.sh"
NOTIFIER="$HOOKS_DIR/codex_notify.py"

if ! command -v jq >/dev/null 2>&1; then
    echo "codex-monitor: jq is required" >&2
    exit 1
fi

CODEX_BIN=$(command -v codex || true)
if [ -z "$CODEX_BIN" ]; then
    echo "codex-monitor: codex not found in PATH" >&2
    exit 1
fi

PYTHON_BIN=$(command -v python3 || true)
if [ -z "$PYTHON_BIN" ]; then
    echo "codex-monitor: python3 not found in PATH" >&2
    exit 1
fi

if [ ! -x "$MONITOR_HOOK" ]; then
    echo "codex-monitor: $MONITOR_HOOK is missing or not executable" >&2
    exit 1
fi

if [ ! -f "$NOTIFIER" ]; then
    echo "codex-monitor: $NOTIFIER is missing" >&2
    exit 1
fi

SESSION_ID="${CLAUDE_MONITOR_SESSION_ID:-codex-$(uuidgen | tr '[:upper:]' '[:lower:]')}"
CWD=$(pwd -P)
PROMPT_TEXT=""
REGISTERED_SESSION=0
CLEANED_UP=0

if [ "${1:-}" = "exec" ] && [ $# -gt 1 ]; then
    PROMPT_TEXT=$(printf '%s ' "${@:2}")
    PROMPT_TEXT="${PROMPT_TEXT% }"
fi

export CLAUDE_MONITOR_AGENT="codex"
export CLAUDE_MONITOR_SESSION_ID="$SESSION_ID"
export CLAUDE_MONITOR_CWD="$CWD"
export CLAUDE_MONITOR_DIR="$MONITOR_DIR"

cleanup() {
    if [ "$CLEANED_UP" -eq 1 ]; then
        return
    fi
    CLEANED_UP=1

    if [ "$REGISTERED_SESSION" -ne 1 ]; then
        return
    fi

    jq -nc \
        --arg session_id "$SESSION_ID" \
        --arg cwd "$CWD" \
        '{session_id:$session_id,cwd:$cwd}' |
        "$MONITOR_HOOK" SessionEnd >/dev/null 2>&1 || true
}

trap cleanup EXIT HUP INT TERM

jq -nc \
    --arg session_id "$SESSION_ID" \
    --arg cwd "$CWD" \
    --arg prompt "$PROMPT_TEXT" \
    '{session_id:$session_id,cwd:$cwd,prompt:$prompt}' |
    "$MONITOR_HOOK" UserPromptSubmit >/dev/null 2>&1
REGISTERED_SESSION=1

NOTIFY_CONFIG=$(printf 'notify=["%s","%s"]' "$PYTHON_BIN" "$NOTIFIER")
set +e
"$CODEX_BIN" -c "$NOTIFY_CONFIG" "$@"
STATUS=$?
set -e
cleanup
exit "$STATUS"
