from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass

import win32con
import win32gui
import win32process

try:
    import psutil
except ImportError:
    psutil = None


@dataclass
class WindowInfo:
    hwnd: int
    title: str
    pid: int | None
    process_name: str | None


def _get_process_name(pid: int | None) -> str | None:
    if pid is None or psutil is None:
        return None
    try:
        return psutil.Process(pid).name().lower()
    except Exception:
        return None


def list_windows() -> list[WindowInfo]:
    results: list[WindowInfo] = []

    def cb(hwnd: int, _: object) -> None:
        if not win32gui.IsWindowVisible(hwnd):
            return
        title = win32gui.GetWindowText(hwnd)
        if not title:
            return
        try:
            _, pid = win32process.GetWindowThreadProcessId(hwnd)
        except Exception:
            pid = None
        results.append(
            WindowInfo(
                hwnd=hwnd,
                title=title,
                pid=pid,
                process_name=_get_process_name(pid),
            )
        )

    win32gui.EnumWindows(cb, None)
    return results


def get_foreground_window() -> WindowInfo | None:
    hwnd = win32gui.GetForegroundWindow()
    if not hwnd:
        return None
    title = win32gui.GetWindowText(hwnd)
    try:
        _, pid = win32process.GetWindowThreadProcessId(hwnd)
    except Exception:
        pid = None
    return WindowInfo(
        hwnd=hwnd,
        title=title or "",
        pid=pid,
        process_name=_get_process_name(pid),
    )


def _match_window(
    *,
    title_substring: str | None = None,
    process_name: str | None = None,
) -> WindowInfo | None:
    windows = list_windows()
    t = (title_substring or "").strip().lower()
    p = (process_name or "").strip().lower()
    if t and p:
        for w in windows:
            if t in w.title.lower() and w.process_name and p in w.process_name:
                return w
        return None
    if t:
        for w in windows:
            if t in w.title.lower():
                return w
        return None
    if p:
        for w in windows:
            if w.process_name and p in w.process_name:
                return w
        return None
    return None


def focus_window(
    *,
    title: str | None = None,
    process_name: str | None = None,
) -> None:
    w = _match_window(title_substring=title, process_name=process_name)
    if not w:
        raise RuntimeError("No matching window found")
    try:
        win32gui.ShowWindow(w.hwnd, win32con.SW_RESTORE)
    except Exception:
        pass
    win32gui.SetForegroundWindow(w.hwnd)


def minimize_window(
    *,
    title: str | None = None,
    process_name: str | None = None,
) -> None:
    w = _match_window(title_substring=title, process_name=process_name)
    if not w:
        raise RuntimeError("No matching window found")
    win32gui.ShowWindow(w.hwnd, win32con.SW_MINIMIZE)


def maximize_window(
    *,
    title: str | None = None,
    process_name: str | None = None,
) -> None:
    w = _match_window(title_substring=title, process_name=process_name)
    if not w:
        raise RuntimeError("No matching window found")
    win32gui.ShowWindow(w.hwnd, win32con.SW_MAXIMIZE)


def close_window(
    *,
    title: str | None = None,
    process_name: str | None = None,
) -> None:
    w = _match_window(title_substring=title, process_name=process_name)
    if not w:
        raise RuntimeError("No matching window found")
    win32gui.PostMessage(w.hwnd, win32con.WM_CLOSE, 0, 0)


def open_application(path_or_name: str) -> None:
    """Open by full path, or resolve a few common names (e.g. notepad, calc)."""
    s = path_or_name.strip().strip('"')
    if not s:
        raise ValueError("path_or_name is empty")

    lower = s.lower()
    aliases = {
        "notepad": "notepad.exe",
        "calc": "calc.exe",
        "calculator": "calc.exe",
        "explorer": "explorer.exe",
        "cmd": "cmd.exe",
        "powershell": "powershell.exe",
    }
    if lower in aliases:
        subprocess.Popen(aliases[lower], shell=False)
        return

    if os.path.isfile(s):
        subprocess.Popen([s], shell=False)
        return

    subprocess.Popen(s, shell=True)
