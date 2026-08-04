---
name: em-newsletter
description: "Use this skill when the user asks to \"generate the EM newsletter\", \"run the weekly account intelligence report\", \"build the engagement manager briefing\", \"do a vertical pulse\", or \"run an account deep-dive\". Produces a verified, sourced, illustrated weekly intelligence report for an Engagement Manager covering their book of accounts, a market pulse, leadership moves and the competitive landscape. Runs a research → adversarial verification → synthesis → render pipeline where every claim is either corroborated or visibly quarantined. Self-contained: carries the whole method inline, so it runs on any agentic platform with code execution and web search. For a one-line shortcut into a single vertical, use /vertical-pulse."
version: 1.0.0
class: authoring
self_contained: true
author: navjyotnishant
---

# EM Newsletter

Builds an Engagement Manager's weekly intelligence report: what moved at their
accounts, what to say on this week's calls, and what backs it up.

**The reader**: an EM with a handful of client relationships and roughly eight
minutes before a call. **The report's one job**: tell them what to say, and show
them what backs it up. Every layout and ordering decision below follows from that.

This skill is **self-contained**. It carries the full method rather than pointing
at a codebase, so it runs anywhere that offers code execution and web search
(Argo, Claude Code, or a plain chat with tools). Nothing here is specific to one
company's repo.

---

## Runtime requirements

| Capability | Needed for | If absent |
|---|---|---|
| Web search / fetch | Phase 1 research, Phase 1.5 verification | **BLOCK** — say so; the report cannot be grounded |
| Code execution | Rendering, image fetch, dedup | Degrade: emit the HTML directly (see §9) |
| CRM access (SFDC/Zoho) | Relationship signals | Degrade: `fallback`, note it in the coverage banner |

**Detect, never require.** A missing capability is a *degrade*, never a failure.
The one exception is web search: without it there is nothing to verify against,
and a report of unverified assertions is worse than no report.

---

## 1. Inputs

Collect these before running. On a shared platform each user supplies their own.

```jsonc
{
  "profile": "vertical-pulse",        // or "account-deepdive"
  "vertical": "FinTech",              // see the taxonomy in §2
  "sub_verticals": ["Payment Tech"],  // optional; derived from the taxonomy if empty
  "clients": [
    { "name": "Remitly", "website": "remitly.com", "brand_color": "#1B6BC5" }
  ],
  "technologies": ["GenAI", "Agentic AI"],
  "competitors": ["TCS", "Infosys", "EPAM"],  // services rivals; see §4c
  "people_intelligence": false,       // gate: see §4b
  "week_of": "auto",                  // literal run date; never rounded
  "verify_mode": "smart"              // full | smart | light | off; see §5
}
```

Ask for anything missing rather than assuming. `vertical` and at least one client
are required; everything else has a working default.

**On a multi-user platform**: treat each user's config, CRM credentials and
account list as theirs alone. Never carry one user's accounts, contacts or CRM
data into another user's run, and never write credentials into the report, the
logs, or the prompt history.

---

## 2. Vertical taxonomy

Ground the research in a real vertical rather than free text. If the user's
vertical matches one of these, use its sub-verticals as the research scope:

- **FinTech** — Enterprise Fintech Solutions, Lending & Finance, Payment Tech, Wealth & Crypto, Cross-Border Payments, Construction Finance, Crypto & Stablecoins
- **Media & Advertising** — AdTech, Advertising & Marketing, Entertainment Production, Publishing, Video Streaming & OTT
- **Software & Hi-Tech** — Greenfield Development, Experience Modernization, Technology Transformation, Platform Consolidation
- **Travel & Hospitality** — Airlines, Car Rentals, Distribution, Hospitality, Events and Meetings
- **Retail**, **Supply Chain & Logistics**, **Healthcare & Life Sciences**

A vertical outside this list is fine: research it directly and note that no
sub-vertical scope was applied.

---

## 3. Pipeline shape

