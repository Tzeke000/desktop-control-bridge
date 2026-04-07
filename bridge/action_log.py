from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path

from bridge.config import get_settings

_logger: logging.Logger | None = None


def _ensure_log_dir() -> Path:
    s = get_settings()
    d = s.log_dir
    if not d.is_absolute():
        d = s.base_dir / d
    d.mkdir(parents=True, exist_ok=True)
    return d


def _file_handler() -> logging.Handler:
    global _logger
    log_dir = _ensure_log_dir()
    path = log_dir / "bridge-actions.log"
    fh = logging.FileHandler(path, encoding="utf-8")
    fh.setLevel(logging.INFO)
    fh.setFormatter(
        logging.Formatter(
            fmt="%(asctime)s | %(levelname)s | %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )
    return fh


def get_action_logger() -> logging.Logger:
    global _logger
    if _logger is not None:
        return _logger
    logger = logging.getLogger("bridge.actions")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    logger.addHandler(_file_handler())
    logger.propagate = False
    _logger = logger
    return logger


def log_action(
    endpoint: str,
    details: str,
    ok: bool,
    *,
    auth_ok: bool | None = None,
) -> None:
    """Human-readable action log line. Avoid putting secrets or full typed text in details."""
    log = get_action_logger()
    auth_bit = "" if auth_ok is None else f" auth_ok={auth_ok}"
    outcome = "OK" if ok else "FAIL"
    log.info("%s | %s%s | %s", endpoint, details, auth_bit, outcome)


def log_auth_rejection(reason: str, client: str | None = None) -> None:
    log = get_action_logger()
    extra = f" client={client}" if client else ""
    log.warning("AUTH_REJECTED | %s%s", reason, extra)


def iso_now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
