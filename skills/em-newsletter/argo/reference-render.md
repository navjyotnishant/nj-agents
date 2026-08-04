# Render and QA

Structure the report as a **paginated issue**, not a scroll. An EM works one
account at a time, so the page break falls where the account boundary already is.

```
Cover  →  one page per account  →  Market  →  Competition
```

---

## Cover

- Wordmark
- Issue title: `Vertical Pulse - <Vertical>` or `Account Deep-Dive - <Vertical>`
- Week, account count, coverage tier
- Lead story with its hero image
- **Contents list**: each account with its story and people-move counts. In a
  paginated issue this is the cover's real job — it tells the reader how many
  accounts are in this week's book before they start flipping.

## One page per account

Two columns. Left carries the week's facts, right carries the interpretation.

- **This week** — numbered stories, each with its image and a linked source.
  Numbering is real here: with several accounts an EM works the list in order, so
  the index encodes sequence rather than decorating it.
- **People moves** — a **table**, so names, moves and roles align down the column.
  An EM comparing three accounts wants to scan these, not read them as prose. Set
  the move verb (`joins as`, `promoted to`, `departing`, `new role`) in a colour
  keyed to its kind.
- **EM Insight** — the interpretation, with **Ask This inside the same panel**,
  separated by a rule. The questions are what the interpretation leads to; they are
  not a second competing sidebar.
- **In the vertical** — 2-3 market items for context, **rotating by page** so two
  accounts do not show the same three.

> On that last block: an earlier version scored each market item for relevance to
> the account, by name match and shared content words, and scored zero across the
> board — one account's week was licences and layoffs while the vertical's week was
> agentic payments. The vocabularies did not meet and no threshold rescued it.
> Since every account in the issue is in the same vertical, the whole pulse is
> legitimate background for any of them. Filtering was false precision.

## Market and Competition

Vertical pulse, technology radar and deals in columns. Then the competitive entries
grouped by `kind` under plain-English headings:

| `kind` | Heading | Sub |
|---|---|---|
| `engagement` | At your accounts | Rival firms winning or expanding work |
| `offering` | What they are selling | Accelerators and platforms rivals market |
| `peer` | Across the vertical | What non-account companies are building |

---

## Interaction

- **The whole news frame is the link**, not just the source credit. Hover tints the
  row; the target opens in a new tab with `rel="noopener noreferrer"`.
- Source credits carry a `→` so the affordance is visible without hovering.
- Pagination is an **enhancement**: pages must stack and print in order with
  JavaScript disabled, so the whole issue stays readable as one document.

## Quality floor

- **Minimum type size 11px.** Anything smaller is unreadable in most mail clients.
  (A reference template used 9px labels; they did not survive contact with a real
  inbox.)
- Real `alt` text on every image.
- Visible keyboard focus: `:focus-visible` with a 2px accent outline, never the
  browser default.
- Responsive to 390px.
- Respect `prefers-reduced-motion`.
- Never hotlink a logo as a remote WEBP: Outlook cannot render WEBP and image
  proxies block remote logos, so the mark vanishes exactly where the report is
  read. Set the wordmark in type or inline SVG.

---

## Palette

Ground the design in the user's own brand if they have one. Absent that, a
newspaper palette reads correctly for this content:

| Role | Light | Dark variant |
|---|---|---|
| Outer surround | `#E8E4DC` | `#121C26` |
| Paper | `#F5F1E8` | `#1D2D3D` |
| Ink / type | `#0A1E3D` | `#F5F5F8` |
| Accent | `#C8A96E` gold | `#94BCE3` steel |
| Body | `#3D3830` | `#C9D4DE` |
| Rules | `#C8C0B0` | `#32485C` |
| Insight panel | `#F0EBE0` | `#16232F` |

Severity: `HIGH` red `#C0392B` · `MEDIUM` orange `#E8560A` · `LOW` slate `#4A6480`.

On a dark ground, accent steps go **lighter**, not darker.

### Client brand colour

**Each account is keyed by its own brand colour** — it is how the reader tells
accounts apart while flipping. Resolve in this order:

1. Pinned in config (`brand_color`)
2. Read from the client's website (`theme-color` meta, or the dominant logo colour)
3. Derived deterministically from the account name, so the same account always gets
   the same colour

Whatever the source, ensure it holds contrast against the page ground; adjust
lightness rather than picking a different hue.

---

## Type

Playfair Display (or another high-contrast serif) for headlines and the masthead;
Source Serif 4 (or a readable text serif) for body copy; DM Sans (or a neutral
grotesk) for labels, metadata and links. Headlines 700; masthead 900.

---

## QA gate

Before delivering, check the rendered report:

- [ ] Coverage indicator present — which sources were live vs fallback, and the tier
- [ ] No em-dashes or double-dashes in prose. CSS custom properties and vendor
      prefixes legitimately use `--`; do not flag those.
- [ ] No quarantined claim rendered as a story
- [ ] Every `url` is a real evidence URL, not a constructed one
- [ ] No credential, token, or CRM identifier anywhere in the output
- [ ] No fact appears twice (see the dedup rules in the instructions)
- [ ] Every image has alt text; no image appears twice
- [ ] Type floor respected; focus states visible

The editor may **reopen** a claim and send it back for re-synthesis, bounded to a
small number of rounds. **Ambiguity resolves toward quarantine, never toward
publishing.**
