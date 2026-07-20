#!/usr/bin/env python3
"""Rasterize an SVG diagram to PNG for external blog platforms.

Why this exists: in-repo diagrams live as SVG, but Dev.to (and most CMSs) do not
render SVG inline — it shows as a broken/crashed image. This converts an SVG to a
PNG sized for the platform's image proxy.

Size ceiling learned the hard way: Dev.to proxies external images through Cloudinary,
which SILENTLY FAILS to fetch images past a certain size. A ~2400px-wide PNG comes
back blank (alt text shows); ~1000-1400px renders fine. So the default target width
here is 1200px, NOT "as big as possible."

Method: wrap the SVG (as a data: URI) in a minimal HTML page sized to the diagram,
render with headless Chrome at 2x device scale, screenshot to PNG. No pip deps.

Usage:
    python3 rasterize-svg.py IN.svg OUT.png [--width 1200] [--scale 2]

Chrome is auto-located (macOS/Linux common paths) or set CHROME_BIN.

VERIFY AFTER RENDERING (do not skip): open the PNG and actually look at it. Confirm
no clipped text, no overlaps, the whole diagram is in frame — and, critically, that
no STALE or now-incorrect label survives in the raster from an out-of-date source SVG.
Source that looks fine routinely rasterizes with surprises.
"""

import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CHROME_CANDIDATES = [
    os.environ.get("CHROME_BIN", ""),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "google-chrome",
    "chromium",
    "chromium-browser",
]


def die(msg, code=1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def find_chrome():
    for c in CHROME_CANDIDATES:
        if not c:
            continue
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c
        found = shutil.which(c)
        if found:
            return found
    die(
        "headless Chrome/Chromium not found. Install Chrome or set CHROME_BIN.\n"
        "  (Fallbacks worth trying by hand: rsvg-convert, `qlmanage -t`, inkscape.)"
    )


def svg_dimensions(svg_text):
    """Best-effort width/height from the root <svg> (viewBox or width/height)."""
    m = re.search(r"<svg\b[^>]*>", svg_text, re.I)
    head = m.group(0) if m else ""
    vb = re.search(r'viewBox\s*=\s*"([\d.\s-]+)"', head)
    if vb:
        parts = vb.group(1).split()
        if len(parts) == 4:
            return float(parts[2]), float(parts[3])
    w = re.search(r'\bwidth\s*=\s*"([\d.]+)', head)
    h = re.search(r'\bheight\s*=\s*"([\d.]+)', head)
    if w and h:
        return float(w.group(1)), float(h.group(1))
    return 1200.0, 630.0  # sane default aspect if the SVG is unhelpful


def main(argv):
    args, width, scale = [], 1200, 2
    it = iter(argv[1:])
    for a in it:
        if a == "--width":
            width = int(next(it))
        elif a == "--scale":
            scale = int(next(it))
        else:
            args.append(a)
    if len(args) != 2:
        die("usage: rasterize-svg.py IN.svg OUT.png [--width 1200] [--scale 2]", 2)

    src, out = Path(args[0]).resolve(), Path(args[1]).resolve()
    if not src.is_file():
        die(f"input not found: {src}", 2)
    if width > 1600:
        print(
            f"warning: width {width}px is above ~1400px; external image proxies "
            "(e.g. Dev.to/Cloudinary) may silently fail to render it.",
            file=sys.stderr,
        )

    svg_text = src.read_text(encoding="utf-8")
    vw, vh = svg_dimensions(svg_text)
    height = max(1, round(width * (vh / vw)))
    b64 = base64.b64encode(svg_text.encode("utf-8")).decode("ascii")

    html = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<style>html,body{margin:0;padding:0;background:#fff}"
        f"img{{display:block;width:{width}px;height:{height}px}}</style></head>"
        f"<body><img src='data:image/svg+xml;base64,{b64}'></body></html>"
    )

    chrome = find_chrome()
    with tempfile.TemporaryDirectory() as td:
        page = Path(td) / "page.html"
        page.write_text(html, encoding="utf-8")
        cmd = [
            chrome, "--headless", "--disable-gpu", "--no-sandbox",
            "--hide-scrollbars", f"--force-device-scale-factor={scale}",
            f"--window-size={width},{height}",
            "--default-background-color=FFFFFFFF",
            f"--screenshot={out}", f"file://{page}",
        ]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if not out.is_file():
        die("Chrome ran but produced no PNG (check the SVG and CHROME_BIN)")
    print(f"{out}  ({width}x{height} @ {scale}x)")
    print(
        "VERIFY: open the PNG and look at it — check for clipping, overlaps, and any "
        "stale/incorrect label carried in from the source SVG.",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main(sys.argv)
