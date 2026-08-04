# Vertical Pulse

`vertical-pulse <Vertical>` — for example `vertical-pulse FinTech`.

The fast path into the EM weekly briefing. Same pipeline and same output as the
**EM Newsletter** skill, with the setup interview collapsed into a single argument.

**Use this** when the user knows their vertical and wants the report.
**Use EM Newsletter** for first-time setup, an account deep-dive, or when the
profile and accounts still need deciding.

---

## Method

**This skill's method is the EM Newsletter skill.** Follow its instructions in
full: the research phases, the people-moves gate, the trust rule, the reviewer
quorum, the synthesis model, the dedup rules, the imagery bounds and quality
filters, the render structure, and the QA gate.

The attached references are the same four files, and they carry the whole method:

| File | Read it when |
|---|---|
| `reference-taxonomy.md` | resolving the vertical argument |
| `schema.md` | emitting claims or the report model |
| `reference-trust.md` | verifying claims |
| `reference-render.md` | rendering and QA |

What follows is **only what differs** from EM Newsletter.

---

## 1. Resolve the vertical and the accounts

The user supplies these in whatever order suits them. Both of these are the same
request:

```
Generate a vertical pulse for the last 7 days. Our clients are Remitly, GFM, Built.
vertical-pulse FinTech
```

### The accounts

Take every company the user names as an account. A list in the prompt is the whole
book for this run: do not add accounts from a previous run, and do not drop one
because you found no news for it. **An account with no verified news still gets its
page**, carrying the gap and a discovery-framed call (see the EM Newsletter
instructions, §5).

If the user names no accounts, check saved config, then the last run, then ask.
Accounts are the one thing worth asking for; a report about the wrong book is
worthless.

### The vertical

Resolve in this order:

1. **Named outright** — "vertical pulse FinTech". Match it case-insensitively
   against `reference-taxonomy.md`.
2. **Inferred from the accounts** — when the user lists companies but no vertical,
   identify what they have in common and match that to the taxonomy. Remitly, GFM
   and Built are all FinTech, so the vertical is FinTech.
3. **Ask** — when the accounts span two verticals, or none of them is recognisable,
   list the taxonomy verticals and ask. Do not guess.

**When you infer, say so and let it be corrected**: "Reading these as FinTech.
Say otherwise if that is wrong." An inferred vertical sets the whole market pulse,
so a silent wrong guess wastes the run.

**One vertical per run.** A report covers a single vertical and the accounts within
it; researching two at once produces a market pulse that belongs to neither. If the
accounts genuinely span verticals, say which ones you see and offer one run each.

**Never silently substitute a different vertical.** If a named vertical is not in
the taxonomy, say so and research it as given rather than snapping it to the
nearest known name.

### The window

Default to the **last 7 days**, which is what "this week" and "for last 7 days"
both mean. Honour a different window if the user gives one ("the last fortnight",
"since the earnings call"), and state the window in the report so the reader knows
what was swept.

---

## 2. Resolve the rest without an interview

Everything the user stated in the prompt wins. Fill what is left in this order,
stopping at the first that answers:

1. **The prompt itself** — accounts, vertical, window, or anything else they named
2. **Saved config** — a config file, saved profile, or the platform's stored inputs
   for this user
3. **The last run for this vertical** — reuse its technologies and competitors
4. **Ask** — but only for accounts, and only when the first three came up empty.
   Derive the rest:

| Input | Default |
|---|---|
| `technologies` | `GenAI`, `Agentic AI`, `Cloud Infrastructure` |
| `competitors` | empty — research the category generically rather than a named roster |
| `people_intelligence` | `false` — the gate stays closed unless asked |
| `week_of` | the literal run date, never rounded |
| `profile` | `vertical-pulse` |

**Accounts are the one thing worth asking for.** Everything else has a defensible
default; a report about the wrong book of accounts is worthless.

**On a shared platform**, resolve config from the invoking user's own saved inputs
and CRM connection. Never inherit another user's accounts or credentials.

---

## 3. Default to the cheap mode

EM Newsletter defaults to `smart` verification. This shortcut is for quick looks,
so it defaults to **`light`** (one cross-check reviewer per claim), roughly a third
the cost.

State it when you start:

> Running FinTech at `light` verification (about a third the cost of a full run).
> Say "thorough" for the `smart` quorum.

Escalate to `smart` or `full` if the user asks for thoroughness, or if the report
feeds a client-facing conversation where a wrong claim is expensive.

All cost-control rules from EM Newsletter still apply: say the cost shape, cap fix
rounds at two, stop on any signal to stop.

---

## 4. Output

Identical to EM Newsletter: a paginated issue titled
**`Vertical Pulse - <Vertical>`**, with a cover, one page per account, then Market
and Competition.

---

## 5. Never

Inherits every prohibition from EM Newsletter. In particular: never invent a fact
or a source URL, never infer a person's employer or title, never render a
quarantined claim as verified, never carry one user's accounts or CRM data into
another user's run, never write credentials into the output.
