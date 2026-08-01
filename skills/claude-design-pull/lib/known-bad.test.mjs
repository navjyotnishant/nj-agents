// Author: navjyotnishant
// Created: 2026-08-01
// Description: Replays real failures this gate was built to catch.
//
// Each case is a state the code was actually in during the session that
// motivated this skill — and each was reported as "done" at the time. If any of
// these stops blocking, the gate has lost the ability to catch the mistakes it
// exists for, and the skill is decorative.
//
// Run:  node lib/known-bad.test.mjs

import { diffPage, verdict } from "./diff.mjs";
import { auditCoverage, derivePairs } from "./coverage.mjs";
import { renderHtml } from "./report.mjs";
import { conflictingRules } from "./pull.mjs";

const facts = (o = {}) => ({ pairs: {}, required: {}, sequences: {}, ...o });
const styled = (s) => ({ count: 1, style: s, texts: [] });

let pass = 0, fail = 0;
const check = (name, got, want) => {
  const ok = got === want;
  console.log(`  ${ok ? "✓" : "✗"} ${name}${ok ? "" : `  got ${got}, want ${want}`}`);
  ok ? pass++ : fail++;
};

// 1. The Workflows toolbar was rebuilt while the table kept its old columns.
//    Reported as complete; the user's screenshot exposed it immediately.
check("wrong columns must BLOCK",
  verdict([diffPage("workflows",
    facts({ sequences: { columns: ["Workflow", "Last 5 runs", "Last run", "Repo"] } }),
    facts({ sequences: { columns: ["Workflow", "Nodes", "Last run"] } }))]).verdict,
  "BLOCK");

// 2. Same page: the sparkline the design specified was never built.
check("a missing required element must BLOCK",
  verdict([diffPage("workflows", facts(), facts({ required: { ".sp-spark": 0 } }))]).verdict,
  "BLOCK");

// 3. `--radius: 1.25rem` made every control 18px instead of 6px. Survived
//    several passes of matching by eye; one computed-style dump found it.
check("an 18px radius against a 6px design must BLOCK",
  verdict([diffPage("skills",
    facts({ pairs: { input: styled({ borderRadius: "6px" }) } }),
    facts({ pairs: { input: styled({ borderRadius: "18px" }) } }))]).verdict,
  "BLOCK");

// 4. Skills field labels were 12px uppercase against a 10px sentence-case design.
check("wrong label size and casing must BLOCK",
  verdict([diffPage("skills",
    facts({ pairs: { label: styled({ fontSize: "10px", textTransform: "none" }) } }),
    facts({ pairs: { label: styled({ fontSize: "12px", textTransform: "uppercase" }) } }))]).verdict,
  "BLOCK");

// 5. The corrected state must PASS. A gate that always blocks teaches people to
//    ignore it, which is its own failure mode.
check("the fixed page must PASS",
  verdict([diffPage("workflows",
    facts({ sequences: { columns: ["Workflow", "Last 5 runs", "Last run", "Repo"] },
            pairs: { chip: styled({ borderRadius: "999px" }) } }),
    facts({ sequences: { columns: ["Workflow", "Last 5 runs", "Last run", "Repo"] },
            pairs: { chip: styled({ borderRadius: "999px" }) },
            required: { ".sp-spark": 1 } }))]).verdict,
  "PASS");

// 6. The design showed a failure reason the API cannot supply — it lives on
//    RunStep, not WorkflowRun. Must WARN so nobody fakes data to go green.
check("an API-side data gap must WARN, not BLOCK",
  verdict([diffPage("workflows", facts(), facts({ required: { ".failure-reason": 0 } }),
    { waivers: [{ selector: ".failure-reason",
                  reason: "WorkflowRun has no error field; it lives on RunStep",
                  tracked: "GH#14" }] })]).verdict,
  "WARN");

// 7. THE COVERAGE HOLE. The manifest was authored by hand-picking "the
//    important selectors", so buttons were never mapped — and the gate reported
//    a confident verdict three times running while the page's primary action was
//    an inline indigo pill against a near-black 6px design. A map that does not
//    cover the mockup must not be usable.
const BUTTONS = `<body><div class="frame">
  <div class="toolbar"><span class="chipf on">All</span></div>
  <button class="btn primary">+ New workflow</button><button class="mini">Edit</button>
</div></body>`;

check("a manifest that skips buttons must NOT report complete",
  auditCoverage(BUTTONS, { toolbar: ".sp-toolbar", chipf: ".sp-chip" }).complete,
  false);

check("and must name the button it skipped",
  auditCoverage(BUTTONS, { toolbar: ".sp-toolbar", chipf: ".sp-chip" })
    .missing.some((m) => m.cls === "btn"),
  true);

// 8. Status variants are separate designs. Mapping only `.st` samples whichever
//    is first in the document and reports the rest as matching.
check("each status variant becomes its own pair",
  derivePairs('<span class="st ok">a</span><span class="st bad">b</span>',
    { st: ".sp-st", "st.ok": ".sp-st-ok", "st.bad": ".sp-st-bad", ok: false, bad: false })
    .filter((p) => p.key.startsWith("st.")).length,
  2);

// 9. An element with no live counterpart must still be compared — the absence
//    IS the finding. Skipping it is how an unbuilt page reads as passing.
check("a null mapping still produces a pair",
  derivePairs('<div class="lk">chain</div>', { lk: null }).length,
  1);

// 10. The HTML report must never print a score. "9 of 12 matching" is the
//     framing that let a wrong page read as progress.
check("the HTML report prints no score",
  /\b\d+\s*\/\s*\d+\b/.test(renderHtml(
    [{ page: "p", findings: [{ kind: "style", severity: "block", selector: "th", message: "fontSize 10px → want 9px" }] }],
    { verdict: "BLOCK", exitCode: 1, blocking: 1, dataGaps: 0, pages: 1 })),
  false);

// 11. The HTML must be self-contained: a report that pulls a CDN stylesheet
//     renders unstyled in CI, offline, and inside a PR attachment.
check("the HTML report loads nothing external",
  /<script|<link rel="stylesheet"|src="http/i.test(renderHtml(
    [{ page: "p", findings: [] }],
    { verdict: "PASS", exitCode: 0, blocking: 0, dataGaps: 0, pages: 1 })),
  false);

// 12. THE CONTRADICTION. The real mockups disagreed about `.btn` across four
//     pages. Porting one page's value into the shared stylesheet fixed two
//     pages and broke a third — which reads as a regression and is actually a
//     conflict in the design. It must be detectable BEFORE porting.
{
  const real = {
    workflows: ".btn{height:30px;padding:0 12px;font-size:11.5px}",
    skills:    ".btn{height:30px;padding:0 12px;font-size:11.5px}",
    users:     ".btn{height:28px;padding:0 11px;font-size:11px}",
    builder:   ".btn{height:29px;padding:0 11px;font-size:11px}",
  };
  const h = conflictingRules(real, [".btn"]).find((c) => c.property === "height");
  check("mockups disagreeing about a shared rule must be reported", Boolean(h), true);
  check("and the dominant value must lead so the choice is evidence-based",
    h?.variants[0].value, "30px");
}

// 13. A design that agrees with itself must stay silent, or the conflict report
//     becomes noise and gets ignored.
check("a rule identical across mockups is not a conflict",
  conflictingRules({ a: ".chip{border-radius:999px}", b: ".chip{border-radius:999px}" }, [".chip"]).length,
  0);

console.log(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
