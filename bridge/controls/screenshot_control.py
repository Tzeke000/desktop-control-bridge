from __future__ import annotations

import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import pyautogui

from bridge.config import get_settings

pyautogui.FAILSAFE = False


@dataclass(frozen=True)
class ScreenshotResult:
    """original: project screenshot dir; workspace: OpenClaw-readable copy."""

    original: Path
    workspace: Path


def capture_to_file(filename: str | None = None) -> ScreenshotResult:
    s = get_settings()
    out_dir = s.screenshot_dir
    if not out_dir.is_absolute():
        out_dir = s.base_dir / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    name = filename or datetime.now().strftime("screenshot-%Y%m%d-%H%M%S.png")
    if not name.lower().endswith(".png"):
        name += ".png"
    original = out_dir / name
    img = pyautogui.screenshot()
    img.save(str(original))

    vision_root = s.vision_workspace_dir
    if not vision_root.is_absolute():
        vision_root = s.base_dir / vision_root
    vision_root.mkdir(parents=True, exist_ok=True)
    workspace_copy = vision_root / original.name

    if original.resolve() == workspace_copy.resolve():
        return ScreenshotResult(original=original, workspace=workspace_copy)

    shutil.copy2(original, workspace_copy)
    return ScreenshotResult(original=original, workspace=workspace_copy)
