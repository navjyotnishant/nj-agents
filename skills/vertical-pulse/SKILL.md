---
name: vertical-pulse
description: "Use this skill when the user asks for \"vertical pulse FinTech\", \"vertical pulse for Travel & Hospitality\", \"this week in <vertical>\", \"what moved in <vertical> this week\", or names a vertical and wants the weekly market-and-accounts briefing without being asked a series of setup questions. A one-line shortcut into the EM newsletter pipeline: takes the vertical as its argument, resolves accounts and technologies from saved config or a short prompt, and runs research → verification → synthesis → render. Self-contained; runs on any agentic platform with code execution and web search. For the full setup path, profile choice, or an account deep-dive, use /em-newsletter."
version: 1.0.0
class: authoring
self_contained: true
author: navjyotnishant
---

# Vertical Pulse

`/vertical-pulse <Vertical>` — for example `/vertical-pulse FinTech`.

The fast path into the EM weekly briefing. Same pipeline and same output as
`/em-newsletter`, with the setup interview collapsed into a single argument.

**Use this** when the user knows their vertical and wants the report.
**Use `/em-newsletter`** for first-time setup, an account deep-dive, or when the
profile and accounts still need deciding.

---

## Method

**This skill delegates its method to `/em-newsletter`.** Read that skill and
follow it in full: the research phases, the trust rule, the reviewer quorum, the
synthesis model, the dedup rules, the imagery bounds and quality filters, the
render structure, and the QA gate all live there and are not repeated here.

What follows is only what differs.

---

## 1. Resolve the argument

The argument is the vertical. Match it case-insensitively against the taxonomy in
`/em-newsletter` §2 and adopt that vertical's sub-verticals as the research scope.
A vertical outside the list is fine: research it directly and note that no
sub-vertical scope was applied.

```
/vertical-pulse FinTech
/vertical-pulse "Travel & Hospitality"
```

**No argument** — list the taxonomy verticals and ask which one. Do not guess.

---

## 2. Resolve the rest without an interview

Fill the remaining inputs in this order, stopping at the first that answers:

1. **Saved config** — a config file, a saved profile, or the platform's stored
   inputs for this user
2. **The last run for this vertical** — reuse its accounts, technologies and
   competitors
3. **One short prompt** — ask for accounts only, and derive the rest:
   - `technologies` → default to `GenAI`, `Agentic AI`, `Cloud Infrastructure`
   - `competitors` → leave empty; the competitive agent researches the category
     generically rather than tracking a named roster
   - `people_intelligence` → `false` (the gate stays closed unless asked)
   - `week_of` → the literal run date, never rounded
   - `profile` → `vertical-pulse`

**Accounts are the one thing worth asking for.** Everything else has a defensible
default; a report about the wrong book of accounts is worthless.

**On a shared platform**, resolve config from the invoking user's own saved inputs
and CRM connection. Never inherit another user's accounts or credentials.

---

## 3. Default to the cheap mode

`/em-newsletter` defaults to `smart` verification. This shortcut is for quick
looks, so it defaults to **`light`** (one cross-check reviewer per claim), which
costs roughly a third as much.

State this when you start:

> Running FinTech at `light` verification (~1/3 the cost of a full run). Say
> "thorough" for the `smart` quorum.

Escalate to `smart` or `full` if the user asks for thoroughness, or if the report
is going to a client-facing conversation where a wrong claim is expensive.

Everything in `/em-newsletter` §11 (cost control) still applies: say the cost
shape, cap fix rounds at two, stop on any signal to stop.

---

## 4. Output

Identical to `/em-newsletter`: a paginated issue titled
**`Vertical Pulse - <Vertical>`**, with a cover, one page per account, then
Market and Competition.

---

## 5. What this skill never does

Inherits every prohibition in `/em-newsletter` §12. In particular: it never
invents a fact or a source URL, never infers a person's employer or title, never
renders a quarantined claim as verified, and never carries one user's accounts or
CRM data into another user's run.

One addition specific to this skill: **never silently substitute a different
vertical.** If the argument does not match the taxonomy, say so and research it
as given rather than snapping it to the nearest known name.
