# Desktop Control Bridge

A **Windows-first**, **localhost-only** HTTP API that lets a **trusted local AI assistant** (or any script) control the desktop like a human operator—move the mouse, type, send hotkeys, manage windows, open URLs, and take screenshots.

This is **not** a public remote desktop product and **not** a stealth tool. It is intended to run visibly on your machine with a **system tray UI**, **pause/stop controls**, and **auditable logs**.

## What it does

- Listens only on **`127.0.0.1`** (default port **`47821`**).
- Requires a **Bearer token** on every control endpoint.
- Rejects requests whose TCP client is not `127.0.0.1` (so typical `::1` or LAN clients are refused by design).
- Logs each action to a **human-readable file** under `logs/bridge-actions.log` (configurable).
- Ships with a **pystray** menu: pause/resume/stop, copy token, open logs, open interactive API docs, and a small **Tk dashboard** for quick tests.

## Safety model

- **Binding**: `127.0.0.1` only—no LAN/WAN exposure by default.
- **Authentication**: Shared secret via `BRIDGE_TOKEN`; send `Authorization: Bearer <token>`.
- **Visibility**: Tray icon color reflects **running / paused / stopped**; menu exposes status and project folder.
- **Control gates**: **`POST /pause`** and **`POST /stop`** disable automation; **`POST /resume`** clears pause (after stop, use tray **Start bridge**—API `resume` returns 503 while stopped).
- **No autorun**: Nothing installs itself into Startup or scheduled tasks unless **you** add that.
- **No stealth**: No hidden persistence, credential dumping, or keylogging—only explicit API actions you request.
- **Logging hygiene**: Typed text is logged as **length + mode**, not full content.
- **Rejected auth** attempts are logged locally with **`AUTH_REJECTED`**.

**You** are responsible for keeping the token secret and for any desktop actions the API performs.

## Requirements