```
Phase 0   capability & scope         deterministic
Phase 1   parallel research          3 agents, fan-out → BARRIER (schema-validate)
Phase 1.5 adversarial verification   per-claim, parallel
Phase 2   synthesis                  sequential reduce
Phase 2.5 imagery                    deterministic, degrade-never-fail
Phase 3   QA, edit, render, deliver  gate + bounded reopen loop
```

**The orchestration is deterministic, never a model.** The barrier does not
release Phase 2 until every Phase-1 object is present and schema-valid. An absent
source yields a `fallback` object, not a stall.

---

## 4. Phase 1 — research (three agents, in parallel)

Each agent returns the same envelope:

```jsonc
{
  "source": "vertical-pulse" | "tech-ecosystem" | "competitive-landscape",
  "coverage": "live" | "partial" | "fallback",
  "generated_at": "<ISO-8601>",
  "claims": [
    { "id": "c1",
      "statement": "<one atomic, checkable assertion>",
      "confidence": "high" | "medium" | "low",
      "evidence": [ { "url": "<real article URL>", "quote": "<excerpt>" } ] }
  ],
  "notes": "<what was skipped, why fallback, caveats>"
}
```

Every claim must be **atomic and individually checkable** — Phase 1.5 verifies
each one on its own. A claim with no evidence URL is dropped, not kept.

### 4a. Vertical pulse agent

Research the vertical, its sub-verticals, and the named accounts over the last 7
days. Find:

- Industry news and trends in the vertical
- Per-account product and engineering moves: launches, platform migrations,
  technology decisions, partnerships
- Leadership and people moves (**gated** — see 4b)
- Funding, M&A, and other deal signals

Prefer items from the last week. **Note thin coverage rather than padding with
stale news** — an EM can tell, and a padded report stops being read.

### 4b. People moves — the gate

Leadership changes are the EM's warmest call reason: a new CTO or a promoted VP
is a reason to call this week. They are also personal data about named
individuals, so the ask is scoped by `people_intelligence`:

**When `true`** — newly appointed or hired executives and senior leaders,
internal promotions into leadership, departures, and newly created senior roles.
For each, capture the person's name, the role they move into, the role they held
before if stated, and the announcement date.

**When `false` (the default)** — stay at the organisational level: newly created
senior roles, restructures, team and division changes. Name a person only when
the source is the company's own announcement of that appointment.

**In both modes**: report a move only when a source explicitly announces it.
**Never infer a person's current employer, title, or seniority.** Skip anyone
whose current role at the account you cannot confirm from the source itself. A
wrong name in front of a client costs more than a missing one.

### 4c. Technology ecosystem agent

For each technology in scope, research how it is being adopted **in this
vertical**: enterprise adoption signals, notable vendor and product moves, and
concrete use cases. The output answers "what are my clients being pitched right
now", not "what is new in AI".

### 4d. Competitive landscape agent

Three distinct questions, tagged by `kind`:

- `engagement` — a **rival services firm** winning or expanding work **at one of
  the named accounts**. This is displacement risk. Tag it with the account.
- `offering` — productized IP a rival markets: accelerators, migration
  frameworks, industry platforms, delivery tooling. This is what you are
  benchmarked against in a pitch.
- `peer` — what **other companies in the client's vertical** (not accounts) are
  building. Context on where the client sits against its own competition.

Each entry carries `who`, `what`, `account` (empty when not account-specific),
`so_what` (why the EM should care), `source`, `url`.

**Report an absence honestly.** "No services firm was publicly named at this
account this cycle" is a real finding and more useful than a manufactured one.

---

## 5. Phase 1.5 — adversarial verification

The costliest phase and the one that makes the report trustworthy. Each claim
ends in one of three verdicts:

| Verdict | Meaning | Usable in the report |
|---|---|---|
| `verified` | passed the reviewer quorum | yes |
| `trusted` | auto-trusted, reviewer-free | yes |
| `quarantined` | kept but flagged | **no** — excluded from stories |

