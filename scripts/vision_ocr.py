"""
Local OCR for bridge screenshots (RapidOCR + ONNX). No cloud APIs.

Regions: --crop X,Y,W,H, --region NAME, or --active-window (Windows).
"""

from __future__ import annotations

import argparse
import re
import statistics
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

NAMED_REGIONS = frozenset({"top", "bottom", "left", "right", "center", "content", "full"})

_NOISE_LINE_RE = re.compile(r"^[\s\-_|=/\\.:·•]{2,}$")


def _ensure_utf8_stdio() -> None:
    if str(PROJECT_ROOT) not in sys.path:
        sys.path.insert(0, str(PROJECT_ROOT))
    try:
        from bridge.win_stdio_utf8 import apply as _apply_win_utf8

        _apply_win_utf8()
    except Exception:
        pass


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
    if n == "content":
        # Heuristic for dense browser/fullscreen UI: skip top tab/URL band, avoid bottom edge.
        y0 = int(h * 0.11)
        ch = max(1, int(h * 0.76))
        if y0 + ch > h:
            ch = h - y0
        return 0, y0, w, ch
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


def preprocess_to_temp(
    image_path: Path,
    *,
    max_side: int,
    contrast: float,
    min_long_side: int,
    sharpen: float,
    autocontrast: bool,
    unsharp_radius: float,
    unsharp_percent: int,
    unsharp_threshold: int,
) -> Path:
    from PIL import Image, ImageEnhance, ImageFilter, ImageOps

    img = Image.open(image_path).convert("RGB").convert("L")
    if autocontrast:
        img = ImageOps.autocontrast(img, cutoff=1)
    img = ImageEnhance.Contrast(img).enhance(contrast)
    w, h = img.size
    long_side = max(w, h)
    if min_long_side > 0 and long_side > 0 and long_side < min_long_side:
        scale = min_long_side / long_side
        nw = max(1, int(round(w * scale)))
        nh = max(1, int(round(h * scale)))
        ml = max(nw, nh)
        if ml > max_side > 0:
            s2 = max_side / ml
            nw = max(1, int(round(nw * s2)))
            nh = max(1, int(round(nh * s2)))
        img = img.resize((nw, nh), Image.Resampling.LANCZOS)
        w, h = nw, nh
    m = max(w, h)
    if m > max_side > 0 and m > 0:
        s = max_side / m
        img = img.resize((max(1, int(w * s)), max(1, int(h * s))), Image.Resampling.LANCZOS)
    if sharpen and sharpen != 1.0:
        img = ImageEnhance.Sharpness(img).enhance(sharpen)
    if unsharp_radius and unsharp_radius > 0 and unsharp_percent > 0:
        img = img.filter(
            ImageFilter.UnsharpMask(
                radius=float(unsharp_radius),
                percent=int(unsharp_percent),
                threshold=int(unsharp_threshold),
            )
        )
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


def _sort_ocr_results_reading_order(raw: list) -> list:
    """Top-to-bottom, left-to-right using box geometry (RapidOCR yields unordered boxes)."""

    def sort_key(item: list) -> tuple[float, float]:
        if not item or len(item) < 1:
            return (0.0, 0.0)
        box = item[0]
        try:
            ys = [float(p[1]) for p in box]
            xs = [float(p[0]) for p in box]
            return (min(ys), min(xs))
        except (TypeError, ValueError, IndexError):
            return (0.0, 0.0)

    return sorted(raw, key=sort_key)


def filter_noise_lines(lines: list[tuple[str, float]]) -> list[tuple[str, float]]:
    """Drop likely UI chrome junk (separator glyphs, tiny low-confidence fragments)."""
    out: list[tuple[str, float]] = []
    for t, s in lines:
        st = t.strip()
        if len(st) <= 1 and s < 0.45:
            continue
        if _NOISE_LINE_RE.match(st):
            continue
        if len(st) == 1 and not st.isalnum():
            continue
        out.append((t, s))
    return out


def compact_consecutive(lines: list[str]) -> list[str]:
    prev: str | None = None
    out: list[str] = []
    for t in lines:
        if t == prev:
            continue
        out.append(t)
        prev = t
    return out