- **Windows 10 or 11**
- **Python 3.10+** (3.12 or 3.14 tested; use a [python.org](https://www.python.org/downloads/) install if the Microsoft Store shim causes issues)

## Install (fresh clone)

```powershell
cd desktop-control-bridge
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

If `win32` COM errors appear, run the pywin32 post-install step (often not needed on recent pip builds):

```powershell
.\.venv\Scripts\python.exe .\.venv\Scripts\pywin32_postinstall.py -install
```

## Configure

```powershell
Copy-Item .env.example .env
notepad .env
```

Set at least:

- `BRIDGE_TOKEN` — long random string (example: `[guid]::NewGuid().ToString('N') * 2` in PowerShell, or a password manager).

Optional:

- `BRIDGE_PORT` — default `47821`
- `BRIDGE_LOG_DIR`, `BRIDGE_SCREENSHOT_DIR`
- `BRIDGE_MACROS_PATH` — JSON map of macro name → list of keys (see `macros.example.json`)

## Run

**Tray + API (recommended)**

```powershell
.\.venv\Scripts\Activate.ps1
python run.py
```

**Headless API only** (no tray—for dev/automation hosts)

```powershell
python -m bridge
```

Open interactive docs: `http://127.0.0.1:47821/docs` (use your port if changed).

## Authenticate

Every **control** route expects:

```http
Authorization: Bearer <your BRIDGE_TOKEN>
```

`GET /health` and `GET /status` are unauthenticated (localhost-only); everything that can move the machine requires the token.

## API overview

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness JSON |
| GET | `/status` | Bridge version, bind address, pause/stop state, last action summary |
| POST | `/pause` | Pause control (423 on actions until resume) |
| POST | `/resume` | Resume from paused (503 if fully stopped) |
| POST | `/stop` | Stop control until tray **Start bridge** |
| POST | `/mouse/move` | Body: `x`, `y`, optional `duration` (smooth move) |
| POST | `/mouse/click` | `button` left/right/middle, optional `x`,`y`, `clicks` 1–3 |
| POST | `/mouse/drag` | `x1,y1` → `x2,y2`, optional `duration`, `button` |
| POST | `/mouse/scroll` | `amount` (signed), `horizontal` |
| POST | `/keyboard/type` | `text`, optional `interval`; `mode`: `type` or `paste` (clipboard + Ctrl+V) |
| POST | `/keyboard/press` | Single `key` |
| POST | `/keyboard/hotkey` | `keys`: e.g. `["ctrl","c"]` — use `winleft` for Win key |
| POST | `/keyboard/macro` | Named macro from `BRIDGE_MACROS_PATH` JSON |
| POST | `/app/open` | Executable path or alias (`notepad`, `calc`, …) |
| GET | `/windows` | Visible windows with titles and process names |
| GET | `/window/active` | Foreground window |
| POST | `/window/focus` | `title` substring and/or `process_name` |
| POST | `/window/minimize` | Same matcher |
| POST | `/window/maximize` | Same matcher |
| POST | `/window/close` | Posts `WM_CLOSE` |
| POST | `/browser/open-url` | `url`, `browser`: `default` or `chrome` |
| POST | `/browser/new-tab` | Ctrl+T |
| POST | `/browser/focus-address-bar` | Ctrl+L |
| POST | `/browser/search` | Opens Google search for `query` (types URL + Enter) |
| POST | `/screenshot` | Saves PNG under the project screenshot dir **and** copies it to the OpenClaw vision workspace; JSON includes **`original_path`**, **`workspace_path`**, and **`path`** (same as `original_path`). |
| POST | `/screenshot/context` | Same as `/screenshot`, plus **`active_window`** (title, pid, process_name, hwnd) sampled before capture and **`captured_at`** (UTC ISO-8601). |

Full schemas: `/openapi.json` or `/docs`.

## Emil vision handoff (OpenClaw workspace)

Every authenticated **`POST /screenshot`** (and **`POST /screenshot/context`**) still writes the primary PNG under the project’s **`BRIDGE_SCREENSHOT_DIR`** (default: **`screenshots/`** next to the repo). The bridge **also** copies that file into **`BRIDGE_VISION_WORKSPACE`**, default:

`%USERPROFILE%\.openclaw\workspace\bridge-vision`

The folder is created if missing. Nothing is served over the LAN; paths are local disk only. Emil’s OpenClaw workspace can read **`workspace_path`** without relying on the bridge project tree.

**Capture from PowerShell**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\vision_capture.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\vision_capture.ps1 -Context
```

**Readiness check** (expects the bridge running unless you pass **`-SkipApi`**)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\vision_readiness.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\vision_readiness.ps1 -SkipApi
```

## Local OCR (offline text from screenshots)

Emil can read on-screen text **without remote image/OCR APIs** using **[RapidOCR](https://github.com/RapidAI/RapidOCR)** (ONNX models). Everything runs locally after install.

**Install**

```powershell
cd desktop-control-bridge
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

The first OCR run may **download** ONNX weights into your user cache (one-time). After that, **inference is fully local**—no remote API calls per image.

**Run on the latest workspace screenshot** (newest `*.png` under `%USERPROFILE%\.openclaw\workspace\bridge-vision`, or `BRIDGE_VISION_WORKSPACE` in `.env`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\vision_ocr.ps1
.\.venv\Scripts\python.exe scripts\vision_ocr.py
```

**Run on a specific file**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\vision_ocr.ps1 D:\path\to\capture.png
.\.venv\Scripts\python.exe scripts\vision_ocr.py D:\path\to\capture.png
```

**Useful flags** (Python script; see `scripts/vision_ocr.py --help`):

- `--no-preprocess` — skip grayscale / contrast / resize (try if layout is already high-contrast).
- `--crop X,Y,W,H` — crop before OCR (for future region workflows).
- `--quiet-meta` — print **only** recognized text lines (no header).

Output includes **image path**, **UTC timestamp**, and **avg/min confidence** when lines are found.

**Limitations**

- Accuracy depends on font size, anti-aliasing, scaling, and language; UI chrome and games are often harder than plain documents.
- Model is geared toward typical text; rare fonts and heavy stylization degrade results.
- Large images are downscaled in preprocessing for speed (see `--max-side`).
- This path **does not** replace a full multimodal model for scene understanding—it extracts **text**.

## PowerShell helper scripts (Windows PowerShell 5.1+)

These scripts load **`BRIDGE_HOST`**, **`BRIDGE_PORT`**, and **`BRIDGE_TOKEN`** from **`.env`** in the project root (or an alternate file). They build the **Bearer** header internally and **never print the raw token**.

| Script | Purpose |
|--------|---------|
| `bridge_ps_common.ps1` | Shared library (dot-sourced by the others; do not run directly). |
| `verify.ps1` | Quick checks: `.env` exists, port valid, `GET /health`, optional `GET /status` with auth. |
| `smoke_actions.ps1` | Interactive smoke sequences (`mouse-test`, `notepad-test`, …, or `all`). |
| `invoke_bridge.ps1` | Single-action CLI wrapper for common API calls. |
| `vision_capture.ps1` | Calls **`/screenshot`** (or **`/screenshot/context`** with **`-Context`**) and prints both path fields. |
| `vision_readiness.ps1` | Ensures the vision folder exists; optionally calls **`/screenshot`** and checks the newest PNG in the workspace. |
| `vision_ocr.ps1` | Runs **local** RapidOCR on the newest workspace PNG or a given image path (no token printed). |

**Verify the bridge is up**

```powershell
cd desktop-control-bridge
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1 -SkipStatus
```

**Smoke scenarios**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\smoke_actions.ps1 all
powershell -NoProfile -ExecutionPolicy Bypass -File .\smoke_actions.ps1 screenshot-test
```

**`invoke_bridge.ps1` examples** (reads `.env`; use `-EnvFile path` for a different env file path)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 health
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 status

powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 screenshot
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 screenshot-context
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 open-url https://example.com
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 app-open notepad

powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 type 'Hello from the bridge'
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 hotkey ctrl,c
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 move 200 200
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 click left

powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 mouse-test
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 notepad-test
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 browser-test
powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 screenshot-test

powershell -NoProfile -ExecutionPolicy Bypass -File .\invoke_bridge.ps1 -EnvFile D:\config\bridge.env status
```

`BRIDGE_HOST` must be **`127.0.0.1`** (or unset) for these scripts. Exit code **0** means success, **1** failure.

## Example PowerShell

```powershell
$base = "http://127.0.0.1:47821"
$h = @{ Authorization = "Bearer YOUR_TOKEN_HERE" }

Invoke-RestMethod "$base/health"
Invoke-RestMethod "$base/status"

$body = @{ x = 100; y = 200; duration = 0.3 } | ConvertTo-Json
Invoke-RestMethod "$base/mouse/move" -Method Post -Headers $h -Body $body -ContentType "application/json"

$body = @{ keys = @("ctrl","c") } | ConvertTo-Json
Invoke-RestMethod "$base/keyboard/hotkey" -Method Post -Headers $h -Body $body -ContentType "application/json"
```

## Example curl

```bash
curl -s http://127.0.0.1:47821/health

curl -s -X POST http://127.0.0.1:47821/mouse/move \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d "{\"x\":300,\"y\":300,\"duration\":0.5}"
```

## Action log file

- Default directory: `logs/` (or `BRIDGE_LOG_DIR`).
- File: `bridge-actions.log`
- Each line includes timestamp, level, endpoint summary, parameters **without secrets**, and **`OK` / `FAIL`**.
- **`AUTH_REJECTED`** entries are **`WARNING`** level.

## Troubleshooting

| Issue | Mitigation |
|-------|------------|
| `BRIDGE_TOKEN is empty` on start | Create `.env` from `.env.example` and set the token. |
| `403 Only 127.0.0.1` | Client must connect to IPv4 loopback, not `localhost` resolving to `::1`, and not from another machine. From WSL2, Windows `127.0.0.1` is not the same as WSL `127.0.0.1`—call the Windows host IP instead only if you **intentionally** change binding (not supported out of the box). |
| `ImportError: win32xxx` | Reinstall `pywin32`, run `pywin32_postinstall.py`. |
| `pip` builds Pillow from source | Use **Python 3.12+** with a recent pip so a **wheel** is used, or install a prebuilt Pillow for your Python version. |
| UI automation flaky in games | Normal; this stack targets desktop apps, not anti-cheat games. |
| Token leak in shell history | Prefer `.env` + app that reads it, or PowerShell secure strings, not inline secrets in shared scripts. |

## Development smoke test

With `.env` configured:

```powershell
.\.venv\Scripts\python.exe scripts\smoke_test.py
```

## Publishing to GitHub

This repository is meant to be **full source**. After `git init`:

```powershell
git add -A
git commit -m "Initial desktop control bridge"
git branch -M main
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```

(The assistant cannot push to your GitHub account from this environment.)

## License

Use and modify for your own machines at your own risk. No warranty.
