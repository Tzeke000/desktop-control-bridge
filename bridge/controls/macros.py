from __future__ import annotations

import json
from pathlib import Path

from bridge.config import get_settings


def load_macros() -> dict[str, list[str]]:
    s = get_settings()
    path = s.macros_path
    if not path:
        return {}
    p = path if path.is_absolute() else s.base_dir / path
    if not p.is_file():
        return {}
    with open(p, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        return {}
    out: dict[str, list[str]] = {}
    for k, v in data.items():
        if isinstance(k, str) and isinstance(v, list) and all(isinstance(x, str) for x in v):
            out[k] = [x.lower().strip() for x in v]
    return out
