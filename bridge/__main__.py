"""Headless API server (no tray). For development or automation-only hosts."""

from dotenv import load_dotenv

load_dotenv()

import uvicorn

from bridge.api import app
from bridge.config import get_settings

if __name__ == "__main__":
    s = get_settings()
    if not (s.bridge_token or "").strip():
        raise SystemExit("Set BRIDGE_TOKEN in .env before starting.")
    uvicorn.run(app, host=s.bridge_host, port=s.bridge_port, log_level="info")