def run_ocr_on_file(
    ocr_input: Path,
    *,
    det_limit_side_len: int,
    box_thresh: float,
    text_score: float,
) -> tuple[list[tuple[str, float]], list[float]]:
    from rapidocr_onnxruntime import RapidOCR

    ocr_kw: dict[str, object] = {}
    if det_limit_side_len > 0:
        # rapidocr-onnxruntime requires det_model_path when any det_* kwarg is set
        ocr_kw["det_model_path"] = ""
        ocr_kw["det_limit_side_len"] = det_limit_side_len
    engine = RapidOCR(**ocr_kw)
    result, _elapse = engine(str(ocr_input), box_thresh=box_thresh, text_score=text_score)
    lines: list[tuple[str, float]] = []
    scores: list[float] = []
    if not result:
        return lines, scores
    for item in _sort_ocr_results_reading_order(result):
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
    _ensure_utf8_stdio()
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
    p.add_argument(
        "--max-side",
        type=int,
        default=2048,
        help="Longest image side after preprocess (downscale if larger).",
    )
    p.add_argument("--contrast", type=float, default=1.4)
    p.add_argument(
        "--min-long-side",
        type=int,
        default=720,
        help="If missing/long edge is smaller, upscale first (0 to disable). Helps small crops/UI text.",
    )
    p.add_argument(
        "--sharpen",
        type=float,
        default=1.12,
        help="PIL sharpness factor after resize (1.0 = off).",
    )
    p.add_argument(
        "--autocontrast",
        action="store_true",
        help="Apply autocontrast before contrast boost (flat captures).",
    )
    p.add_argument(
        "--unsharp-radius",
        type=float,
        default=0.0,
        help="Pillow UnsharpMask radius (>0 enables). Try mild 1–2 for small UI text.",
    )
    p.add_argument("--unsharp-percent", type=int, default=120, help="Unsharp percent (default 120).")
    p.add_argument("--unsharp-threshold", type=int, default=2, help="Unsharp threshold (default 2).")
    p.add_argument(
        "--perception",
        action="store_true",
        help="Turn on a tuned bundle for desktop/browser screenshots (autocontrast, stronger upscale, mild unsharp, slightly stricter detector).",
    )
    p.add_argument(
        "--filter-noise",
        action="store_true",
        help="Drop very short low-confidence fragments and separator-like junk lines.",
    )
    p.add_argument(
        "--compact",
        action="store_true",
        help="Remove consecutive duplicate text lines in output.",
    )
    p.add_argument(
        "--det-limit-side-len",
        type=int,
        default=2048,
        help="RapidOCR detector limit_side_len (0 = engine default).",
    )
    p.add_argument(
        "--ocr-box-thresh",
        type=float,
        default=0.54,
        help="Detector box threshold.",
    )
    p.add_argument(
        "--ocr-text-score",
        type=float,
        default=0.28,
        help="Min recognition score to keep a line (lower = more permissive).",
    )
    p.add_argument("--crop", default="", metavar="X,Y,W,H", help="Pixel crop before OCR.")
    p.add_argument(
        "--region",
        default="",
        metavar="NAME",
        help="Named band: top, bottom, left, right, center, content (browser-ish main band), full.",
    )
    p.add_argument(
        "--active-window",
        action="store_true",
        help="Crop to foreground window (full-screen capture; Windows).",
    )
    p.add_argument("--quiet-meta", action="store_true")
    args = p.parse_args()

    if args.perception:
        # Upscale + stricter detector for dense browser/UI; avoid autocontrast/unsharp here
        # (optional: add --autocontrast and/or --unsharp-radius for flat captures).
        args.min_long_side = max(args.min_long_side, 800)
        args.sharpen = max(args.sharpen, 1.15)
        args.max_side = max(args.max_side, 2304)
        args.ocr_box_thresh = max(args.ocr_box_thresh, 0.55)
        args.ocr_text_score = max(args.ocr_text_score, 0.30)
        args.det_limit_side_len = max(args.det_limit_side_len, 2048)

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
            pp = preprocess_to_temp(
                work,
                max_side=args.max_side,
                contrast=args.contrast,
                min_long_side=args.min_long_side,
                sharpen=args.sharpen,
                autocontrast=args.autocontrast,
                unsharp_radius=args.unsharp_radius,
                unsharp_percent=args.unsharp_percent,
                unsharp_threshold=args.unsharp_threshold,
            )
            tmp_paths.append(pp)
            ocr_file = pp
        else:
            ocr_file = work

        processed_at = datetime.now(timezone.utc).isoformat()
        lines, _raw_scores = run_ocr_on_file(
            ocr_file,
            det_limit_side_len=max(0, args.det_limit_side_len),
            box_thresh=args.ocr_box_thresh,
            text_score=args.ocr_text_score,
        )
        if args.filter_noise:
            lines = filter_noise_lines(lines)
        scores = [s for _, s in lines]
        text_only = [t for t, _ in lines]
        if args.compact:
            text_only = compact_consecutive(text_only)

        if not args.quiet_meta:
            print("[vision_ocr] image:", str(img_path))
            print("[vision_ocr] ocr_input:", str(ocr_file))
            print("[vision_ocr] processed_at_utc:", processed_at)
            if args.perception:
                print("[vision_ocr] preset: perception")
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
