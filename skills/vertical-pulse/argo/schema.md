# Schemas

Two contracts: what each research agent returns (Phase 1), and what synthesis
reduces them into (Phase 2).

---

## Phase 1 — source object

Every research agent returns this envelope. The barrier validates it before
Phase 2 starts.

```jsonc
{
  "source": "vertical-pulse" | "tech-ecosystem" | "competitive-landscape",
  "coverage": "live" | "partial" | "fallback",
  "generated_at": "<ISO-8601>",
  "claims": [
    {
      "id": "c1",                       // short, stable within this object
      "statement": "<one atomic, checkable assertion>",
      "confidence": "high" | "medium" | "low",
      "evidence": [
        { "url": "<real article URL>", "quote": "<supporting excerpt>" }
      ]
    }
  ],
  "notes": "<what was skipped, why fallback, caveats>"
}
```

**Rules**

- Every claim is **atomic**: one assertion, independently checkable. Split
  compound statements.
- `live` and `partial` objects **must** carry evidence-bearing claims. A claim with
  no evidence URL is dropped, not kept.
- A `fallback` object may have zero claims but **must** explain itself in `notes`.
- An agent that errors returns a `fallback` object. One agent must never sink the
  barrier.

---

## Phase 2 — report model

```jsonc
{
  "headline": "<the week's single most important story for these accounts>",
  "lead": "<1-2 sentence lede>",

  "vertical_pulse": [
    { "text": "", "source": "domain.com", "url": "https://…" }
  ],

  "clients": [
    {
      "name": "Remitly",
      "stories": [
        { "text": "", "source": "", "url": "" }
      ],
      "people_moves": [
        { "name": "", "role": "", "previous": "",
          "kind": "hire" | "promotion" | "departure" | "new-role",
          "date": "", "source": "", "url": "" }
      ],
      "em_insight": "<what it means for the relationship, and the conversation it opens>",
      "actions": [ "<2-3 questions to ask on the call>" ]
    }
  ],

  "tech_radar": [
    { "tech": "", "signal": "", "source": "", "url": "" }
  ],

  "deals": [
    { "severity": "HIGH" | "MEDIUM" | "LOW", "text": "", "source": "", "url": "" }
  ],

  "competitive": [
    { "kind": "engagement" | "offering" | "peer",
      "who": "", "what": "",
      "account": "",     // "" when not account-specific
      "so_what": "",     // why the EM should care
      "source": "", "url": "" }
  ],

  "em_lens": [ "<3-4 conversation starters that work across accounts>" ]
}
```

### Field rules

**`source` and `url`** — `source` is the domain shown as a credit; `url` is the
article itself. Both come from the claim's evidence. **Copy the URL exactly.**
Never construct, shorten, or guess one; no evidence URL means an empty string.

**`people_moves.previous`** — empty string when the source does not state the
prior role. Do not infer it.

**`people_moves.date`** — as stated by the source; empty string if absent.

**`deals.severity`** — client impact, not newsworthiness. `HIGH` means it changes
what the EM does this week.

**`competitive.kind`**
- `engagement` — a rival services firm at one of *our* accounts (displacement risk)
- `offering` — productized IP a rival markets (what we are benchmarked against)
- `peer` — a non-account company in the client's vertical (context)

**An account with no verified news** — empty `stories`, and an `em_insight` naming
the gap. Do not invent filler for a quiet week.

**Prose** — no em-dashes, no double-dashes anywhere in the output.
