from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Annotated, Any, Callable

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from pydantic import BaseModel, Field

from bridge import __version__
from bridge.action_log import log_action
from bridge.auth import require_token
from bridge.config import get_settings
from bridge.controls import browser_control, keyboard_control, mouse_control
from bridge.controls import screenshot_control, window_control
from bridge.state import state

Auth = Annotated[None, Depends(require_token)]


def _run_control(endpoint: str, details: str, fn: Callable[[], None]) -> dict[str, Any]:
    if state.status == "stopped":
        log_action(endpoint, details, ok=False)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Bridge is stopped. Start the service from the tray app.",
        )
    if not state.is_control_allowed():
        log_action(endpoint, details, ok=False)
        raise HTTPException(
            status_code=status.HTTP_423_LOCKED,
            detail=f"Bridge is {state.status}; control disabled until resumed",
        )
    try:
        fn()
        state.record_action(f"{endpoint}: {details}")
        log_action(endpoint, details, ok=True, auth_ok=True)
        return {"ok": True}
    except HTTPException:
        raise
    except Exception as e:
        log_action(endpoint, f"{details} err={e!s}", ok=False, auth_ok=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e),
        ) from e


@asynccontextmanager
async def lifespan(_: FastAPI):
    yield


app = FastAPI(
    title="Desktop Control Bridge",
    description="Localhost-only desktop control API (authenticated).",
    version=__version__,
    lifespan=lifespan,
)


@app.middleware("http")
async def localhost_only(request: Request, call_next):
    """Enforce loopback-only (IPv4 127.0.0.1)."""
    client = request.client
    host = client.host if client else ""
    if host != "127.0.0.1":
        from bridge.action_log import log_action as la

        la(
            "BLOCK_NON_LOCAL",
            f"path={request.url.path} host={host!r}",
            ok=False,
        )
        return Response(
            status_code=status.HTTP_403_FORBIDDEN,
            content=b"Only 127.0.0.1 is permitted",
            media_type="text/plain",
        )
    return await call_next(request)


# --- Public (no auth) ---


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "service": "desktop-control-bridge"}


@app.get("/status")
def public_status() -> dict[str, Any]:
    s = get_settings()
    return {
        "version": __version__,
        "bind": f"{s.bridge_host}:{s.bridge_port}",
        "status": state.status,
        "control_enabled": state.is_control_allowed(),
        "last_action": state.last_action_summary,
        "last_action_at": state.last_action_at.isoformat()
        if state.last_action_at
        else None,
    }


# --- Lifecycle (auth) ---


@app.post("/pause", dependencies=[Depends(require_token)])
def pause() -> dict[str, Any]:
    state.set_status("paused")
    log_action("/pause", "", ok=True, auth_ok=True)
    state.record_action("pause")
    return {"ok": True, "status": state.status}


@app.post("/resume", dependencies=[Depends(require_token)])
def resume() -> dict[str, Any]:
    if state.status == "stopped":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Bridge is stopped. Start from tray.",
        )
    state.set_status("running")
    log_action("/resume", "", ok=True, auth_ok=True)
    state.record_action("resume")
    return {"ok": True, "status": state.status}


@app.post("/stop", dependencies=[Depends(require_token)])
def stop_service() -> dict[str, Any]:
    state.set_status("stopped")
    log_action("/stop", "", ok=True, auth_ok=True)
    state.record_action("stop (API)")
    return {"ok": True, "status": state.status}


# --- Mouse ---


class MouseMoveBody(BaseModel):
    x: int
    y: int
    duration: float = Field(default=0.0, ge=0.0, description="Seconds; >0 for smooth move")


@app.post("/mouse/move")
def mouse_move(_: Auth, body: MouseMoveBody) -> dict[str, Any]:
    return _run_control(
        "/mouse/move",
        f"x={body.x} y={body.y} duration={body.duration}",
        lambda: mouse_control.move_to(body.x, body.y, body.duration),
    )


class MouseClickBody(BaseModel):
    button: str = "left"
    x: int | None = None
    y: int | None = None
    clicks: int = Field(default=1, ge=1, le=3)


