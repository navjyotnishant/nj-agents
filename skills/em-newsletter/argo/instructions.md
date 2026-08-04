# EM Newsletter

Builds an Engagement Manager's weekly intelligence report: what moved at their
accounts, what to say on this week's calls, and what backs it up.

**The reader**: an EM with a handful of client relationships and roughly eight
minutes before a call. **The report's one job**: tell them what to say, and show
them what backs it up. Every ordering and layout decision follows from that.

## Attached references

Load each only when the phase that needs it runs. Do not read them all up front.

| File | Read it when |
|---|---|
| `reference-taxonomy.md` | resolving the vertical (Phase 0) |
| `schema.md` | emitting Phase-1 claims or the Phase-2 report model |
| `reference-trust.md` | verifying claims (Phase 1.5) |
| `reference-render.md` | structure, palette and the QA checklist (Phase 3) |
| `reference-skeleton.md` | **the actual HTML** (Phase 3) |

`reference-skeleton.md` carries the real markup and stylesheet. **Use it rather
than authoring HTML from the prose description.** It is what makes every issue look
like the same publication instead of a fresh design each week.

---

## Runtime requirements

| Capability | Needed for | If absent |
|---|---|---|
| Web search / fetch | research, verification | **BLOCK** — say so; the report cannot be grounded |
| Code execution | rendering, image fetch, dedup | degrade: emit the HTML directly |
| CRM access (SFDC/Zoho) | relationship signals | degrade: mark `fallback` in the coverage banner |

**Detect, never require.** A missing capability is a degrade, never a failure. The
one exception is web search: without it there is nothing to verify against, and a
report of unverified assertions is worse than no report.

---

## 1. Inputs

```jsonc
{
  "profile": "vertical-pulse",        // or "account-deepdive"
  "vertical": "FinTech",
  "sub_verticals": ["Payment Tech"],  // optional; derived from the taxonomy
  "clients": [
    { "name": "Remitly", "website": "remitly.com", "brand_color": "#1B6BC5" }
  ],
  "technologies": ["GenAI", "Agentic AI"],
  "competitors": ["TCS", "Infosys", "EPAM"],
  "people_intelligence": false,       // gate: see §4b
  "week_of": "auto",                  // literal run date, never rounded
  "verify_mode": "smart"              // full | smart | light | off
}
```

Ask for anything missing rather than assuming. `vertical` and at least one client
are required; everything else has a working default.

**On a shared platform**: each user's config, CRM credentials and account list are
theirs alone. Never carry one user's accounts, contacts or CRM data into another
user's run. Never write credentials into the report, the logs, or the prompt
history.

---

## 2. Pipeline

```
Phase 0   capability & scope         deterministic
Phase 1   parallel research          3 agents, fan-out → BARRIER (schema-validate)
Phase 1.5 adversarial verification   per-claim, parallel
Phase 2   synthesis                  sequential reduce
Phase 2.5 imagery                    deterministic, degrade-never-fail
Phase 3   QA, edit, render, deliver  gate + bounded reopen loop
```

**Orchestration is deterministic, never a model.** The barrier does not release
Phase 2 until every Phase-1 object is present and schema-valid. An absent source
yields a `fallback` object, not a stall.

Resolve the vertical against `reference-taxonomy.md` and adopt its sub-verticals
as research scope. A vertical outside the list is fine: research it directly and
note that no sub-vertical scope was applied.

---

## 3. Phase 1 — research (three agents, in parallel)

Every claim is **atomic and individually checkable**, and carries at least one
evidence URL with a supporting quote. A claim with no evidence is dropped, not
kept. Envelope shape is in `schema.md`.

### 3a. Vertical pulse

The vertical, its sub-verticals, and the named accounts over the last 7 days:

- Industry news and trends
- Per-account product and engineering moves: launches, platform migrations,
  technology decisions, partnerships
- Leadership and people moves (**gated** — see 3b)
- Funding, M&A, and other deal signals

Prefer the last week. **Note thin coverage rather than padding with stale news** —
an EM can tell, and a padded report stops being read.

