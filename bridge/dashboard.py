from __future__ import annotations

import subprocess
import sys
import threading
from pathlib import Path

import tkinter as tk
from tkinter import messagebox, scrolledtext, ttk

import requests

from bridge.config import get_settings
from bridge.state import state

_PROJECT_ROOT = Path(__file__).resolve().parent.parent


def open_dashboard_threaded() -> None:
    def run() -> None:
        Dashboard().mainloop()

    threading.Thread(target=run, daemon=True).start()


class Dashboard(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Desktop Control Bridge")
        self.geometry("420x400")
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
        ttk.Button(
            tf,
            text="See (screenshot + local OCR)",
            command=self._see,
        ).pack(fill=tk.X, padx=4, pady=2)

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

    def _see(self) -> None:
        def work() -> None:
            try:
                r = requests.post(
                    f"{self._base}/screenshot/context",
                    headers=self._headers,
                    json={},
                    timeout=60,
                )
                r.raise_for_status()
                data = r.json()
                ws = data.get("workspace_path") or ""
                if not ws:
                    raise RuntimeError("No workspace_path in response")
                script = _PROJECT_ROOT / "scripts" / "vision_ocr.py"
                if not script.is_file():
                    raise RuntimeError(f"Missing {script}")
                proc = subprocess.run(
                    [
                        sys.executable,
                        str(script),
                        ws,
                        "--quiet-meta",
                    ],
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    cwd=str(_PROJECT_ROOT),
                    timeout=180,
                )
                ocr_out = (proc.stdout or "").strip()
                ocr_err = (proc.stderr or "").strip()
                self.after(
                    0,
                    lambda: self._show_see_window(data, ocr_out, proc.returncode, ocr_err),
                )
            except Exception as e:
                msg = str(e)
                self.after(0, lambda m=msg: messagebox.showerror("See", m))

        threading.Thread(target=work, daemon=True).start()

    def _show_see_window(
        self,
        snap: dict,
        ocr_text: str,
        ocr_code: int,
        ocr_stderr: str,
    ) -> None:
        win = tk.Toplevel(self)
        win.title("See — screenshot + OCR")
        win.geometry("620x520")
        win.transient(self)

        meta = tk.Frame(win, padx=8, pady=8)
        meta.pack(fill=tk.X)
        lines = [
            f"original_path:  {snap.get('original_path', '')}",
            f"workspace_path: {snap.get('workspace_path', '')}",
        ]
        if snap.get("captured_at"):
            lines.append(f"captured_at:    {snap['captured_at']}")
        aw = snap.get("active_window")
        if aw:
            lines.append(f"active_title:   {aw.get('title', '')}")
            lines.append(f"active_process: {aw.get('process_name', '')}")
        for line in lines:
            ttk.Label(meta, text=line).pack(anchor=tk.W)

        ttk.Label(win, text="OCR text (local RapidOCR):").pack(anchor=tk.W, padx=8)
        txt = scrolledtext.ScrolledText(win, height=18, wrap=tk.WORD, font=("Consolas", 10))
        txt.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)
        parts: list[str] = []
        if ocr_code != 0:
            parts.append(f"[OCR exit {ocr_code}]")
            if ocr_stderr:
                parts.append(ocr_stderr)
        parts.append(ocr_text if ocr_text else "(no text detected)")
        body = "\n\n".join(parts)
        txt.insert(tk.END, body)
        txt.configure(state=tk.DISABLED)

        header = "\n".join(lines)

        def _clipboard_set(s: str) -> None:
            win.clipboard_clear()
            win.clipboard_append(s)
            win.update()

        def copy_all() -> None:
            _clipboard_set(f"{header}\n\n--- OCR ---\n{body}")

        def copy_ocr_only() -> None:
            if ocr_text:
                s = ocr_text
            elif ocr_code != 0 and ocr_stderr:
                s = ocr_stderr
            else:
                s = "(no text detected)"
            _clipboard_set(s)

        bf = ttk.Frame(win, padding=8)
        bf.pack(fill=tk.X)
        ttk.Button(bf, text="Copy all", command=copy_all).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(bf, text="Copy OCR text", command=copy_ocr_only).pack(side=tk.LEFT, padx=(0, 4))
        ttk.Button(bf, text="Close", command=win.destroy).pack(side=tk.RIGHT)
