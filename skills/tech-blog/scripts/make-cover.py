#!/usr/bin/env python3
"""Compose a blog cover / social banner (1000x420) as a PNG.

Dev.to and social unfurls want a wide cover (~1000x420, ~2.4:1). This composes one
from a title + optional subtitle + optional kicker, with an optional repo logo (crisp
mark top-right + large faint watermark) and an optional diagram as a low-opacity
background motif. Headless Chrome renders it; no pip deps.

The layered technique (learned by building a real one): dark gradient canvas, text on
the left kept clear, brand/logo on the right, any diagram at very low opacity so it
reads as texture, not content. Keep the left column free of imagery so the title stays
legible.

Usage:
    python3 make-cover.py OUT.png \
        --title "Headline goes here" \
        [--subtitle "One line under it."] \
        [--kicker "SECTION LABEL"] \
        [--brand "example.com"] \
        [--logo path/to/logo.svg] \
        [--motif path/to/diagram.svg]

VERIFY AFTER RENDERING (do not skip): open the PNG and look at it. A layout/opacity
tweak can silently break the composition — text overlapping the brand line, or a faint
motif whose STALE/incorrect text is still readable. Confirm the title is clear, nothing
overlaps, and no out-of-date label shows through. (This exact class of bug bit the
first cover: a z-index change left a now-wrong label faintly legible.)
"""

import base64
import html as htmlmod
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CHROME_CANDIDATES = [
    os.environ.get("CHROME_BIN", ""),
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "google-chrome", "chromium", "chromium-browser",
]

W, H = 1000, 420


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
    die("headless Chrome/Chromium not found. Install Chrome or set CHROME_BIN.")


def data_uri(path):
    p = Path(path)
    if not p.is_file():
        die(f"asset not found: {path}", 2)
    b64 = base64.b64encode(p.read_bytes()).decode("ascii")
    ext = p.suffix.lower()
    mime = {
        ".svg": "image/svg+xml", ".png": "image/png",
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    }.get(ext, "application/octet-stream")
    return f"data:{mime};base64,{b64}"


def parse_args(argv):
    out, opts = None, {"title": "", "subtitle": "", "kicker": "",
                       "brand": "", "logo": "", "motif": ""}
    it = iter(argv[1:])
    for a in it:
        if a.startswith("--"):
            key = a[2:]
            if key not in opts:
                die(f"unknown option: {a}", 2)
            opts[key] = next(it, "")
        elif out is None:
            out = a
        else:
            die(f"unexpected argument: {a}", 2)
    if not out or not opts["title"]:
        die("usage: make-cover.py OUT.png --title '...' [--subtitle ..] "
            "[--kicker ..] [--brand ..] [--logo f.svg] [--motif d.svg]", 2)
    return out, opts


def build_html(o):
    esc = lambda s: htmlmod.escape(s)  # noqa: E731
    motif = (f'<img class="motif" src="{data_uri(o["motif"])}">'
             if o["motif"] else "")
    logo_bg = logo_mark = ""
    if o["logo"]:
        uri = data_uri(o["logo"])
        logo_bg = f'<img class="logo-bg" src="{uri}">'
        logo_mark = f'<img class="logo-mark" src="{uri}">'
    kicker = f'<div class="kicker">{esc(o["kicker"])}</div>' if o["kicker"] else ""
    subtitle = f'<div class="sub">{esc(o["subtitle"])}</div>' if o["subtitle"] else ""
    brand = f'<div class="brand">{esc(o["brand"])}</div>' if o["brand"] else ""
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{{margin:0;padding:0}}
  .card{{width:{W}px;height:{H}px;box-sizing:border-box;overflow:hidden;position:relative;
    background:linear-gradient(135deg,#0b1220 0%,#111a2e 55%,#0d1a38 100%);
    color:#e8eefc;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Inter,sans-serif;
    padding:44px 56px}}
  .motif{{position:absolute;right:-90px;bottom:-60px;width:430px;opacity:.05;filter:grayscale(1)}}
  .logo-bg{{position:absolute;right:-70px;top:50%;transform:translateY(-50%);width:340px;height:340px;opacity:.10}}
  .logo-mark{{position:absolute;top:40px;right:52px;width:66px;height:66px;filter:drop-shadow(0 4px 14px rgba(79,70,229,.5))}}
  .content{{position:relative;z-index:3;height:100%;display:flex;flex-direction:column;justify-content:center}}
  .kicker{{font-size:15px;letter-spacing:.14em;text-transform:uppercase;color:#8b9dff;font-weight:700;margin-bottom:16px}}
  h1{{font-size:41px;line-height:1.12;margin:0 0 16px;font-weight:800;max-width:620px;letter-spacing:-.5px}}
  .sub{{font-size:18px;color:#9fb0d0;max-width:580px;line-height:1.45}}
  .brand{{position:absolute;bottom:30px;left:56px;font-size:15px;color:#7183ab;font-weight:600;z-index:3}}
</style></head><body>
  <div class="card">
    {motif}{logo_bg}{logo_mark}
    <div class="content">{kicker}<h1>{esc(o["title"])}</h1>{subtitle}</div>
    {brand}
  </div>
</body></html>"""


def main(argv):
    out, opts = parse_args(argv)
    out = Path(out).resolve()
    chrome = find_chrome()
    with tempfile.TemporaryDirectory() as td:
        page = Path(td) / "cover.html"
        page.write_text(build_html(opts), encoding="utf-8")
        subprocess.run(
            [chrome, "--headless", "--disable-gpu", "--no-sandbox",
             "--hide-scrollbars", "--force-device-scale-factor=2",
             f"--window-size={W},{H}", f"--screenshot={out}", f"file://{page}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    if not out.is_file():
        die("Chrome ran but produced no PNG")
    print(f"{out}  ({W}x{H} @ 2x)")
    print(
        "VERIFY: open the PNG — title clear, nothing overlapping the brand line, and "
        "no stale/incorrect text readable in the faint motif.",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main(sys.argv)