**Flag, never drop.** A quarantined claim stays in the record with its reason, so
the reader can see what was rejected and why.

### The trust rule (spend reviewer budget on the doubtful ones)

Auto-trust a claim on any of these, cheapest check first:

1. **Multi-source** — 2 or more independent citing domains. Already corroborated.
2. **Primary / official** — the company's own domain including `ir.`, `investor.`,
   `investors.`, `newsroom.`, `news.`, `press.`, `media.` subdomains; a regulator;
   or any `.gov`, `.gov.uk`, `.gov.sg`, `.edu`, `.ac.uk`, `.int`, `.mil` suffix.
3. **Reputable outlet** — a curated allowlist: Reuters, AP, Bloomberg, FT, WSJ,
   NYT, Economist, CNBC, BBC, Guardian, Forbes, Axios, Fortune, MarketWatch;
   Morningstar, PitchBook, Crunchbase, Statista, Gartner, McKinsey, Deloitte,
   PwC, KPMG, EY, CB Insights; Finextra, American Banker, PaymentsDive, PYMNTS,
   TechCrunch, The Verge, Wired, Banking Dive, FinTech Futures, CoinDesk,
   fintech.global, Ledger Insights; SEC, Federal Reserve, OCC, FDIC, FINRA,
   ECB, BIS, World Bank, IMF, MAS, FCA, Bank of England.

The principle: *a claim already corroborated, or cited to a legitimate primary
source, does not need independent re-verification.*

### Reviewer quorum

Claims that are not auto-trusted get three reviewers, each with a distinct
stance, returning `support` / `unsure` / `reject` with a rationale:

- **corroborate** — find independent confirmation
- **cross-check** — check the claim against the cited source; does the source
  actually say this?
- **refute** — actively try to disprove it

Any `reject` quarantines the claim. Record which reviewer rejected it and why.

### Modes and cost

| Mode | Rule | Relative spend |
|---|---|---|
| `full` | 3-reviewer quorum on every claim | highest |
| `smart` (default) | auto-trust by the rule above; quorum on the rest | ~1x |
| `light` | 1 reviewer (cross-check) per claim | ~1/3 |
| `off` | no reviewers; every claim trusted as fetched | minimal |

**State the cost shape before running.** A measured run: 45 claims at `smart`
produced 133 model calls over 12.5 minutes. Tell the user the expected order of
magnitude and get a yes before spending it. `light` is the right default when the
user is iterating on layout rather than content.

---

## 6. Phase 2 — synthesis

Reduce the verified claims into the report model. **Use only verified and trusted
claims. Introduce no fact that is not in them.**

```jsonc
{
  "headline": "<the week's single most important story for these accounts>",
  "lead": "<1-2 sentence lede>",
  "vertical_pulse": [ { "text": "", "source": "domain.com", "url": "https://…" } ],
  "clients": [
    { "name": "Remitly",
      "stories":      [ { "text": "", "source": "", "url": "" } ],
      "people_moves": [ { "name": "", "role": "", "previous": "",
                          "kind": "hire|promotion|departure|new-role",
                          "date": "", "source": "", "url": "" } ],
      "em_insight": "<what it means for the relationship and the conversation it opens>",
      "actions":    [ "<2-3 questions to ask on the call>" ] }
  ],
  "tech_radar":  [ { "tech": "", "signal": "", "source": "", "url": "" } ],
  "deals":       [ { "severity": "HIGH|MEDIUM|LOW", "text": "", "source": "", "url": "" } ],
  "competitive": [ { "kind": "engagement|offering|peer", "who": "", "what": "",
                     "account": "", "so_what": "", "source": "", "url": "" } ],
  "em_lens": [ "<3-4 conversation starters that work across accounts>" ]
}
```

**`url` is the evidence URL, copied exactly.** Never construct, shorten, or guess
one. If a fact has no evidence URL, use an empty string — a broken link costs
more than a missing one.

