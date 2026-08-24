#!/usr/bin/env python3
"""Self-test for rasterize-svg.py's deterministic logic (§NAV-24).

Exercises svg_dimensions — the pure SVG-dimension-parsing function — without
touching Chrome (find_chrome/subprocess.run are never called here). stdlib
only, no network.

Run: python3 test_rasterize_svg.py
"""

import importlib.util
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).parent / "rasterize-svg.py"
_spec = importlib.util.spec_from_file_location("rasterize_svg", _SCRIPT)
rasterize_svg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rasterize_svg)


class SvgDimensionsTest(unittest.TestCase):
    def test_viewbox_wins_over_width_height(self):
        svg = '<svg viewBox="0 0 800 450" width="1000" height="500"></svg>'
        w, h = rasterize_svg.svg_dimensions(svg)
        self.assertEqual((w, h), (800.0, 450.0))

    def test_falls_back_to_width_height_when_no_viewbox(self):
        svg = '<svg width="640" height="360"></svg>'
        w, h = rasterize_svg.svg_dimensions(svg)
        self.assertEqual((w, h), (640.0, 360.0))

    def test_falls_back_to_default_aspect_when_neither_present(self):
        svg = "<svg></svg>"
        w, h = rasterize_svg.svg_dimensions(svg)
        self.assertEqual((w, h), (1200.0, 630.0))

    def test_malformed_viewbox_falls_through_to_width_height(self):
        # Only 3 numbers instead of 4 — svg_dimensions must not crash, and must
        # fall back rather than returning a garbage tuple.
        svg = '<svg viewBox="0 0 800" width="500" height="300"></svg>'
        w, h = rasterize_svg.svg_dimensions(svg)
        self.assertEqual((w, h), (500.0, 300.0))

    def test_negative_viewbox_origin_is_handled(self):
        svg = '<svg viewBox="-10 -10 800 450"></svg>'
        w, h = rasterize_svg.svg_dimensions(svg)
        self.assertEqual((w, h), (800.0, 450.0))

    def test_no_svg_tag_at_all_falls_back_to_default(self):
        w, h = rasterize_svg.svg_dimensions("not even xml")
        self.assertEqual((w, h), (1200.0, 630.0))


if __name__ == "__main__":
    unittest.main()
