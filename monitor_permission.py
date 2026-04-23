#!/usr/bin/env python3
"""
Agent Monitor — PermissionRequest hook via Unix domain socket.
Connects to the monitor app's socket, sends permission details,
blocks until the app responds with allow/deny, then outputs JSON.
"""

import json
import socket
import sys
import os
import re

SOCKET_PATH = os.path.expanduser("~/.claude/monitor/monitor.sock")
TIMEOUT_SECONDS = 300  # 5 min max wait for user response
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]+$")

def main():
    input_data = json.loads(sys.stdin.read())

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})
    session_id = input_data.get("session_id", "")

    if not SESSION_ID_RE.fullmatch(session_id):
        sys.exit(0)

    # Build display text
    if tool_name == "Bash":
        display = tool_input.get("command", "")[:300]
    elif tool_name in ("Edit", "Write", "Read"):
        display = tool_input.get("file_path", "")
    else:
        display = json.dumps(tool_input)[:300]

    # Also write .permission file for the monitor UI
    sessions_dir = os.path.expanduser("~/.claude/monitor/sessions")
    perm_file = os.path.join(sessions_dir, f"{session_id}.permission")
    perm_data = {
        "tool_name": tool_name,
        "display": display,
        "tool_input": json.dumps(tool_input),
        "timestamp": input_data.get("hook_event_name", ""),
    }
    tmp_file = perm_file + ".tmp"
    try:
        os.makedirs(sessions_dir, exist_ok=True)
        with open(tmp_file, "w") as f:
            json.dump(perm_data, f)
        os.replace(tmp_file, perm_file)
    except Exception:
        pass

    # Connect to monitor app socket
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(TIMEOUT_SECONDS)
    try:
        sock.connect(SOCKET_PATH)
    except (ConnectionRefusedError, FileNotFoundError):
        # Monitor app not running — clean up and fall through to terminal dialog
        cleanup(perm_file)
        sys.exit(0)

    # Send permission request
    request = {
        "type": "permission_request",
        "session_id": session_id,
        "tool_name": tool_name,
        "display": display,
        "tool_input": json.dumps(tool_input),
    }
    try:
        sock.sendall(json.dumps(request).encode())
    except Exception:
        cleanup(perm_file)
        sock.close()
        sys.exit(0)

    # Block waiting for response from the monitor app
    try:
        response_data = sock.recv(4096)
        sock.close()
    except socket.timeout:
        cleanup(perm_file)
        sock.close()
        sys.exit(0)
    except Exception:
        cleanup(perm_file)
        sock.close()
        sys.exit(0)

    if not response_data:
        cleanup(perm_file)
        sys.exit(0)

    try:
        response = json.loads(response_data.decode())
    except Exception:
        cleanup(perm_file)
        sys.exit(0)

    decision = response.get("decision", "")
    cleanup(perm_file)

    if decision == "allow":
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        }
        print(json.dumps(output))
        sys.exit(0)
    elif decision == "deny":
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "deny",
                    "message": "Denied from Agent Monitor",
                },
            }
        }
        print(json.dumps(output))
        sys.exit(0)
    else:
        # "terminal" or unknown — fall through
        sys.exit(0)


def cleanup(perm_file):
    try:
        os.remove(perm_file)
    except FileNotFoundError:
        pass


if __name__ == "__main__":
    main()
