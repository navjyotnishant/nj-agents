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

console.log(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
