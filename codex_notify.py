#!/usr/bin/env python3

import json
import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Union


def utc_now() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def truncate(text: str, limit: int = 200) -> str:
    return text[:limit]


def load_event(raw: str) -> Optional[Dict[str, Any]]:
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict):
        return None
    return payload


def load_json(path: Path) -> Dict[str, Any]:
    try:
        data = json.loads(path.read_text())
        if isinstance(data, dict):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {}


def atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temp_path = Path(handle.name)
    temp_path.replace(path)


def hook_script_path() -> Path:
    return Path.home() / ".claude" / "hooks" / "codex_notify.py"


def is_self_command(command: Union[List[str], str]) -> bool:
    self_path = str(hook_script_path())
    if isinstance(command, list):
        return any(Path(part).expanduser() == Path(self_path) for part in command)
    return self_path in command


def load_chain_command() -> Optional[Union[List[str], str]]:
    chain_path = Path.home() / ".claude" / "monitor" / "codex_notify_chain.json"
    try:
        data = json.loads(chain_path.read_text())
    except (OSError, json.JSONDecodeError):
        return None

    command = data.get("command")
    if isinstance(command, list) and all(isinstance(part, str) for part in command):
        if is_self_command(command):
            return None
        return command
    if isinstance(command, str) and command.strip():
        if is_self_command(command):
            return None
        return command
    return None


def run_chained_notifier(raw_event: str) -> None:
    command = load_chain_command()
    if not command:
        return

    try:
        if isinstance(command, list):
            subprocess.run(command + [raw_event], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        else:
            subprocess.run(
                ["/bin/sh", "-c", f"{command} {shlex.quote(raw_event)}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
    except Exception:
        pass


def choose_session_id(sessions_dir: Path, session_id: str, cwd: str, thread_id: str) -> Optional[str]:
    if session_id:
        return session_id

    cwd_matches: List[str] = []
    for path in sessions_dir.glob("*.json"):
        session = load_json(path)
        if session.get("agent") != "codex":
            continue
        if thread_id and session.get("thread_id") == thread_id:
            return str(session.get("session_id") or "").strip() or None
        if cwd and session.get("cwd") == cwd:
            cwd_matches.append(str(session.get("session_id") or "").strip())

    if thread_id:
        safe_thread = "".join(ch for ch in thread_id if ch.isalnum() or ch in "-_")
        if safe_thread:
            return f"codex-{safe_thread}"

    matches = [match for match in cwd_matches if match]
    if len(matches) == 1:
        return matches[0]
    return None


def update_session_file(session_file: Path, session_id: str, cwd: str, thread_id: str, prompt: str, updated_at: str) -> None:
    session = load_json(session_file)
    if not session:
        project = Path(cwd).name if cwd else "unknown"
        session = {
            "session_id": session_id,
            "project": project,
            "cwd": cwd,
            "terminal": "",
            "terminal_session_id": "",
            "started_at": updated_at,
        }

    session["session_id"] = session_id
    session["agent"] = "codex"
    session["status"] = "done"
    session["cwd"] = cwd or session.get("cwd", "")
    session["project"] = session.get("project") or (Path(cwd).name if cwd else "unknown")
    session["updated_at"] = updated_at
    session.setdefault("started_at", updated_at)
    session.setdefault("terminal", "")
    session.setdefault("terminal_session_id", "")
    session.setdefault("last_prompt", "")

    if thread_id:
        session["thread_id"] = thread_id
    if prompt:
        session["last_prompt"] = prompt

    atomic_write_json(session_file, session)


def main() -> int:
    if len(sys.argv) < 2:
        return 0

    raw_event = sys.argv[1]
    event = load_event(raw_event)
    if not event or event.get("type") != "agent-turn-complete":
        return 0

    monitor_dir = Path(os.environ.get("CLAUDE_MONITOR_DIR", str(Path.home() / ".claude" / "monitor")))
    sessions_dir = monitor_dir / "sessions"
    thread_id = str(event.get("thread-id") or "").strip()
    cwd = str(event.get("cwd") or os.environ.get("CLAUDE_MONITOR_CWD", "")).strip()
    input_messages = event.get("input-messages")
    prompt = ""
    if isinstance(input_messages, list) and input_messages:
        prompt = truncate(str(input_messages[0]).strip())
    session_id = choose_session_id(
        sessions_dir=sessions_dir,
        session_id=str(os.environ.get("CLAUDE_MONITOR_SESSION_ID", "")).strip(),
        cwd=cwd,
        thread_id=thread_id,
    )
    if not session_id:
        return 0

    session_file = sessions_dir / f"{session_id}.json"
    should_autoclean = not session_file.exists() and session_id.startswith("codex-")
    updated_at = utc_now()
    update_session_file(session_file, session_id, cwd, thread_id, prompt, updated_at)

    monitor_hook = Path.home() / ".claude" / "hooks" / "monitor.sh"
    if monitor_hook.exists():
        payload = json.dumps({"session_id": session_id, "cwd": cwd})
        env = dict(os.environ)
        env["CLAUDE_MONITOR_AGENT"] = "codex"
        if thread_id:
            env["CLAUDE_MONITOR_THREAD_ID"] = thread_id
        if should_autoclean:
            env["CLAUDE_MONITOR_AUTOCLEAN_DONE"] = "1"
        subprocess.run(
            [str(monitor_hook), "Stop"],
            input=payload,
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            check=False,
        )

    run_chained_notifier(raw_event)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
