"""
CLI: put exact text on the Windows clipboard without going through Notepad.

Reads: file path as first arg, or '-' for stdin. Does not echo payload unless CLIPBOARD_STAGE_ECHO=1.
Exit 0 on success, 1 on failure.
"""

from __future__ import annotations

import argparse
import os
import sys

import pyperclip


def main() -> int:
    p = argparse.ArgumentParser(description="Stage exact UTF-8 text to clipboard (pyperclip).")
    p.add_argument(
        "source",
        nargs="?",
        default="",
        help="Path to UTF-8 file, or '-' for stdin.",
    )
    args = p.parse_args()
    src = (args.source or "").strip()
    if not src:
        print("[FAIL] clipboard_stage.py: pass file path or '-'", file=sys.stderr)
        return 1
    try:
        if src == "-":
            text = sys.stdin.read()
        else:
            path = os.path.expanduser(src)
            with open(path, encoding="utf-8", newline="") as f:
                text = f.read()
    except OSError as e:
        print(f"[FAIL] clipboard_stage.py: {e}", file=sys.stderr)
        return 1
    try:
        pyperclip.copy(text)
    except Exception as e:
        print(f"[FAIL] clipboard_stage.py: clipboard {e}", file=sys.stderr)
        return 1
    n = len(text.encode("utf-8"))
    lines = 0 if not text else text.count("\n") + 1
    print(f"[PASS] clipboard_stage.py bytes={n} lines={lines}")
    if os.environ.get("CLIPBOARD_STAGE_ECHO", "").strip() in ("1", "true", "yes"):
        print("--- payload begin (unsafe) ---")
        print(text, end="" if text.endswith("\n") else "\n")
        print("--- payload end ---")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
