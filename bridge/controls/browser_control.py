from __future__ import annotations

import os
import re
import subprocess
import webbrowser
from pathlib import Path
from urllib.parse import quote_plus


_URL_RE = re.compile(r"^https?://", re.I)


def _ensure_url(url: str) -> str:
    u = url.strip()
    if not u:
        raise ValueError("url is empty")
    if not _URL_RE.match(u):
        return "https://" + u
    return u


def _chrome_exe() -> str | None:
    candidates = [
        os.environ.get("PROGRAMFILES", r"C:\Program Files")
        + r"\Google\Chrome\Application\chrome.exe",
        os.environ.get("PROGRAMFILES(X86)", r"C:\Program Files (x86)")
        + r"\Google\Chrome\Application\chrome.exe",
        str(Path.home() / r"AppData\Local\Google\Chrome\Application\chrome.exe"),
    ]
    for c in candidates:
        if c and Path(c).is_file():
            return c
    return None


def open_url(url: str, *, browser: str = "default") -> None:
    u = _ensure_url(url)
    b = browser.lower().strip()
    if b == "default":
        webbrowser.open(u)
        return
    if b == "chrome":
        chrome = _chrome_exe()
        if not chrome:
            raise RuntimeError("Google Chrome not found in standard locations")
        subprocess.Popen([chrome, u], shell=False)
        return
    raise ValueError("browser must be 'default' or 'chrome'")


def new_browser_tab() -> None:
    # Works for most browsers with focus on browser window
    import pyautogui

    pyautogui.hotkey("ctrl", "t")


def focus_address_bar() -> None:
    import pyautogui

    pyautogui.hotkey("ctrl", "l")


def type_search_query(query: str) -> None:
    import pyautogui

    q = quote_plus(query.strip())
    url = f"https://www.google.com/search?q={q}"
    pyautogui.hotkey("ctrl", "l")
    pyautogui.sleep(0.05)
    pyautogui.write(url, interval=0.01)
    pyautogui.press("enter")
