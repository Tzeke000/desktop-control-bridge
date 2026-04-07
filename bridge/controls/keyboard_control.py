from __future__ import annotations

import pyautogui
from bridge.controls.macros import load_macros

pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0.02

# Normalize common aliases to pyautogui names
_KEY_ALIASES = {
    "windows": "winleft",
    "win": "winleft",
    "escape": "esc",
    "del": "delete",
    "ins": "insert",
    "pgup": "pageup",
    "pgdn": "pagedown",
    "break": "pause",
}


def _norm_key(k: str) -> str:
    s = k.lower().strip()
    return _KEY_ALIASES.get(s, s)


def type_text(text: str, interval: float = 0.0) -> None:
    interval = max(0.0, float(interval))
    pyautogui.write(text, interval=interval)


def press_key(key: str) -> None:
    pyautogui.press(_norm_key(key))


def hotkey(keys: list[str]) -> None:
    if not keys:
        raise ValueError("keys list is empty")
    normalized = [_norm_key(k) for k in keys]
    pyautogui.hotkey(*normalized)


def run_macro(name: str) -> None:
    macros = load_macros()
    if name not in macros:
        raise KeyError(f"Unknown macro: {name}")
    hotkey(macros[name])


def paste_safe(text: str) -> None:
    """Put text on clipboard and paste with Ctrl+V (does not log clipboard contents in API layer)."""
    try:
        import pyperclip  # type: ignore
    except ImportError:
        raise RuntimeError(
            "Safe paste requires pyperclip. pip install pyperclip"
        ) from None
    pyperclip.copy(text)
    pyautogui.hotkey("ctrl", "v")