### 3b. People moves — the gate

A new CTO or a promoted VP is the EM's warmest call reason. It is also personal
data about a named individual, so the ask is scoped by `people_intelligence`:

**`true`** — appointments, hires, internal promotions into leadership, departures,
newly created senior roles. Capture name, incoming role, prior role if stated, and
the announcement date.

**`false` (default)** — organisational level only: newly created senior roles,
restructures, team and division changes. Name a person only when the source is the
company's own announcement of that appointment.

**Both modes**: report a move only when a source explicitly announces it. **Never
infer a person's employer, title, or seniority.** Skip anyone whose current role
you cannot confirm from the source itself. A wrong name in front of a client costs
more than a missing one.

### 3c. Technology ecosystem

Per technology, how it is being adopted **in this vertical**: enterprise adoption
signals, vendor and product moves, concrete use cases. This answers "what are my
clients being pitched", not "what is new in AI".

### 3d. Competitive landscape

Three distinct questions, tagged by `kind`:

- **`engagement`** — a rival services firm winning or expanding work **at one of
  the named accounts**. Displacement risk. Tag it with the account.
- **`offering`** — productized IP a rival markets: accelerators, migration
  frameworks, industry platforms, delivery tooling. What you are benchmarked
  against in a pitch.
- **`peer`** — what other companies **in the client's vertical** (not accounts) are
  building. Context on where the client sits against its own competition.

**Report an absence honestly.** "No services firm was publicly named at this
account this cycle" is a real finding and beats a manufactured one.

---

## 4. Phase 1.5 — adversarial verification

Read `reference-trust.md` for the allowlist, the auto-trust rules, and the modes.

Each claim ends `verified`, `trusted`, or `quarantined`. **Flag, never drop**: a
quarantined claim stays in the record with its reason, but is **never rendered as
a story**.

Claims that are not auto-trusted get three reviewers with distinct stances —
**corroborate** (find independent confirmation), **cross-check** (does the cited
source actually say this?), **refute** (actively try to disprove it). Each returns
`support` / `unsure` / `reject` with a rationale. **Any `reject` quarantines the
claim**; record which reviewer rejected it and why.

**State the cost shape before running.** A measured run: 45 claims at `smart`
produced 133 model calls over 12.5 minutes. Get a yes before spending it.

---

## 5. Phase 2 — synthesis

Reduce verified and trusted claims into the report model in `schema.md`.
**Introduce no fact that is not in them.**

- **`url` is the evidence URL, copied exactly.** Never construct, shorten, or guess
  one. No evidence URL means an empty string — a broken link costs more than a
  missing one.
- **Severity is client impact**, not newsworthiness. `HIGH` means it changes what
  the EM does this week.
- **An account with no verified news** gets an empty `stories` list and an
  `em_insight` naming the gap. Do not invent filler; say the week was quiet and
  suggest treating the call as discovery.
- **No em-dashes, no double-dashes** anywhere in the output prose.

---

## 6. Deduplication

Raw synthesis repeats itself badly: the same funding round lands in
`vertical_pulse`, `deals`, and `tech_radar`. Readers experience that as padding.

**Every fact appears exactly once.** Render in priority order and let each section
claim the facts it uses:

```
client stories  >  people moves  >  competitive  >  deals  >  vertical pulse
```

**Match on content words, not exact strings.** Strip articles, prepositions and
sentence scaffolding; compare what remains. Sharing **≥ 0.35** of content words
with something already shown means it is a restatement — drop it.

Two refinements learned the hard way:

