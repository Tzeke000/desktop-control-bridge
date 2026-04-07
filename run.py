"""Launch the system-tray controller (starts the API on 127.0.0.1)."""

from dotenv import load_dotenv

load_dotenv()

try:
    from bridge.win_stdio_utf8 import apply as _win_stdio_utf8

    _win_stdio_utf8()
except Exception:
    pass

from bridge.tray import run_tray

if __name__ == "__main__":
    run_tray()
