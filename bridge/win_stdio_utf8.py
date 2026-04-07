"""Reconfigure stdio for UTF-8 on Windows so OCR paths and text print cleanly."""

from __future__ import annotations

import sys


def apply() -> None:
    if sys.platform != "win32":
        return
    for name in ("stdout", "stderr"):
        stream = getattr(sys, name, None)
        if stream is None or not hasattr(stream, "reconfigure"):
            continue
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (OSError, ValueError, AttributeError, TypeError):
            pass