@app.post("/mouse/click")
def mouse_click(_: Auth, body: MouseClickBody) -> dict[str, Any]:
    return _run_control(
        "/mouse/click",
        f"button={body.button} clicks={body.clicks} at={body.x},{body.y}",
        lambda: mouse_control.click(
            button=body.button, x=body.x, y=body.y, clicks=body.clicks
        ),
    )


class MouseDragBody(BaseModel):
    x1: int
    y1: int
    x2: int
    y2: int
    duration: float = Field(default=0.25, ge=0.05)
    button: str = "left"


@app.post("/mouse/drag")
def mouse_drag(_: Auth, body: MouseDragBody) -> dict[str, Any]:
    return _run_control(
        "/mouse/drag",
        f"({body.x1},{body.y1})->({body.x2},{body.y2})",
        lambda: mouse_control.drag(
            body.x1, body.y1, body.x2, body.y2, body.duration, button=body.button
        ),
    )


class MouseScrollBody(BaseModel):
    amount: int = Field(description="positive=up, negative=down (typical wheel steps)")
    horizontal: bool = False


@app.post("/mouse/scroll")
def mouse_scroll(_: Auth, body: MouseScrollBody) -> dict[str, Any]:
    return _run_control(
        "/mouse/scroll",
        f"amount={body.amount} horizontal={body.horizontal}",
        lambda: mouse_control.scroll(body.amount, horizontal=body.horizontal),
    )


# --- Keyboard ---


class KeyboardTypeBody(BaseModel):
    text: str
    interval: float = Field(default=0.0, ge=0.0)
    mode: str = Field(
        default="type",
        description="type | paste — paste uses clipboard+Ctrl+V",
    )


@app.post("/keyboard/type")
def keyboard_type(_: Auth, body: KeyboardTypeBody) -> dict[str, Any]:
    n = len(body.text)
    details = f"chars={n} mode={body.mode}"
    if body.mode == "paste":

        def do() -> None:
            keyboard_control.paste_safe(body.text)

        return _run_control("/keyboard/type", details, do)
    if body.mode != "type":
        raise HTTPException(status_code=400, detail="mode must be type or paste")

    def do2() -> None:
        keyboard_control.type_text(body.text, body.interval)

    return _run_control("/keyboard/type", details, do2)


class KeyboardPressBody(BaseModel):
    key: str


@app.post("/keyboard/press")
def keyboard_press(_: Auth, body: KeyboardPressBody) -> dict[str, Any]:
    return _run_control(
        "/keyboard/press",
        f"key={body.key!r}",
        lambda: keyboard_control.press_key(body.key),
    )


class KeyboardHotkeyBody(BaseModel):
    keys: list[str]


@app.post("/keyboard/hotkey")
def keyboard_hotkey(_: Auth, body: KeyboardHotkeyBody) -> dict[str, Any]:
    keys_repr = "+".join(body.keys)
    return _run_control(
        "/keyboard/hotkey",
        f"keys={keys_repr}",
        lambda: keyboard_control.hotkey(body.keys),
    )


class KeyboardMacroBody(BaseModel):
    name: str


@app.post("/keyboard/macro")
def keyboard_macro(_: Auth, body: KeyboardMacroBody) -> dict[str, Any]:
    return _run_control(
        "/keyboard/macro",
        f"name={body.name!r}",
        lambda: keyboard_control.run_macro(body.name),
    )


# --- Apps / windows ---


class AppOpenBody(BaseModel):
    path_or_name: str


@app.post("/app/open")
def app_open(_: Auth, body: AppOpenBody) -> dict[str, Any]:
    return _run_control(
        "/app/open",
        f"path_or_name_len={len(body.path_or_name)}",
        lambda: window_control.open_application(body.path_or_name),
    )