- **Dedup within a class, never across.** Facts compete with facts, questions with
  questions. A question that mentions a fact in passing ("Given the Stripe-PayPal
  bid, ask whether…") is *not* a restatement of it. Pooling them made the evidence
  ledger lose real facts to openers that merely named them.
- **Compare against each prior item separately**, not a merged vocabulary pool. A
  pooled set grows until unrelated sentences match it by accident.

Calibration from real runs: a paraphrase scores ~0.40; two genuinely distinct facts
about one company (a licence win and a layoff) score ~0.07. The gap is wide, so
0.35 is safe.

---

## 7. Phase 2.5 — imagery

Fetch each source article's `og:image` (falling back to `twitter:image`) and inline
it as a base64 data URI.

**Why inline rather than hotlink**: the report is read in an inbox. Outlook blocks
remote images by default, publishers rotate asset URLs within weeks, and every
hotlinked image pings the publisher's server with the reader's IP. A data URI is
self-contained, survives forwarding, and leaks nothing.

This phase fetches arbitrary third-party URLs. Bound it on five axes:

1. **Scheme and host** — public `http(s)` only. Resolve the hostname and reject
   private, loopback, link-local, reserved, multicast and unspecified ranges. These
   URLs come from model output about pages found on the web, so they are
   attacker-influenceable; without this check a crafted citation turns the run into
   a request against internal infrastructure.
2. **Content type** — `image/jpeg`, `png`, `webp`, `gif` only. **Refuse SVG**: it
   can carry script and would be inlined into a document a person opens.
3. **Size** — skip anything over ~900 KB. Skip, never truncate: a truncated image
   renders as a broken box, which is worse than none.
4. **Count and time** — ~12 distinct images per report, with per-request timeouts.
5. **Quality** — the two filters below.

**Drop publisher branding.** Wire services serve their own logo as `og:image` on
every release, so the picture is the distributor's mark, not the story. Skip
`globenewswire.com`, `businesswire.com`, `prnewswire.com`, `stocktitan.net`,
`accesswire.com`, `newsfilecorp.com`, `einpresswire.com`, and any image whose path
names itself as branding (`logo`, `wordmark`, `favicon`, `default`, `placeholder`,
`og-default`, `share-image`, `social-card`). *A logo card is worse than no image:
same space, draws the eye, tells the reader nothing.* In one measured run, 4 of 7
thumbnails were logo cards from exactly these sources.

**Never show the same image twice.** Publishers reuse one stock photo across many
articles. Hash the bytes and skip duplicates — the same contactless-payment photo
appeared beside two unrelated claims in a real run.

**Every failure degrades to "no image."** The report renders identically without
pictures.

---

## 8. Phase 3 — render and QA

**The deliverable is one self-contained HTML file.** Every image inlined as a
base64 data URI, no external stylesheet, no external script, no remote image. The
only external reference is the Google Fonts link, which degrades to named
fallbacks. It has to survive being forwarded, saved, and opened offline.

**Start from `reference-skeleton.md`.** It carries the stylesheet and the markup
for every section, with four placeholders to fill (`{title}`, `{fonts}`, `{nav}`,
`{pages}`). Do not re-author the HTML from the prose in `reference-render.md` —
that file explains *why* the structure is what it is and carries the QA checklist;
the skeleton is *what to emit*.

Read `reference-render.md` for the page structure, palette, interaction rules and
the QA checklist.

**If code execution is available**, write a renderer that takes the report model and
fills the skeleton; determinism matters more than novelty. **If not**, emit the
filled skeleton directly.

The editor may **reopen** a claim and send it back for re-synthesis, bounded to a
small number of rounds. **Ambiguity resolves toward quarantine, never toward
publishing.**

---

## 9. Cost control

Every run spends real money.

- **Say the cost shape before starting** and get a yes.
- **Hard cap: 2 fix rounds.** After two failed QA cycles on the same artifact, stop
  and report what is fixed, what still fails, and the options.
- **A blocking verdict is a checkpoint, not a to-do.** Surface it; do not silently
  fix and re-run.
- **Cheap path first.** When the user is iterating on layout, re-render existing
  output rather than re-running research.
- **Stop on any signal to stop** — "this is expensive", an interrupt, a suggested
  change of approach.

---

## 10. Never

- Invent a fact, figure, company, person, or source URL
- Infer a person's employer, title, or seniority
- Render a quarantined claim as though it were verified
- Carry one user's accounts, contacts or CRM data into another user's run
- Write credentials into the report, logs, or prompt history
- Commit, push, or email anything without explicit instruction
