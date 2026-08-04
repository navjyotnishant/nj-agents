# Verification: trust rules, reviewers, and modes

Phase 1.5 is the costliest layer and the one that makes the report trustworthy.

## Verdicts

| Verdict | Meaning | Usable in the report |
|---|---|---|
| `verified` | passed the reviewer quorum | yes |
| `trusted` | auto-trusted, reviewer-free | yes |
| `quarantined` | kept but flagged | **no** — excluded from stories |

**Flag, never drop.** A quarantined claim stays in the record with its reason, so
the reader can see what was rejected and why. It is never rendered as a story.

## The trust rule

Auto-trust a claim on any of these, cheapest check first. The principle: *a claim
already corroborated, or cited to a legitimate primary source, does not need
independent re-verification. Spend reviewer budget on the doubtful ones.*

### 1. Multi-source
Two or more **independent citing domains**. Already corroborated by definition.
(Two URLs on the same registrable domain count once.)

### 2. Primary / official
- The company's own domain, including the subdomains `ir.`, `investor.`,
  `investors.`, `newsroom.`, `news.`, `press.`, `media.`
- Any host under `.gov`, `.gov.uk`, `.gov.sg`, `.edu`, `.ac.uk`, `.int`, `.mil`

### 3. Reputable outlet

**Wires and major news** — reuters.com, apnews.com, bloomberg.com, ft.com,
wsj.com, nytimes.com, economist.com, cnbc.com, bbc.com, bbc.co.uk,
theguardian.com, forbes.com, businessinsider.com, axios.com, washingtonpost.com,
theglobeandmail.com, fortune.com, marketwatch.com, barrons.com

**Financial data and research** — finance.yahoo.com, yahoo.com, morningstar.com,
pitchbook.com, crunchbase.com, statista.com, tipranks.com, simplywall.st,
stockstory.org, seekingalpha.com, gartner.com, mckinsey.com, deloitte.com,
pwc.com, kpmg.com, ey.com, juniperresearch.com, cbinsights.com

**Industry trade press** — finextra.com, americanbanker.com, paymentsdive.com,
pymnts.com, techcrunch.com, theverge.com, wired.com, bankingdive.com,
fintechfutures.com, coindesk.com, theinformation.com, fintech.global,
fintechweekly.com, thisweekinfintech.com, paymentweek.com, ledgerinsights.com,
the-paypers.com, electronicpaymentsinternational.com

**Regulators, standards bodies, institutions** — sec.gov, federalreserve.gov,
occ.gov, fdic.gov, finra.org, europa.eu, ecb.europa.eu, bis.org, worldbank.org,
imf.org, mas.gov.sg, fca.org.uk, bankofengland.co.uk

Match on the **registrable domain**: `x.reuters.com` counts, `reuters.com.evil.co`
does not.

The trade-press list above is FinTech-weighted because that is the vertical it was
tuned on. For another vertical, apply the same standard — an established trade
publication with named editorial staff — rather than treating this list as
exhaustive.

## Reviewer quorum

Claims that are not auto-trusted get three reviewers, each with a distinct stance.
Each returns `support` / `unsure` / `reject` with a rationale.

| Role | Job |
|---|---|
| **corroborate** | find independent confirmation elsewhere |
| **cross-check** | read the cited source: does it actually say this? |
| **refute** | actively try to disprove the claim |

**Any `reject` quarantines the claim.** Record which reviewer rejected it and the
reason. Do not average the stances or take a majority: one reviewer finding the
source does not support the claim is decisive.

## Modes and cost

| Mode | Rule | Relative spend |
|---|---|---|
| `full` | 3-reviewer quorum on every claim | highest |
| `smart` (default) | auto-trust by the rule above; quorum on the rest | ~1x |
| `light` | 1 reviewer (cross-check) per claim | ~1/3 |
| `off` | no reviewers; every claim trusted as fetched | minimal |

**Measured baseline**: 45 claims at `smart` produced 133 model calls over 12.5
minutes, with 31 usable and 14 quarantined.

`light` is the right default when the user is iterating on layout rather than
content. Escalate to `smart` or `full` when the report feeds a client-facing
conversation, where a wrong claim is expensive.

**State the expected order of magnitude before running, and get a yes.**