@app.get("/windows", dependencies=[Depends(require_token)])
def windows_list() -> dict[str, Any]:
    if state.status == "stopped":
        raise HTTPException(503, "Bridge stopped")
    if state.status == "paused":
        raise HTTPException(423, "Bridge paused")
    ws = window_control.list_windows()
    log_action("/windows", f"count={len(ws)}", ok=True, auth_ok=True)
    return {
        "windows": [
            {
                "hwnd": w.hwnd,
                "title": w.title,
                "pid": w.pid,
                "process_name": w.process_name,
            }
            for w in ws
        ]
    }


class WindowTargetBody(BaseModel):
    title: str | None = None
    process_name: str | None = None


@app.post("/window/focus")
def window_focus(_: Auth, body: WindowTargetBody) -> dict[str, Any]:
    return _run_control(
        "/window/focus",
        f"title={(body.title or '')[:40]!r} proc={(body.process_name or '')!r}",
        lambda: window_control.focus_window(title=body.title, process_name=body.process_name),
    )


@app.post("/window/minimize")
def window_minimize(_: Auth, body: WindowTargetBody) -> dict[str, Any]:
    return _run_control(
        "/window/minimize",
        f"title={(body.title or '')[:40]!r}",
        lambda: window_control.minimize_window(
            title=body.title, process_name=body.process_name
        ),
    )


@app.post("/window/maximize")
def window_maximize(_: Auth, body: WindowTargetBody) -> dict[str, Any]:
    return _run_control(
        "/window/maximize",
        f"title={(body.title or '')[:40]!r}",
        lambda: window_control.maximize_window(
            title=body.title, process_name=body.process_name
        ),
    )


@app.post("/window/close")
def window_close(_: Auth, body: WindowTargetBody) -> dict[str, Any]:
    return _run_control(
        "/window/close",
        f"title={(body.title or '')[:40]!r}",
        lambda: window_control.close_window(title=body.title, process_name=body.process_name),
    )


@app.get("/window/active", dependencies=[Depends(require_token)])
def window_active() -> dict[str, Any]:
    if state.status == "stopped":
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="Bridge stopped"
        )
    w = window_control.get_foreground_window()
    log_action("/window/active", "ok", ok=True, auth_ok=True)
    if not w:
        return {"active": None}
    return {
        "active": {
            "hwnd": w.hwnd,
            "title": w.title,
            "pid": w.pid,
            "process_name": w.process_name,
        }
    }


# --- Browser ---


class BrowserOpenUrlBody(BaseModel):
    url: str
    browser: str = "default"


@app.post("/browser/open-url")
def browser_open_url(_: Auth, body: BrowserOpenUrlBody) -> dict[str, Any]:
    b = body.browser
    detail = f"browser={b} url_len={len(body.url)}"
    return _run_control(
        "/browser/open-url",
        detail,
        lambda: browser_control.open_url(body.url, browser=b),
    )


@app.post("/browser/new-tab")
def browser_new_tab(_: Auth) -> dict[str, Any]:
    return _run_control("/browser/new-tab", "", browser_control.new_browser_tab)


@app.post("/browser/focus-address-bar")
def browser_focus_bar(_: Auth) -> dict[str, Any]:
    return _run_control(
        "/browser/focus-address-bar",
        "",
        browser_control.focus_address_bar,
    )


class BrowserSearchBody(BaseModel):
    query: str


@app.post("/browser/search")
def browser_search(_: Auth, body: BrowserSearchBody) -> dict[str, Any]:
    q = body.query.strip()
    return _run_control(
        "/browser/search",
        f"query_len={len(q)}",
        lambda: browser_control.type_search_query(q),
    )


# --- Screenshot ---


class ScreenshotBody(BaseModel):
    filename: str | None = None


@app.post("/screenshot")
def screenshot(_: Auth, body: ScreenshotBody) -> dict[str, Any]:
    path_holder: dict[str, str] = {}

    def do() -> None:
        p = screenshot_control.capture_to_file(body.filename)
        path_holder["path"] = str(p.resolve())

    out = _run_control(
        "/screenshot",
        f"filename={body.filename!r}",
        do,
    )
    out["path"] = path_holder.get("path", "")
    return out
