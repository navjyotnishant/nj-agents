#!/usr/bin/env python3
"""Publish a Markdown blog post to Dev.to (Forem) via the REST API.

Dependency-free (Python stdlib only). Designed as the direct-REST fallback the
`blog-poster` agent uses when no publishing MCP connector is present.

The post's YAML front matter (title, tags, description, canonical_url,
cover_image, ...) is parsed natively by Dev.to out of `body_markdown`, so the
whole file is sent as-is after two transforms:

  1. Local images (./images/*.png and a local cover_image:) are uploaded to
     Dev.to's media CDN and their references rewritten to the returned URLs.
  2. `published:` is forced to false (draft-first) unless --publish is passed.

Idempotent: the Dev.to article id and an image-path -> CDN-URL cache are stored
in ~/.claude/devto-state.json, keyed by the post's absolute path, so re-runs
UPDATE the same draft instead of creating duplicates.

Usage:
    python3 publish-devto.py <path-to-post.md> [--publish]

The API key is read from $DEVTO_API_KEY, or from ~/.claude/.env
(DEVTO_API_KEY=...) if not already exported. It is never logged or persisted.
"""

import hashlib
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API_BASE = "https://dev.to/api"
ARTICLES_URL = f"{API_BASE}/articles"
IMAGES_URL = f"{API_BASE}/images"
ACCEPT = "application/vnd.forem.api-v1+json"
# Dev.to's edge (Cloudflare/Heroku) rejects the default python-urllib
# User-Agent with a 403; any conventional UA is accepted.
USER_AGENT = "publish-devto/1.0 (+nj-agents)"

STATE_PATH = Path.home() / ".claude" / "devto-state.json"
ENV_PATH = Path.home() / ".claude" / ".env"

# Inline markdown images: ![alt](path "optional title")
IMG_RE = re.compile(r"!\[(?P<alt>[^\]]*)\]\((?P<path>[^)\s]+)(?P<rest>\s+[^)]*)?\)")


# --------------------------------------------------------------------------- #
# small helpers
# --------------------------------------------------------------------------- #
def die(msg, code=1):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def info(msg):
    print(msg, file=sys.stderr)


def load_api_key():
    key = os.environ.get("DEVTO_API_KEY", "").strip()
    if key:
        return key
    if ENV_PATH.is_file():
        for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, _, val = line.partition("=")
            if name.strip() == "DEVTO_API_KEY":
                return val.strip().strip('"').strip("'")
    die(
        "DEVTO_API_KEY not set.\n"
        "  Generate a key at https://dev.to/settings/extensions "
        '("DEV Community API Keys"),\n'
        f"  then add a line to {ENV_PATH}:\n"
        "      DEVTO_API_KEY=your_key_here"
    )


def load_state():
    if STATE_PATH.is_file():
        try:
            return json.loads(STATE_PATH.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            info(f"warning: could not parse {STATE_PATH}; starting fresh state")
    return {}


def save_state(state):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# --------------------------------------------------------------------------- #
# HTTP
# --------------------------------------------------------------------------- #
def api_request(url, api_key, method="GET", json_body=None):
    data = json.dumps(json_body).encode("utf-8") if json_body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("api-key", api_key)
    req.add_header("Accept", ACCEPT)
    req.add_header("User-Agent", USER_AGENT)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        die(f"{method} {url} -> HTTP {e.code}\n{body}")
    except urllib.error.URLError as e:
        die(f"{method} {url} failed: {e.reason}")


def upload_image(path, api_key):
    """Upload one image via multipart/form-data to Dev.to's image endpoint.

    This is the editor's endpoint (not documented v1). Returns the CDN URL.
    """
    path = Path(path)
    ctype = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
    boundary = f"----njagents{uuid.uuid4().hex}"
    pre = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="image[]"; filename="{path.name}"\r\n'
        f"Content-Type: {ctype}\r\n\r\n"
    ).encode("utf-8")
    post = f"\r\n--{boundary}--\r\n".encode("utf-8")
    body = pre + path.read_bytes() + post

    req = urllib.request.Request(IMAGES_URL, data=body, method="POST")
    req.add_header("api-key", api_key)
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    req.add_header("User-Agent", USER_AGENT)
    try:
        with urllib.request.urlopen(req) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        die(
            f"image upload failed for {path.name} -> HTTP {e.code}\n{body}\n"
            "  Fallback: host the images yourself (e.g. rewrite ./images/x.png to\n"
            "  https://raw.githubusercontent.com/<owner>/<repo>/<branch>/docs/blog/images/x.png)\n"
            "  and re-run."
        )
    except urllib.error.URLError as e:
        die(f"image upload failed for {path.name}: {e.reason}")

    # Response shape: {"image": ["https://media.dev.to/.../x.png"]} (or a string).
    img = payload.get("image")
    url = img[0] if isinstance(img, list) and img else img
    if not url:
        die(f"image upload for {path.name} returned no URL: {payload}")
    return url


