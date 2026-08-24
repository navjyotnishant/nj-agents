#!/usr/bin/env python3
"""Self-test for publish-devto.py's deterministic logic (§NAV-24).

Exercises is_local, force_published, and rewrite_images' non-network paths —
the pure/local functions — without any network call (upload_image, which is
the only function that hits Dev.to's API, is never invoked here: the fixtures
below use only remote image refs or a pre-populated cache, so
resolve_local_image's upload branch never fires). stdlib only, tempdir
fixtures, no network, no API key required.

Run: python3 test_publish_devto.py
"""

import importlib.util
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).parent / "publish-devto.py"
_spec = importlib.util.spec_from_file_location("publish_devto", _SCRIPT)
publish_devto = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(publish_devto)


class IsLocalTest(unittest.TestCase):
    def test_relative_path_is_local(self):
        self.assertTrue(publish_devto.is_local("./images/x.png"))

    def test_bare_relative_path_is_local(self):
        self.assertTrue(publish_devto.is_local("images/x.png"))

    def test_https_url_is_not_local(self):
        self.assertFalse(publish_devto.is_local("https://example.com/x.png"))

    def test_http_url_is_not_local(self):
        self.assertFalse(publish_devto.is_local("http://example.com/x.png"))

    def test_protocol_relative_url_is_not_local(self):
        self.assertFalse(publish_devto.is_local("//example.com/x.png"))

    def test_data_uri_is_not_local(self):
        self.assertFalse(publish_devto.is_local("data:image/png;base64,abc"))


class ForcePublishedTest(unittest.TestCase):
    def test_inserts_published_line_when_absent(self):
        text = "---\ntitle: T\n---\nbody"
        out = publish_devto.force_published(text, False)
        self.assertIn("published: false\n", out)
        self.assertTrue(out.startswith("---\npublished: false\n"))

    def test_replaces_existing_published_line(self):
        text = "---\ntitle: T\npublished: true\n---\nbody"
        out = publish_devto.force_published(text, False)
        self.assertIn("published: false", out)
        self.assertNotIn("published: true", out)

    def test_publish_true_when_requested(self):
        text = "---\ntitle: T\n---\nbody"
        out = publish_devto.force_published(text, True)
        self.assertIn("published: true", out)

    def test_no_front_matter_leaves_text_unchanged(self):
        text = "just a body, no front matter"
        out = publish_devto.force_published(text, True)
        self.assertEqual(out, text)

    def test_unterminated_front_matter_leaves_text_unchanged(self):
        text = "---\ntitle: T\nbody with no closing fence"
        out = publish_devto.force_published(text, True)
        self.assertEqual(out, text)

    def test_only_touches_front_matter_block(self):
        # A line that looks like "published:" in the BODY must not be touched.
        text = "---\ntitle: T\n---\nSee published: false in prod docs."
        out = publish_devto.force_published(text, True)
        self.assertIn("See published: false in prod docs.", out)


class RewriteImagesTest(unittest.TestCase):
    def test_remote_inline_image_untouched(self):
        text = "![alt](https://example.com/x.png)"
        out = publish_devto.rewrite_images(text, Path("."), "fake-key", {})
        self.assertEqual(out, text)

    def test_local_inline_image_uses_cache_without_network(self):
        # Pre-populate the cache so resolve_local_image's cache-hit branch
        # returns immediately — upload_image (the network call) is never reached.
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            img = base / "images" / "x.png"
            img.parent.mkdir()
            img.write_bytes(b"\x89PNG\r\n")
            content_hash = publish_devto.file_hash(img)
            cache_key = f"{img.resolve()}::{content_hash}"
            cache = {cache_key: "https://media.dev.to/cached-x.png"}

            text = "![alt](images/x.png)"
            out = publish_devto.rewrite_images(text, base, "fake-key", cache)
            self.assertIn("https://media.dev.to/cached-x.png", out)
            self.assertNotIn("images/x.png", out)

    def test_remote_cover_image_untouched(self):
        text = "---\ncover_image: https://example.com/c.png\n---\nbody"
        out = publish_devto.rewrite_images(text, Path("."), "fake-key", {})
        self.assertEqual(out, text)

    def test_local_cover_image_uses_cache_without_network(self):
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            cover = base / "cover.png"
            cover.write_bytes(b"\x89PNG\r\n")
            content_hash = publish_devto.file_hash(cover)
            cache_key = f"{cover.resolve()}::{content_hash}"
            cache = {cache_key: "https://media.dev.to/cached-cover.png"}

            text = "---\ncover_image: cover.png\n---\nbody"
            out = publish_devto.rewrite_images(text, base, "fake-key", cache)
            self.assertIn("https://media.dev.to/cached-cover.png", out)


if __name__ == "__main__":
    unittest.main()
