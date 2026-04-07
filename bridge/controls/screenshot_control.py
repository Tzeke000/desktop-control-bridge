from __future__ import annotations

from datetime import datetime
from pathlib import Path

import pyautogui

from bridge.config import get_settings

pyautogui.FAILSAFE = False


def capture_to_file(filename: str | None = None) -> Path:
    s = get_settings()
    out_dir = s.screenshot_dir
    if not out_dir.is_absolute():
        out_dir = s.base_dir / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    name = filename or datetime.now().strftime("screenshot-%Y%m%d-%H%M%S.png")
    if not name.lower().endswith(".png"):
        name += ".png"
    path = out_dir / name
    img = pyautogui.screenshot()
    img.save(str(path))
    return path
