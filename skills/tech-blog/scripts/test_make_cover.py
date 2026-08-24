#!/usr/bin/env python3
"""Self-test for make-cover.py's deterministic logic (§NAV-24).

Exercises parse_args, data_uri, and build_html — the pure functions — without
touching Chrome (find_chrome/subprocess.run are never called here). stdlib
only, tempdir fixtures, no network.

Run: python3 test_make_cover.py
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).parent / "make-cover.py"
_spec = importlib.util.spec_from_file_location("make_cover", _SCRIPT)
make_cover = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_cover)


class ParseArgsTest(unittest.TestCase):
    def test_minimal_valid_args(self):
        out, opts = make_cover.parse_args(["prog", "out.png", "--title", "Hello"])
        self.assertEqual(out, "out.png")
        self.assertEqual(opts["title"], "Hello")
        self.assertEqual(opts["subtitle"], "")

    def test_all_options(self):
        out, opts = make_cover.parse_args([
            "prog", "out.png",
            "--title", "T", "--subtitle", "S", "--kicker", "K",
            "--brand", "B", "--logo", "l.svg", "--motif", "m.svg",
        ])
        self.assertEqual(opts["subtitle"], "S")
        self.assertEqual(opts["motif"], "m.svg")

    def test_missing_title_exits_nonzero(self):
        with self.assertRaises(SystemExit) as ctx:
            make_cover.parse_args(["prog", "out.png"])
        self.assertEqual(ctx.exception.code, 2)

    def test_missing_out_exits_nonzero(self):
        with self.assertRaises(SystemExit) as ctx:
            make_cover.parse_args(["prog", "--title", "T"])
        self.assertEqual(ctx.exception.code, 2)

    def test_unknown_option_exits_nonzero(self):
        with self.assertRaises(SystemExit) as ctx:
            make_cover.parse_args(["prog", "out.png", "--title", "T", "--bogus", "x"])
        self.assertEqual(ctx.exception.code, 2)


class DataUriTest(unittest.TestCase):
    def test_missing_asset_exits_nonzero(self):
        with self.assertRaises(SystemExit) as ctx:
            make_cover.data_uri("/nonexistent/path/x.svg")
        self.assertEqual(ctx.exception.code, 2)

    def test_svg_mime_type(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "logo.svg"
            p.write_text("<svg></svg>")
            uri = make_cover.data_uri(str(p))
            self.assertTrue(uri.startswith("data:image/svg+xml;base64,"))

    def test_png_mime_type(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "logo.png"
            p.write_bytes(b"\x89PNG\r\n")
            uri = make_cover.data_uri(str(p))
            self.assertTrue(uri.startswith("data:image/png;base64,"))


class BuildHtmlTest(unittest.TestCase):
    def test_title_is_escaped(self):
        html = make_cover.build_html({
            "title": "<script>alert(1)</script>", "subtitle": "", "kicker": "",
            "brand": "", "logo": "", "motif": "",
        })
        self.assertNotIn("<script>alert(1)</script>", html)
        self.assertIn("&lt;script&gt;", html)

    def test_optional_fields_omitted_when_empty(self):
        html = make_cover.build_html({
            "title": "T", "subtitle": "", "kicker": "", "brand": "", "logo": "", "motif": "",
        })
        self.assertNotIn('class="kicker"', html)
        self.assertNotIn('class="brand"', html)
        self.assertNotIn('class="motif"', html)

    def test_kicker_and_brand_present_when_given(self):
        html = make_cover.build_html({
            "title": "T", "subtitle": "", "kicker": "K", "brand": "B", "logo": "", "motif": "",
        })
        self.assertIn('class="kicker">K<', html)
        self.assertIn('class="brand">B<', html)


if __name__ == "__main__":
    unittest.main()
