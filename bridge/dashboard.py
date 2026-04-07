from __future__ import annotations

import threading
import tkinter as tk
from tkinter import messagebox, ttk

import requests

from bridge.config import get_settings
from bridge.state import state


def open_dashboard_threaded() -> None:
    def run() -> None:
        Dashboard().mainloop()

    threading.Thread(target=run, daemon=True).start()


class Dashboard(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Desktop Control Bridge")
        self.geometry("420x360")
        s = get_settings()
        self._token = (s.bridge_token or "").strip()
        self._base = f"http://127.0.0.1:{s.bridge_port}"
        self._headers = {"Authorization": f"Bearer {self._token}"}

        frm = ttk.Frame(self, padding=8)
        frm.pack(fill=tk.BOTH, expand=True)

        self._status_var = tk.StringVar(value="…")
        ttk.Label(frm, textvariable=self._status_var, font=("Segoe UI", 11)).pack(
            anchor=tk.W
        )

        ttk.Label(frm, text=f"API: {self._base}").pack(anchor=tk.W)
        tok_show = (
            (self._token[:4] + "…" + self._token[-4:])
            if len(self._token) > 12
            else "(short token)"
        )
        ttk.Label(frm, text=f"Token: {tok_show}").pack(anchor=tk.W)

        bf = ttk.Frame(frm)
        bf.pack(fill=tk.X, pady=8)
        ttk.Button(bf, text="Refresh status", command=self._refresh).pack(
            side=tk.LEFT, padx=4
        )
        ttk.Button(bf, text="Health (no auth)", command=self._health).pack(
            side=tk.LEFT, padx=4
        )

        cf = ttk.LabelFrame(frm, text="Bridge control")
        cf.pack(fill=tk.X, pady=8)
        ttk.Button(cf, text="Pause", command=self._pause).pack(
            side=tk.LEFT, padx=4, pady=4
        )
        ttk.Button(cf, text="Resume", command=self._resume).pack(
            side=tk.LEFT, padx=4, pady=4
        )
        ttk.Button(cf, text="Stop (API)", command=self._stop).pack(
            side=tk.LEFT, padx=4, pady=4
        )

        tf = ttk.LabelFrame(frm, text="Quick tests (auth)")
        tf.pack(fill=tk.X, pady=8)
        ttk.Button(tf, text="Mouse move 10,10", command=self._test_move).pack(
            fill=tk.X, padx=4, pady=2
        )
        ttk.Button(tf, text="Types 'hi' in focused window", command=self._test_type).pack(
            fill=tk.X, padx=4, pady=2
        )

        self._refresh()

    def _refresh(self) -> None:
        try:
            r = requests.get(f"{self._base}/status", timeout=2)
            j = r.json()
            self._status_var.set(
                f"API status: {j.get('status')} | local UI sees: {state.status}"
            )
        except Exception as e:
            self._status_var.set(f"status error: {e}")

    def _health(self) -> None:
        try:
            r = requests.get(f"{self._base}/health", timeout=2)
            messagebox.showinfo("Health", r.text)
        except Exception as e:
            messagebox.showerror("Health", str(e))

    def _pause(self) -> None:
        try:
            r = requests.post(f"{self._base}/pause", headers=self._headers, timeout=5)
            messagebox.showinfo("Pause", r.text)
        except Exception as e:
            messagebox.showerror("Pause", str(e))
        self._refresh()

    def _resume(self) -> None:
        try:
            r = requests.post(f"{self._base}/resume", headers=self._headers, timeout=5)
            messagebox.showinfo("Resume", r.text)
        except Exception as e:
            messagebox.showerror("Resume", str(e))
        self._refresh()

    def _stop(self) -> None:
        try:
            r = requests.post(f"{self._base}/stop", headers=self._headers, timeout=5)
            messagebox.showinfo("Stop", r.text)
        except Exception as e:
            messagebox.showerror("Stop", str(e))
        self._refresh()

    def _test_move(self) -> None:
        try:
            r = requests.post(
                f"{self._base}/mouse/move",
                headers=self._headers,
                json={"x": 10, "y": 10, "duration": 0},
                timeout=5,
            )
            messagebox.showinfo("mouse/move", r.text)
        except Exception as e:
            messagebox.showerror("mouse/move", str(e))

    def _test_type(self) -> None:
        try:
            r = requests.post(
                f"{self._base}/keyboard/type",
                headers=self._headers,
                json={"text": "hi", "mode": "type"},
                timeout=5,
            )
            messagebox.showinfo("keyboard/type", r.text)
        except Exception as e:
            messagebox.showerror("keyboard/type", str(e))
