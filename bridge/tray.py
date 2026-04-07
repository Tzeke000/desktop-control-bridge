from __future__ import annotations

import threading
import webbrowser
from pathlib import Path

import uvicorn
from PIL import Image, ImageDraw
from pystray import Icon, Menu, MenuItem

from bridge.api import app
from bridge.config import get_settings
from bridge.state import state


def _pill_image(color: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (64, 64), (30, 30, 36))
    d = ImageDraw.Draw(img)
    d.ellipse((10, 10, 54, 54), fill=color, outline=(200, 200, 210))
    return img


def _status_label() -> str:
    s = get_settings()
    return f"{state.status} @ 127.0.0.1:{s.bridge_port}"


def _copy_token() -> None:
    try:
        import pyperclip
    except ImportError:
        return
    tok = (get_settings().bridge_token or "").strip()
    if tok:
        pyperclip.copy(tok)


def _open_logs() -> None:
    s = get_settings()
    d = s.log_dir if s.log_dir.is_absolute() else s.base_dir / s.log_dir
    d.mkdir(parents=True, exist_ok=True)
    import os

    os.startfile(str(d))


def _open_env_dir() -> None:
    import os

    os.startfile(str(get_settings().base_dir))


def _open_docs() -> None:
    s = get_settings()
    webbrowser.open(f"http://127.0.0.1:{s.bridge_port}/docs")


def _pause(_: Icon | None = None, __: object | None = None) -> None:
    state.set_status("paused")
    state.record_action("pause (tray)")


def _resume(_: Icon | None = None, __: object | None = None) -> None:
    if state.status != "stopped":
        state.set_status("running")
    state.record_action("resume (tray)")


def _stop(_: Icon | None = None, __: object | None = None) -> None:
    state.set_status("stopped")
    state.record_action("stop (tray)")


def _start_bridge(_: Icon | None = None, __: object | None = None) -> None:
    state.set_status("running")
    state.record_action("start (tray)")


def _launch_dashboard() -> None:
    from bridge import dashboard

    dashboard.open_dashboard_threaded()


def run_tray() -> None:
    s = get_settings()
    host = (s.bridge_host or "127.0.0.1").strip()
    if host != "127.0.0.1":
        raise SystemExit("BRIDGE_HOST must be 127.0.0.1 (localhost IPv4 only).")
    if not (s.bridge_token or "").strip():
        raise SystemExit(
            "BRIDGE_TOKEN is empty. Copy .env.example to .env and set BRIDGE_TOKEN."
        )

    def serve() -> None:
        uvicorn.run(
            app,
            host=host,
            port=s.bridge_port,
            log_level="info",
            access_log=False,
        )

    t = threading.Thread(target=serve, daemon=True)
    t.start()

    icon_green = _pill_image((80, 200, 120))
    icon_amber = _pill_image((220, 180, 60))
    icon_red = _pill_image((220, 80, 80))

    def current_icon() -> Image.Image:
        if state.status == "stopped":
            return icon_red
        if state.status == "paused":
            return icon_amber
        return icon_green

    icon = Icon("desktop_control_bridge")
    icon.icon = current_icon()

    def _updateAppearance(_: object | None = None) -> None:
        icon.icon = current_icon()
        try:
            icon.title = f"Desktop Bridge — {_status_label()}"
        except Exception:
            pass

    icon.menu = Menu(
        MenuItem(lambda t: _status_label(), None, enabled=False),
        Menu.SEPARATOR,
        MenuItem("Resume bridge", _resume, enabled=lambda _: state.status == "paused"),
        MenuItem("Pause bridge", _pause, enabled=lambda _: state.status == "running"),
        MenuItem("Stop bridge (API control off)", _stop),
        MenuItem(
            "Start bridge (enable API)",
            _start_bridge,
            enabled=lambda _: state.status == "stopped",
        ),
        Menu.SEPARATOR,
        MenuItem("Copy token to clipboard", lambda: _copy_token()),
        MenuItem("Open project folder (.env)", _open_env_dir),
        MenuItem("Open logs folder", _open_logs),
        MenuItem("Open API docs in browser", lambda: _open_docs()),
        MenuItem("Status dashboard…", lambda: _launch_dashboard()),
        Menu.SEPARATOR,
        MenuItem("Quit (stops bridge server)", lambda: icon.stop()),
    )

    # Periodically refresh icon for status changes from API
    def tick() -> None:
        _updateAppearance()
        try:
            threading.Timer(1.0, tick).start()
        except Exception:
            pass

    tick()
    icon.run()