**Severity is client impact**, not newsworthiness: `HIGH` means it changes what
the EM does this week.

**An account with no verified news** gets an empty `stories` list and an
`em_insight` naming the gap. Do not invent filler for a quiet week; say it was
quiet and suggest treating the call as discovery.

**Prose rule**: no em-dashes, no double-dashes anywhere in the output.

---

## 7. Deduplication

Raw synthesis repeats itself badly: the same funding round lands in
`vertical_pulse`, `deals`, and `tech_radar`. Readers experience that as padding.

**Rule: every fact appears exactly once.** Render sections in priority order and
let each claim the facts it uses:

```
client stories  >  people moves  >  competitive  >  deals  >  vertical pulse
```

**Match on content words, not exact strings.** Strip articles, prepositions, and
sentence scaffolding; compare the remaining content words. If a new item shares
**≥ 0.35** of its content words with something already shown, it is a
restatement — drop it.

Two refinements learned the hard way:

- **Dedup within a class, never across.** Facts compete with facts and questions
  with questions. A question that mentions a fact in passing ("Given the
  Stripe-PayPal bid, ask whether…") is *not* a restatement of that fact. Pooling
  them made the evidence ledger lose real facts to openers that merely named them.
- **Compare against each prior item separately**, not against a merged vocabulary
  pool. A pooled set grows until unrelated sentences match it by accident.

Calibration from real runs: a paraphrased restatement scores ~0.40; two genuinely
distinct facts about the same company (a licence win and a layoff) score ~0.07.
The gap is wide, so 0.35 is safe.

---

## 8. Phase 2.5 — imagery

Fetch each source article's `og:image` (falling back to `twitter:image`) and
inline it as a base64 data URI.

**Why inline rather than hotlink**: the report is read in an inbox. Outlook blocks
remote images by default, publishers rotate asset URLs within weeks, and every
hotlinked image pings the publisher's server with the reader's IP. A data URI is
self-contained, survives forwarding, and leaks nothing.

This phase fetches arbitrary third-party URLs, so it is bounded on five axes:

1. **Scheme and host** — reject anything that is not public `http(s)`. Resolve the
   hostname and reject private, loopback, link-local, reserved, multicast and
   unspecified ranges. These URLs originate in model output about pages found on
   the web, so they are attacker-influenceable; without this check a crafted
   citation turns the run into a request against internal infrastructure.
2. **Content type** — only `image/jpeg`, `png`, `webp`, `gif`. **Refuse SVG**: it
   can carry script and would be inlined into a document a person opens.
3. **Size** — skip anything over ~900 KB. Skip, never truncate: a truncated image
   renders as a broken box, which is worse than none.
4. **Count and time** — roughly 12 distinct images per report, with per-request
   timeouts.
5. **Quality** — see below.

### Two quality filters, both learned from a live run

**Drop publisher branding.** Wire services and filing aggregators serve their own
logo as `og:image` on every release, so the picture is the distributor's mark
rather than anything about the story. Skip images from `globenewswire.com`,
`businesswire.com`, `prnewswire.com`, `stocktitan.net`, `accesswire.com`,
`newsfilecorp.com`, `einpresswire.com`, and skip any image whose path names
itself as branding (`logo`, `wordmark`, `favicon`, `default`, `placeholder`,
`og-default`, `share-image`, `social-card`). *A logo card is worse than no image:
it takes the same space, draws the eye, and tells the reader nothing.* In one
measured run, 4 of 7 thumbnails came back as logo cards from exactly these
sources.

**Never show the same image twice.** Publishers reuse one stock photo across many
articles. Hash the image bytes and skip duplicates — the same contactless-payment
photo appeared beside two unrelated claims in a real run.

**Every failure degrades to "no image".** The report renders identically without
pictures.

---

## 9. Phase 3 — render

Structure the report as a **paginated issue**, not a scroll. An EM works one
account at a time, so the page break falls where the account boundary already is:

```
Cover  →  one page per account  →  Market  →  Competition
```

### Cover
Wordmark, issue title (`Vertical Pulse - <Vertical>` or
`Account Deep-Dive - <Vertical>`), the week, the lead story with its hero image,
and a contents list showing each account with its story and people-move counts.

### One page per account
- **This week** — numbered stories, each with its image and a linked source
- **People moves** — a table so names, moves and roles align down the column; an
  EM comparing three accounts wants to scan these, not read them
- **EM Insight** — the interpretation, with **Ask This** *inside the same panel*.
  The questions are what the interpretation leads to; they are not a second
  competing sidebar.
- **In the vertical** — 2-3 market items for context, rotating by page so two
  accounts do not show the same three

### Market and Competition
Vertical pulse, technology radar and deals in columns; then the competitive
entries grouped by `kind` under plain-English headings ("At your accounts",
"What they are selling", "Across the vertical").

### Interaction and quality floor
- **The whole news frame is the link**, not just the source credit. Hover tints
  the row; the target opens in a new tab with `rel="noopener noreferrer"`.
- **Minimum type size 11px.** Anything smaller is unreadable in most mail clients.
- Real `alt` text on every image; visible keyboard focus on every link
  (`:focus-visible` with a 2px accent outline, never the browser default).
- Responsive to 390px. Respect `prefers-reduced-motion`.
- Pages must **stack and print in order** with JavaScript disabled — pagination is
  an enhancement, not a requirement for reading.

### Palette
Ground the design in the user's own brand if they have one. Absent that, a
newspaper palette reads correctly for this content: newsprint `#E8E4DC`, paper
`#F5F1E8`, ink navy `#0A1E3D`, gold `#C8A96E`, body `#3D3830`, rules `#C8C0B0`,
insight panel `#F0EBE0`; severity in red `#C0392B` / orange `#E8560A` / slate
`#4A6480`. A dark variant is legitimate: steel ground `#1D2D3D` with type
reversed to paper.

**Each account is keyed by its own brand colour** — pinned in config, else read
from the client's website, else derived deterministically from the name so the
same account always gets the same colour. Colour is how the reader tells accounts
apart while flipping.

**If code execution is available**, write a renderer that takes the report model
and emits the HTML; determinism matters more than novelty here. **If not**, emit
the HTML directly from the model, following this structure.

---

## 10. QA gate

Before delivering, check the rendered report:

- Coverage indicator present (which sources were live vs fallback, and the tier)
- No em-dashes or double-dashes in prose (CSS custom properties and vendor
  prefixes legitimately use `--`; do not flag those)
- No quarantined claim rendered as a story
- Every `url` is a real evidence URL, not a constructed one
- No credential, token, or CRM identifier anywhere in the output

The editor may **reopen** a claim and send it back for re-synthesis, bounded to a
small number of rounds. Ambiguity resolves toward quarantine, never toward
publishing.

---

## 11. Cost control

This pipeline spends real money on every run.

- **Say the cost shape before starting** and get a yes.
- **Hard cap: 2 fix rounds.** After two failed QA cycles on the same artifact,
  stop and report what is fixed, what still fails, and the options.
- **A blocking verdict is a checkpoint, not a to-do.** Surface it; do not silently
  fix and re-run.
- **Cheap path first.** When the user is iterating on layout, re-render existing
  output rather than re-running research. Use `/vertical-pulse` for a fast
  single-vertical run.
- **Stop on any signal to stop** — "this is expensive", an interrupt, a suggested
  change of approach.

---

## 12. What this skill never does

- Never invents a fact, figure, company, person, or source URL
- Never infers a person's employer, title, or seniority
- Never renders a quarantined claim as though it were verified
- Never carries one user's accounts, contacts or CRM data into another user's run
- Never writes credentials into the report, logs, or prompt history
- Never commits, pushes, or emails anything without explicit instruction

Related: **`/vertical-pulse`** — the same pipeline as a one-line shortcut into a
single vertical.
