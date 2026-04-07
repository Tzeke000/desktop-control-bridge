from __future__ import annotations

import threading
from dataclasses import dataclass, field
from datetime import datetime
from typing import Literal

StatusLiteral = Literal["running", "paused", "stopped"]


@dataclass
class BridgeState:
    _lock: threading.RLock = field(default_factory=threading.RLock, repr=False)
    _status: StatusLiteral = "running"
    _last_action_summary: str = ""
    _last_action_at: datetime | None = None

    @property
    def status(self) -> StatusLiteral:
        with self._lock:
            return self._status

    def set_status(self, status: StatusLiteral) -> None:
        with self._lock:
            self._status = status

    def is_control_allowed(self) -> bool:
        with self._lock:
            return self._status == "running"

    def record_action(self, summary: str) -> None:
        with self._lock:
            self._last_action_summary = summary
            self._last_action_at = datetime.now()

    @property
    def last_action_summary(self) -> str:
        with self._lock:
            return self._last_action_summary

    @property
    def last_action_at(self) -> datetime | None:
        with self._lock:
            return self._last_action_at


state = BridgeState()