# --------------------------------------------------------------------------- #
# transforms
# --------------------------------------------------------------------------- #
def is_local(ref):
    return not re.match(r"^[a-z][a-z0-9+.-]*://", ref, re.I) and not ref.startswith("//")


def resolve_local_image(base_dir, ref, api_key, state, cache):
    """Upload a local image (once, cached) and return its CDN URL.

    `cache` maps "path::contenthash" -> url and lives inside the post's state
    entry, so unchanged images are never re-uploaded.
    """
    abs_path = (base_dir / ref).resolve()
    if not abs_path.is_file():
        die(f"local image not found: {ref} (resolved {abs_path})")
    key = f"{abs_path}::{file_hash(abs_path)}"
    if key in cache:
        info(f"  cached  {ref} -> {cache[key]}")
        return cache[key]
    info(f"  upload  {ref} ...")
    url = upload_image(abs_path, api_key)
    cache[key] = url
    info(f"          -> {url}")
    return url


def rewrite_images(text, base_dir, api_key, cache):
    """Rewrite local inline images AND a local front-matter cover_image."""

    def repl_inline(m):
        ref = m.group("path")
        if not is_local(ref):
            return m.group(0)
        url = resolve_local_image(base_dir, ref, api_key, {}, cache)
        rest = m.group("rest") or ""
        return f"![{m.group('alt')}]({url}{rest})"

    text = IMG_RE.sub(repl_inline, text)

    def repl_cover(m):
        ref = m.group(2).strip()
        if not ref or not is_local(ref):
            return m.group(0)
        url = resolve_local_image(base_dir, ref, api_key, {}, cache)
        return f"{m.group(1)}{url}"

    # cover_image: ./images/x.png  (only within the leading front-matter block)
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            head, body = text[: end + 4], text[end + 4 :]
            head = re.sub(
                r"(?m)^(cover_image:[^\S\n]*)(.*)$",
                repl_cover,
                head,
            )
            text = head + body
    return text


def force_published(text, published):
    """Set the front-matter `published:` line. Only touches the FM block."""
    value = "true" if published else "false"
    if not text.startswith("---"):
        return text
    end = text.find("\n---", 3)
    if end == -1:
        return text
    head, body = text[: end + 4], text[end + 4 :]
    if re.search(r"(?m)^published:", head):
        head = re.sub(r"(?m)^published:[^\S\n]*.*$", f"published: {value}", head, count=1)
    else:
        # insert right after the opening '---'
        head = re.sub(r"^---\n", f"---\npublished: {value}\n", head, count=1)
    return head + body


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main(argv):
    args = [a for a in argv[1:] if a != "--publish"]
    publish = "--publish" in argv[1:]
    if len(args) != 1:
        die("usage: publish-devto.py <path-to-post.md> [--publish]", code=2)

    post_path = Path(args[0]).resolve()
    if not post_path.is_file():
        die(f"post not found: {post_path}", code=2)

    api_key = load_api_key()
    state = load_state()
    entry = state.setdefault(str(post_path), {})
    cache = entry.setdefault("images", {})

    text = post_path.read_text(encoding="utf-8")

    info("resolving images ...")
    text = rewrite_images(text, post_path.parent, api_key, cache)
    text = force_published(text, publish)

    body = {"article": {"body_markdown": text}}
    article_id = entry.get("article_id")

    if article_id:
        info(f"updating existing draft (id {article_id}) ...")
        status, resp = api_request(
            f"{ARTICLES_URL}/{article_id}", api_key, method="PUT", json_body=body
        )
    else:
        info("creating new draft ...")
        status, resp = api_request(
            ARTICLES_URL, api_key, method="POST", json_body=body
        )
        entry["article_id"] = resp.get("id")

    save_state(state)

    url = resp.get("url") or resp.get("canonical_url") or "(no url returned)"
    state_word = "published" if publish else "draft"
    info(f"done ({status}). {state_word}:")
    print(url)


if __name__ == "__main__":
    main(sys.argv)
