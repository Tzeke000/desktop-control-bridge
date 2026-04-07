"""Headless API server (no tray). For development or automation-only hosts."""

from dotenv import load_dotenv

load_dotenv()

try:
    from bridge.win_stdio_utf8 import apply as _win_stdio_utf8

    _win_stdio_utf8()
except Exception:
    pass

import uvicorn

from bridge.api import app
from bridge.config import get_settings

if __name__ == "__main__":
    s = get_settings()
    host = (s.bridge_host or "127.0.0.1").strip()
    if host != "127.0.0.1":
        raise SystemExit("BRIDGE_HOST must be 127.0.0.1.")
    if not (s.bridge_token or "").strip():
        raise SystemExit("Set BRIDGE_TOKEN in .env before starting.")
    uvicorn.run(app, host=host, port=s.bridge_port, log_level="info")
