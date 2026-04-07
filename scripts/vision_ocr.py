"""
Local OCR for bridge screenshots (RapidOCR + ONNX). No cloud APIs.

Regions: --crop X,Y,W,H, --region NAME, or --active-window (Windows).
"""

from __future__ import annotations

import argparse
import statistics
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

NAMED_REGIONS = frozenset({"top", "bottom", "left", "right", "center", "full"})


def _load_dotenv() -> None:
    try:
        from dotenv import load_dotenv

        load_dotenv(PROJECT_ROOT / ".env")
    except ImportError:
        pass


def vision_workspace_default() -> Path:
    _load_dotenv()
    import os

    raw = (os.environ.get("BRIDGE_VISION_WORKSPACE") or "").strip()
    if raw:
        p = Path(raw)
        if not p.is_absolute():
            p = PROJECT_ROOT / p
        return p
    return Path.home() / ".openclaw" / "workspace" / "bridge-vision"


def latest_workspace_png(workspace: Path) -> Path:
    if not workspace.is_dir():
        raise FileNotFoundError(f"Vision workspace not found: {workspace}")
    pngs = sorted(workspace.glob("*.png"), key=lambda p: p.stat().st_mtime_ns, reverse=True)
    if not pngs:
        raise FileNotFoundError(f"No .png files in {workspace}")
    return pngs[0]


