#!/bin/bash
# ~/.claude/hooks/monitor.sh
# Claude Code lifecycle hook — writes session JSON + triggers TTS
# Called by all 5 hook events: SessionStart, UserPromptSubmit, Stop, Notification, SessionEnd
#
# Usage: monitor.sh <event>
# Receives hook JSON on stdin

set -euo pipefail

EVENT="${1:-unknown}"
INPUT=$(cat)

# --- Paths ---
MONITOR_DIR="$HOME/.claude/monitor"
SESSIONS_DIR="$MONITOR_DIR/sessions"
CONFIG_FILE="$MONITOR_DIR/config.json"

mkdir -p "$SESSIONS_DIR"

# --- Extract context from hook JSON ---
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Need a session ID to do anything useful
if [ -z "$SESSION_ID" ]; then
    exit 0
fi

if ! [[ "$SESSION_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    exit 0
fi

SESSION_FILE="$SESSIONS_DIR/${SESSION_ID}.json"
PROJECT=$(basename "${CWD:-unknown}")
PROJECT_NAME=$(echo "$PROJECT" | sed 's/[-_]/ /g')
NOW=$(python3 - <<'PY'
from datetime import datetime, timezone
print(datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z"))
PY
)
AGENT="${CLAUDE_MONITOR_AGENT:-}"
if [ -z "$AGENT" ] && [ -f "$SESSION_FILE" ]; then
    AGENT=$(jq -r '.agent // empty' "$SESSION_FILE" 2>/dev/null || true)
fi
case "$(printf '%s' "$AGENT" | tr '[:upper:]' '[:lower:]')" in
    codex) AGENT="codex" ;;
    *)     AGENT="claude" ;;
esac
THREAD_ID="${CLAUDE_MONITOR_THREAD_ID:-}"
if [ -n "$THREAD_ID" ] && ! [[ "$THREAD_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    THREAD_ID=""
fi
AUTOCLEAN_DONE="${CLAUDE_MONITOR_AUTOCLEAN_DONE:-0}"

# --- Detect terminal + session ID for click-to-switch ---
detect_terminal() {
    local term_app=""
    local term_session_id=""

    if [ -n "${ITERM_SESSION_ID:-}" ]; then
        echo "iterm2|$ITERM_SESSION_ID"
        return
    fi

    if [ -n "${WEZTERM_PANE:-}" ]; then
        echo "wezterm|$WEZTERM_PANE"
        return
    fi

    # Walk up process tree to find a parent with a real TTY
    local pid=$$
    local tty_name=""
    for _ in 1 2 3 4 5; do
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$pid" ] || [ "$pid" = "1" ] && break
        tty_name=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
        if [ -n "$tty_name" ] && [ "$tty_name" != "??" ]; then
            term_app="terminal"
            term_session_id="/dev/$tty_name"
            break
        fi
    done

    echo "$term_app|$term_session_id"
}

ensure_monitor_running() {
    local binary="$MONITOR_DIR/claude_monitor"
    [ -x "$binary" ] || return 0
    pgrep -f "/\.claude/monitor/claude_monitor\$" >/dev/null 2>&1 && return 0

    local lockdir="$MONITOR_DIR/.relaunch.lock"
    # Clear stale lock (>10s old) left behind by a crashed relauncher
    if [ -d "$lockdir" ]; then
        local lock_age
        lock_age=$(( $(date +%s) - $(stat -f %m "$lockdir" 2>/dev/null || echo 0) ))
        [ "$lock_age" -gt 10 ] && rmdir "$lockdir" 2>/dev/null
    fi

    if mkdir "$lockdir" 2>/dev/null; then
        (
            "$binary" </dev/null >/dev/null 2>&1 &
            disown 2>/dev/null || true
            sleep 3
            rmdir "$lockdir" 2>/dev/null
        ) </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
}

play_say_with_volume() {
    local msg="$1"
    local voice="$2"
    local rate="$3"
    local volume="$4"

    (
        local temp_audio
        temp_audio=$(mktemp -t claude_monitor_say) || exit 1
        if say -v "$voice" -r "$rate" -o "$temp_audio" -- "$msg"; then
            afplay -v "$volume" "$temp_audio"
        fi
        rm -f "$temp_audio"
    ) &
    disown 2>/dev/null
}

# --- TTS announcement ---
announce() {
    local msg="$1"
    local provider voice rate volume

    # Read config
    if [ ! -f "$CONFIG_FILE" ]; then
        return
    fi

    provider=$(jq -r '.tts_provider // "say"' "$CONFIG_FILE")
    volume=$(jq -r '.announce.volume // 0.5' "$CONFIG_FILE")
    # Read say config upfront so all fallback paths can use it
    voice=$(jq -r '.say.voice // "Samantha"' "$CONFIG_FILE")
    rate=$(jq -r '.say.rate // 200' "$CONFIG_FILE")

    if [ "$provider" = "cache" ]; then
        "$HOME/.claude/hooks/voice-cache.sh" "$msg" "$volume" &
        disown 2>/dev/null
    elif [ "$provider" = "elevenlabs" ]; then
        local env_file model stability similarity
        env_file=$(jq -r '.elevenlabs.env_file // empty' "$CONFIG_FILE")
        env_file="${env_file/#\~/$HOME}"
        model=$(jq -r '.elevenlabs.model // "eleven_multilingual_v2"' "$CONFIG_FILE")
        stability=$(jq -r '.elevenlabs.stability // 0.5' "$CONFIG_FILE")
        similarity=$(jq -r '.elevenlabs.similarity_boost // 0.75' "$CONFIG_FILE")

        if [ -f "$env_file" ]; then
            set -a; source "$env_file"; set +a
        fi

        local config_voice_id
        config_voice_id=$(jq -r '.elevenlabs.voice_id // empty' "$CONFIG_FILE")
        if [ -n "$config_voice_id" ]; then
            ELEVENLABS_VOICE_ID="$config_voice_id"
        fi

        if [ -n "${ELEVENLABS_API_KEY:-}" ] && [ -n "${ELEVENLABS_VOICE_ID:-}" ]; then
            local temp_audio="/tmp/claude_monitor_tts_$$.mp3"
            local json_payload
            json_payload=$(jq -n \
                --arg text "$msg" \
                --arg model "$model" \
                --argjson stability "$stability" \
                --argjson similarity "$similarity" \
                '{text:$text,model_id:$model,voice_settings:{stability:$stability,similarity_boost:$similarity}}')

            local http_code
            http_code=$(curl -s -w '%{http_code}' -X POST \
                "https://api.elevenlabs.io/v1/text-to-speech/$ELEVENLABS_VOICE_ID" \
                -H "xi-api-key: $ELEVENLABS_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$json_payload" \
                -o "$temp_audio")

            if [ "$http_code" = "200" ] && [ -s "$temp_audio" ]; then
                afplay -v "$volume" "$temp_audio" &
                disown 2>/dev/null
                (sleep 30 && rm -f "$temp_audio") &
                disown 2>/dev/null
            else
                rm -f "$temp_audio"
                play_say_with_volume "$msg" "$voice" "$rate" "$volume"
            fi
        else
            play_say_with_volume "$msg" "$voice" "$rate" "$volume"
        fi
    else
        play_say_with_volume "$msg" "$voice" "$rate" "$volume"
    fi
}

announcement_text() {
    local event_type="$1"
    local project_label="$PROJECT_NAME"

    if [ "$AGENT" = "codex" ]; then
        project_label="$project_label codex"
    fi

    case "$event_type" in
        done)      echo "$project_label done" ;;
        attention) echo "$project_label needs attention" ;;
        start)     echo "$project_label starting" ;;
        *)         return 1 ;;
    esac
}

