#!/usr/bin/env python3

import json
import os
import sys
import time


def main() -> int:
    if len(sys.argv) != 4:
        return 1

    session_file, done_updated_at, permission_file = sys.argv[1:4]
    time.sleep(5)

    if not os.path.exists(session_file):
        return 0

    try:
        with open(session_file, "r", encoding="utf-8") as handle:
            session = json.load(handle)
    except Exception:
        return 0

    if session.get("status") == "done" and session.get("updated_at") == done_updated_at:
        for path in (session_file, permission_file):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
