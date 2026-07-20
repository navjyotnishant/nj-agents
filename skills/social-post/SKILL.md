---
name: social-post
description: Use this skill when the user asks to "write a LinkedIn post", "draft a launch post", "promote this blog on X/Twitter", "share this on social", or wants promotional copy for a published article, project, or release. Given a published URL (blog, repo, demo) it drafts ready-to-paste social copy in short / medium / builder-story variants, gets the hook and links right for the platform's feed algorithm, and keeps hashtags clean. Grounds the copy in the actual linked content — never invents claims. Produces copy for the user to post; it does not auto-post.
version: 0.1.0
---

# Social post (LinkedIn / X promo)

Drafts promotional social copy for a **published** thing (a blog post, a repo, a
demo). Its whole job is the stuff that's easy to get wrong by hand: the in-feed hook,
the link that generates the preview card, hashtag hygiene, and honoring the author's
style. It **grounds every claim in the actual linked content** and hands the user
copy to paste — it never posts anything itself.

## Step 0 — Print the banner FIRST

```
╔══════════════════════════════════════════════════════════════════╗
║  SOCIAL POST — promo copy (LinkedIn / X)                         ║
╠══════════════════════════════════════════════════════════════════╣
║  Drafts short / medium / builder-story variants from a published ║
║  URL. Hook-first, clean hashtags, correct link + preview         ║
║  strategy. Grounded in the real content; never invents claims.   ║
║  Hands you copy to paste — never auto-posts.                    ║
╚══════════════════════════════════════════════════════════════════╝
```

## Prerequisites

- **A published URL** to promote (blog post, repo, demo). If the thing isn't published
  yet, say so — a social post needs a live link. If the user only has a local draft,
  offer to promote it once it's published, or write the copy with a placeholder link.
- **Platform** — default LinkedIn; also supports X/Twitter (shorter, different hashtag
  norms). Ask if unstated.

## Step 1 — Ground in the real content

**Fetch the URL** (WebFetch) and read it. The copy must reflect what the piece
actually says — the real problem, the real hook, the actual benefits — not a
plausible-sounding summary. Pull the strongest one-line hook and 2–3 concrete
benefits from the source. Never invent a metric, a feature, or a claim the source
doesn't make (same grounding bar as the authoring skills, `CONVENTIONS-authoring.md
§A6`).

## Step 2 — Confirm angle, length, CTA, style

Ask (or accept as parameters):
- **Angle** — personal builder story ("I built this to scratch an itch"), problem/insight
  hook, or straight announce.
- **Primary CTA** — read the blog / try the demo / star the repo. This decides which
  link leads.
- **Style prefs** — honor the same `style_prefs` the tech-blog skill uses (e.g. **no
  em-dashes** → use commas/colons/parentheticals; bold-Unicode styling for key
  phrases). Keep a real human voice, not AI-symmetric copy (reuse the tech-blog voice
  guidance: varied rhythm, first person, an actual point of view).

## Step 3 — Spawn the social-post agent

Spawn `social-post` with the fetched content + angle + platform + CTA + style prefs.
It returns the variants and the link/hashtag scaffolding (below). Review its output;
loop once if the hook or voice needs adjusting.

## Step 4 — Platform mechanics the copy must respect

These are feed-algorithm realities, not preferences — the agent applies them:

- **Hook first.** Feeds truncate after ~2 lines before "see more". The single
  strongest line goes first; no throat-clearing.
- **Link → preview card.** A platform builds the preview card from the **first URL** in
  the post. Put the link whose card you want (usually the blog, which has a cover
  image) **first**. A bare GitHub/markdown link makes an ugly card.
- **Multiple links suppress reach.** LinkedIn (and others) throttle posts with several
  outbound links. Keep **one link in the body** and put secondary links (demo, repo,
  API) in a **ready-to-paste first comment**. Provide that comment block.
- **Hashtags.** LinkedIn favors **3–5**; X favors **1–3**. Valid form only: no spaces,
  CamelCase for multi-word (`#WeekendProject`), dedupe, fix typos, drop invented tags.
- **You can delete the raw URL after the card renders.** Note this to the user (paste,
  let the card load, optionally remove the bare URL for a cleaner look).

## Step 5 — Deliver the variants

Hand the user **ready-to-paste** copy:
- **Short** (~60 words) — hook + one-line pitch + link.
- **Medium** (~130–150 words) — the LinkedIn sweet spot: hook, the "why", the pitch,
  an honest caveat if the piece has one, CTA.
- **Builder-story** (optional) — first-person "I hit this problem, so I built X".
- Plus: the **hashtag line**, the **first-comment block** (secondary links), and a
  one-line note on which link leads and why.

Do **not** post anything. Never call a social/publishing MCP without the user
explicitly asking and opting in; even then, draft-first and confirm before it goes
live. This skill's deliverable is copy the user posts themselves.
