from __future__ import annotations

import pyautogui

# Disable failsafe that triggers when mouse hits screen corner during API-driven moves.
pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0.02


def position() -> tuple[int, int]:
    p = pyautogui.position()
    return int(p.x), int(p.y)


def move_to(x: int, y: int, duration: float = 0.0) -> None:
    duration = max(0.0, float(duration))
    pyautogui.moveTo(int(x), int(y), duration=duration)


def move_relative(dx: int, dy: int, duration: float = 0.0) -> None:
    duration = max(0.0, float(duration))
    pyautogui.moveRel(int(dx), int(dy), duration=duration)


def click(
    *,
    button: str = "left",
    x: int | None = None,
    y: int | None = None,
    clicks: int = 1,
) -> None:
    btn = button.lower()
    if btn not in ("left", "right", "middle"):
        raise ValueError("button must be left, right, or middle")
    if x is not None and y is not None:
        pyautogui.moveTo(int(x), int(y), duration=0)
    if clicks == 2:
        pyautogui.doubleClick(button=btn)
    elif clicks == 1:
        pyautogui.click(button=btn)
    else:
        for _ in range(int(clicks)):
            pyautogui.click(button=btn)


def drag(
    x1: int,
    y1: int,
    x2: int,
    y2: int,
    duration: float = 0.25,
    button: str = "left",
) -> None:
    btn = button.lower()
    if btn not in ("left", "right", "middle"):
        raise ValueError("button must be left, right, or middle")
    pyautogui.moveTo(int(x1), int(y1), duration=0)
    pyautogui.drag(
        int(x2) - int(x1),
        int(y2) - int(y1),
        duration=max(0.05, float(duration)),
        button=btn,
    )


def scroll(amount: int, *, horizontal: bool = False) -> None:
    if horizontal:
        pyautogui.hscroll(int(amount))
    else:
        pyautogui.scroll(int(amount))