def rect_named_region(name: str, w: int, h: int) -> tuple[int, int, int, int]:
    """Return (x, y, width, height) in image pixels for a named band."""
    n = name.lower().strip()
    if n == "full":
        return 0, 0, w, h
    if n == "top":
        bh = max(1, h // 3)
        return 0, 0, w, bh
    if n == "bottom":
        bh = max(1, h // 3)
        return 0, h - bh, w, bh
    if n == "left":
        bw = max(1, w // 3)
        return 0, 0, bw, h
    if n == "right":
        bw = max(1, w // 3)
        return w - bw, 0, bw, h
    if n == "center":
        cw = max(1, int(w * 0.5))
        ch = max(1, int(h * 0.5))
        x = (w - cw) // 2
        y = (h - ch) // 2
        return x, y, cw, ch
    raise ValueError(f"unknown region: {name}")


def crop_active_window_screen(image_path: Path) -> Path:
    """Crop full-screen capture to foreground window bounds (Windows)."""
    try:
        import win32gui
    except ImportError as e:
        raise RuntimeError("--active-window requires pywin32 on Windows") from e
    from PIL import Image

    hwnd = win32gui.GetForegroundWindow()
    if not hwnd:
        raise RuntimeError("no foreground window")
    L, T, R, B = win32gui.GetWindowRect(hwnd)
    with Image.open(image_path) as im:
        w_img, h_img = im.size
    x0 = max(0, min(L, w_img - 1))
    y0 = max(0, min(T, h_img - 1))
    x1 = max(x0 + 1, min(R, w_img))
    y1 = max(y0 + 1, min(B, h_img))
    return apply_crop(image_path, (x0, y0, x1 - x0, y1 - y0))


def preprocess_to_temp(image_path: Path, *, max_side: int, contrast: float) -> Path:
    from PIL import Image, ImageEnhance

    img = Image.open(image_path).convert("RGB").convert("L")
    img = ImageEnhance.Contrast(img).enhance(contrast)
    w, h = img.size
    m = max(w, h)
    if m > max_side and m > 0:
        s = max_side / m
        img = img.resize((int(w * s), int(h * s)), Image.Resampling.LANCZOS)
    fd, name = tempfile.mkstemp(suffix=".png")
    import os

    os.close(fd)
    out = Path(name)
    img.save(out, format="PNG")
    return out


def apply_crop(image_path: Path, crop: tuple[int, int, int, int]) -> Path:
    from PIL import Image

    x, y, w, h = crop
    if w < 1 or h < 1:
        raise ValueError("crop width/height must be positive")
    im = Image.open(image_path).crop((x, y, x + w, y + h))
    fd, name = tempfile.mkstemp(suffix=".png")
    import os

    os.close(fd)
    out = Path(name)
    im.save(out, format="PNG")
    return out


def run_ocr_on_file(ocr_input: Path) -> tuple[list[tuple[str, float]], list[float]]:
    from rapidocr_onnxruntime import RapidOCR

    engine = RapidOCR()
    result, _elapse = engine(str(ocr_input))
    lines: list[tuple[str, float]] = []
    scores: list[float] = []
    if not result:
        return lines, scores
    for item in result:
        if len(item) < 3:
            continue
        text = str(item[1]).strip()
        if not text:
            continue
        try:
            score = float(item[2])
        except (TypeError, ValueError):
            score = 0.0
        lines.append((text, score))
        scores.append(score)
    return lines, scores


def main() -> int:
    p = argparse.ArgumentParser(description="Local OCR for screenshot images (RapidOCR).")
    p.add_argument(
        "image",
        nargs="?",
        default="",
        help="Path to PNG/JPG. If omitted, use newest workspace PNG.",
    )
    p.add_argument(
        "--latest-workspace",
        action="store_true",
        help="Use newest .png in the OpenClaw bridge-vision folder.",
    )
    p.add_argument(
        "--workspace-dir",
        default="",
        help="Override vision workspace directory.",
    )
    p.add_argument("--no-preprocess", action="store_true")
    p.add_argument("--max-side", type=int, default=1600)
    p.add_argument("--contrast", type=float, default=1.4)
    p.add_argument("--crop", default="", metavar="X,Y,W,H", help="Pixel crop before OCR.")
    p.add_argument(
        "--region",
        default="",
        metavar="NAME",
        help="Named band: top, bottom, left, right, center, full.",
    )
    p.add_argument(
        "--active-window",
        action="store_true",
        help="Crop to foreground window (full-screen capture; Windows).",
    )
    p.add_argument("--quiet-meta", action="store_true")
    args = p.parse_args()

    reg = (args.region or "").strip().lower()
    if reg and reg not in NAMED_REGIONS:
        print(f"[vision_ocr] FAIL: unknown --region (use {', '.join(sorted(NAMED_REGIONS))})", file=sys.stderr)
        return 1

    opts = sum(1 for x in (bool(args.crop.strip()), bool(reg), args.active_window) if x)
    if opts > 1:
        print("[vision_ocr] FAIL: use only one of --crop, --region, --active-window", file=sys.stderr)
        return 1

    tmp_paths: list[Path] = []
    try:
        if args.latest_workspace or not (args.image or "").strip():
            ws = Path(args.workspace_dir) if args.workspace_dir else vision_workspace_default()
            img_path = latest_workspace_png(ws)
        else:
            img_path = Path(args.image.strip()).expanduser().resolve()
            if not img_path.is_file():
                print(f"[vision_ocr] FAIL: file not found: {img_path}", file=sys.stderr)
                return 1

        work = img_path
        if args.active_window:
            aw = crop_active_window_screen(img_path)
            tmp_paths.append(aw)
            work = aw
        elif reg:
            from PIL import Image

            with Image.open(img_path) as im:
                iw, ih = im.size
            rect = rect_named_region(reg, iw, ih)
            cr = apply_crop(img_path, rect)
            tmp_paths.append(cr)
            work = cr
        elif args.crop.strip():
            parts = [int(x.strip()) for x in args.crop.split(",")]
            if len(parts) != 4:
                print("[vision_ocr] FAIL: --crop needs X,Y,W,H", file=sys.stderr)
                return 1
            cr = apply_crop(img_path, tuple(parts))  # type: ignore[arg-type]
            tmp_paths.append(cr)
            work = cr

        if not args.no_preprocess:
            pp = preprocess_to_temp(work, max_side=args.max_side, contrast=args.contrast)
            tmp_paths.append(pp)
            ocr_file = pp
        else:
            ocr_file = work

        processed_at = datetime.now(timezone.utc).isoformat()
        lines, scores = run_ocr_on_file(ocr_file)
        text_only = [t for t, _ in lines]

        if not args.quiet_meta:
            print("[vision_ocr] image:", str(img_path))
            print("[vision_ocr] ocr_input:", str(ocr_file))
            print("[vision_ocr] processed_at_utc:", processed_at)
            if args.active_window:
                print("[vision_ocr] crop: active_window")
            elif reg:
                print("[vision_ocr] crop: region=%s" % reg)
            elif args.crop.strip():
                print("[vision_ocr] crop: rect=%s" % args.crop.strip())
            if lines and scores:
                print("[vision_ocr] avg_confidence:", f"{statistics.mean(scores):.3f}")
                print("[vision_ocr] min_confidence:", f"{min(scores):.3f}")
            else:
                print("[vision_ocr] avg_confidence: (no lines)")
            print("[vision_ocr] ----- text -----")

        if text_only:
            print("\n".join(text_only))
        else:
            if not args.quiet_meta:
                print("(no text detected)")

        if not args.quiet_meta:
            print("[vision_ocr] ----- end -----")

        return 0
    except FileNotFoundError as e:
        print(f"[vision_ocr] FAIL: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"[vision_ocr] FAIL: {e}", file=sys.stderr)
        return 1
    finally:
        for t in tmp_paths:
            try:
                t.unlink(missing_ok=True)
            except OSError:
                pass


if __name__ == "__main__":
    sys.exit(main())