# --- Should we announce this event? ---
should_announce() {
    local event_type="$1"
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    # Master toggle
    jq -e '.announce.enabled == true' "$CONFIG_FILE" >/dev/null 2>&1 || return 1

    case "$event_type" in
        done)     jq -e '.announce.on_done == true' "$CONFIG_FILE" >/dev/null 2>&1 ;;
        attention) jq -e '.announce.on_attention == true' "$CONFIG_FILE" >/dev/null 2>&1 ;;
        start)    jq -e '.announce.on_start == true' "$CONFIG_FILE" >/dev/null 2>&1 ;;
        *)        return 1 ;;
    esac
}

# --- Detect terminal once for all events ---
TERM_INFO=$(detect_terminal)
TERM_APP=$(echo "$TERM_INFO" | cut -d'|' -f1)
TERM_SID=$(echo "$TERM_INFO" | cut -d'|' -f2)

# Helper: backfill terminal info + update status on existing session file
update_session() {
    local new_status="$1"
    jq \
        --arg status "$new_status" \
        --arg updated "$NOW" \
        --arg terminal "$TERM_APP" \
        --arg term_sid "$TERM_SID" \
        --arg agent "$AGENT" \
        --arg thread_id "$THREAD_ID" \
        '.status = $status
        | .updated_at = $updated
        | if (.agent // "") == "" then .agent = $agent else . end
        | if $thread_id != "" and (.thread_id // "") == "" then .thread_id = $thread_id else . end
        | if .terminal == "" or ($terminal != "" and .terminal != $terminal) then .terminal = $terminal | .terminal_session_id = $term_sid else . end' \
        "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
}

schedule_session_removal() {
    local session_file="$1"
    local session_id="$2"
    local done_updated_at="$3"
    local permission_file="$SESSIONS_DIR/${session_id}.permission"

    python3 - "$session_file" "$done_updated_at" "$permission_file" <<'PY'
import subprocess
import sys
from pathlib import Path

cleanup_script = Path.home() / ".claude" / "hooks" / "session_cleanup.py"
subprocess.Popen(
    ["python3", str(cleanup_script), sys.argv[1], sys.argv[2], sys.argv[3]],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
    close_fds=True,
)
PY
}

# Helper: create new session file
create_session() {
    local new_status="$1"
    local prompt="${2:-}"
    jq -n \
        --arg sid "$SESSION_ID" \
        --arg agent "$AGENT" \
        --arg thread_id "$THREAD_ID" \
        --arg status "$new_status" \
        --arg project "$PROJECT" \
        --arg cwd "${CWD:-}" \
        --arg terminal "$TERM_APP" \
        --arg term_sid "$TERM_SID" \
        --arg started "$NOW" \
        --arg updated "$NOW" \
        --arg prompt "$prompt" \
        '{
            session_id:$sid,
            agent:$agent,
            status:$status,
            project:$project,
            cwd:$cwd,
            terminal:$terminal,
            terminal_session_id:$term_sid,
            started_at:$started,
            updated_at:$updated,
            last_prompt:$prompt
        } + (if $thread_id != "" then {thread_id:$thread_id} else {} end)' \
        > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    # Clean up any discovered-*.json for the same terminal session (discovery→hook handoff)
    # Handles format differences: iTerm2 discovery stores "GUID", hooks store "w0t0p0:GUID"
    if [ -n "$TERM_SID" ]; then
        for df in "$SESSIONS_DIR"/discovered-*.json; do
            [ -f "$df" ] || continue
            local df_sid df_terminal hook_guid
            df_sid=$(jq -r '.terminal_session_id // ""' "$df" 2>/dev/null)
            df_terminal=$(jq -r '.terminal // ""' "$df" 2>/dev/null)
            [ -z "$df_sid" ] && continue
            if [ "$TERM_APP" = "iterm2" ]; then
                hook_guid="${TERM_SID##*:}"
                if [ "$df_terminal" = "iterm2" ] && { [ "$df_sid" = "$TERM_SID" ] || [ "$df_sid" = "$hook_guid" ]; }; then
                    rm -f "$df"
                fi
            elif [ "$df_terminal" = "$TERM_APP" ] && [ "$df_sid" = "$TERM_SID" ]; then
                rm -f "$df"
            fi
        done
    fi
}

# --- Self-heal: relaunch the UI panel if it's not running ---
ensure_monitor_running

# --- Handle events ---
case "$EVENT" in
    SessionStart)
        create_session "starting"
        if should_announce start; then
            announce "$(announcement_text start)"
        fi
        ;;

    UserPromptSubmit)
        PROMPT_TEXT=$(echo "$INPUT" | jq -r '.prompt // empty' | head -c 200)
        if [ -f "$SESSION_FILE" ]; then
            # Single atomic write: status + prompt + terminal backfill
            jq \
                --arg status "working" \
                --arg updated "$NOW" \
                --arg prompt "$PROMPT_TEXT" \
                --arg terminal "$TERM_APP" \
                --arg term_sid "$TERM_SID" \
                --arg agent "$AGENT" \
                --arg thread_id "$THREAD_ID" \
                '.status = $status
                | .updated_at = $updated
                | .last_prompt = $prompt
                | if (.agent // "") == "" then .agent = $agent else . end
                | if $thread_id != "" and (.thread_id // "") == "" then .thread_id = $thread_id else . end
                | if .terminal == "" or ($terminal != "" and .terminal != $terminal) then .terminal = $terminal | .terminal_session_id = $term_sid else . end' \
                "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
        else
            create_session "working" "$PROMPT_TEXT"
        fi
        ;;

    Stop)
        should_schedule_removal="$AUTOCLEAN_DONE"
        if [ -f "$SESSION_FILE" ]; then
            update_session "done"
        else
            create_session "done"
        fi
        if should_announce done; then
            announce "$(announcement_text done)"
        fi
        if [ "$should_schedule_removal" = "1" ]; then
            schedule_session_removal "$SESSION_FILE" "$SESSION_ID" "$NOW"
        fi
        ;;

    Notification)
        if [ -f "$SESSION_FILE" ]; then
            update_session "attention"
        else
            create_session "attention"
        fi
        # Only announce if PermissionRequest isn't actively handling this
        PERM_FILE="$SESSIONS_DIR/${SESSION_ID}.permission"
        if [ ! -f "$PERM_FILE" ] && should_announce attention; then
            announce "$(announcement_text attention)"
        fi
        ;;

    SessionEnd)
        if [ -f "$SESSION_FILE" ]; then
            update_session "done"
            schedule_session_removal "$SESSION_FILE" "$SESSION_ID" "$NOW"
        fi
        ;;
esac

exit 0
