"""Smoke tests against a running server (start with: python -m bridge)."""

from __future__ import annotations

import os
import sys
import threading
import time

import requests

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT)
os.chdir(PROJECT)

from dotenv import load_dotenv

load_dotenv()


def main() -> None:
    from bridge.api import app
    from bridge.config import get_settings
    import uvicorn

    s = get_settings()
    t = threading.Thread(
        target=lambda: uvicorn.run(
            app, host=s.bridge_host, port=s.bridge_port, log_level="warning"
        ),
        daemon=True,
    )
    t.start()
    time.sleep(1.5)
    base = f"http://127.0.0.1:{s.bridge_port}"
    tok = s.bridge_token.strip()
    h = {"Authorization": f"Bearer {tok}"}

    r = requests.get(f"{base}/health", timeout=2)
    assert r.status_code == 200, r.text

    r = requests.post(f"{base}/mouse/move", json={"x": 0, "y": 0}, timeout=2)
    assert r.status_code == 401

    r = requests.post(
        f"{base}/mouse/move", headers=h, json={"x": 50, "y": 50}, timeout=5
    )
    assert r.status_code == 200, r.text

    r = requests.post(f"{base}/screenshot", headers=h, json={}, timeout=10)
    assert r.status_code == 200, r.text
    assert "path" in r.json()

    r = requests.post(
        f"{base}/pause",
        headers=h,
        timeout=5,
    )
    assert r.status_code == 200

    r = requests.post(f"{base}/mouse/move", headers=h, json={"x": 51, "y": 51}, timeout=5)
    assert r.status_code == 423

    r = requests.post(f"{base}/resume", headers=h, timeout=5)
    assert r.status_code == 200

    r = requests.post(f"{base}/stop", headers=h, timeout=5)
    assert r.status_code == 200

    r = requests.post(f"{base}/resume", headers=h, timeout=5)
    assert r.status_code == 503

    print("smoke_test: OK")


if __name__ == "__main__":
    main()
