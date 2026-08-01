// Author: navjyotnishant
// Created: 2026-08-01
// Last updated: 2026-08-01
// Description: Render the verdict — terminal output and the report artifact.
//
// The output is the delta and nothing else. No score, no percentage, no "9 of 12
// matching" — that framing is exactly what let a wrong page read as progress.
// Either it matches or here is precisely what differs.
//
// Run the self-check with:  node lib/report.mjs --self-check

const ICON = { BLOCK: "✗", WARN: "▲", PASS: "✓" };

/** Terminal output. Grouped by page, each finding on one line, widest column
 *  padded so the deltas line up and scan vertically. */
export function renderTerminal(results, agg, drift) {
  const lines = [];
  const head = `${ICON[agg.verdict]} ${agg.verdict}`;

  if (agg.verdict === "PASS") {
    lines.push(`${head} — ${agg.pages} page${agg.pages === 1 ? "" : "s"} match their design`);
  } else {
    const bits = [];
    if (agg.blocking) bits.push(`${agg.blocking} mismatch${agg.blocking === 1 ? "" : "es"}`);
    if (agg.dataGaps) bits.push(`${agg.dataGaps} data gap${agg.dataGaps === 1 ? "" : "s"}`);
    lines.push(`${head} — ${bits.join(", ")}`);
  }

  for (const r of results) {
    if (!r.findings.length) continue;
    lines.push("", `  ${r.page}`);
    const w = Math.max(...r.findings.map((f) => f.kind.length));
    for (const f of r.findings) {
      const tail = f.tracked ? ` (tracked ${f.tracked})` : "";
      lines.push(`    ${f.kind.padEnd(w)}  ${f.selector}  ${f.message}${tail}`);
    }
  }

  if (drift?.total) {
    lines.push("", `  ${drift.total} hardcoded colour literal${drift.total === 1 ? "" : "s"} in source` +
      (drift.delta ? ` (${drift.delta > 0 ? "+" : ""}${drift.delta} since last run)` : ""));
  }

  if (agg.verdict === "BLOCK") {
    lines.push("", "  Not matching. Fix the deltas above and re-run.");
  }
  return lines.join("\n");
}

/** Report artifact — CONVENTIONS §6. A record of what was compared and what came
 *  of it, written outside the repo tree. */
export function renderReport(results, agg, meta = {}) {
  const l = [];
  l.push(`# Design parity — ${agg.verdict}`, "");
  l.push(`- **When:** ${meta.timestamp ?? "(unset)"}`);
  l.push(`- **Repo:** ${meta.repo ?? "(unset)"} @ ${meta.branch ?? "(unset)"} (${meta.sha ?? "dirty"})`);
  l.push(`- **Design project:** ${meta.designProject ?? "(local mockups only)"}`);
  l.push(`- **Pages compared:** ${agg.pages}`);
  l.push(`- **Exit code:** ${agg.exitCode}`, "");

  if (meta.designChanges?.dirty) {
    l.push("## Design changed since the last pull", "");
    for (const k of ["added", "changed", "removed"]) {
      for (const p of meta.designChanges[k] ?? []) l.push(`- \`${p}\` — ${k}`);
    }
    l.push("", "The design moved. These deltas may reflect a design edit rather than a code regression.", "");
  }

  for (const r of results) {
    l.push(`## ${r.page}`, "");
    if (!r.findings.length) { l.push("Matches.", ""); continue; }
    l.push("| Class | Element | Delta |", "|---|---|---|");
    for (const f of r.findings) {
      const tail = f.tracked ? ` (tracked ${f.tracked})` : "";
      l.push(`| ${f.kind} | \`${f.selector}\` | ${f.message}${tail} |`);
    }
    l.push("");
  }

  if (agg.dataGaps) {
    l.push("## Data gaps", "",
      "The design shows fields the API cannot currently supply. These do not block —",
      "the honest fix is an API change, and blocking here would only invite faking data.", "");
  }
  return l.join("\n");
}

// console.assert PRINTS and CONTINUES — it does not throw, and it does not set
// the exit code. A self-check built on it reports every failure and still exits
// 0, so the documented "for f in ...; do node lib/$f.mjs --self-check; done"
// loop goes green over a broken gate. Count the failures and exit on them.
let _failed = 0;
const _assert = console.assert.bind(console);
console.assert = (cond, ...rest) => { if (!cond) _failed++; _assert(cond, ...rest); };
function _done(name) {
  if (_failed) {
    console.error(`
${name} self-check FAILED — ${_failed} assertion(s)`);
    process.exit(1);
  }
  console.log(`${name} self-check OK`);
}

// ── self-check ───────────────────────────────────────────────────────────────

function demo() {
  const results = [{
    page: "workflows",
    findings: [
      { kind: "structure", severity: "block", selector: "columns", message: "[a] → want [a, b]" },
      { kind: "style", severity: "block", selector: "th", message: "fontSize 10px → want 9px" },
      { kind: "data-gap", severity: "info", selector: ".reason", message: "no error field", tracked: "GH#14" },
    ],
  }];
  const agg = { verdict: "BLOCK", exitCode: 1, blocking: 2, dataGaps: 1, pages: 1 };

  const term = renderTerminal(results, agg, { total: 915, delta: 12 });
  console.assert(term.startsWith("✗ BLOCK"), "leads with the verdict");
  console.assert(term.includes("2 mismatches, 1 data gap"), "counts both classes");
  console.assert(term.includes("tracked GH#14"), "surfaces the tracking ref");
  console.assert(term.includes("+12 since last run"), "reports drift movement");
  console.assert(!/\d+\s*\/\s*\d+/.test(term), "never prints a score — that framing hid the problem");
  console.assert(term.includes("Not matching."), "says plainly it is not done");

  const pass = renderTerminal([], { verdict: "PASS", exitCode: 0, blocking: 0, dataGaps: 0, pages: 4 });
  console.assert(pass.includes("4 pages match"), "pluralises the pass line");
  console.assert(!pass.includes("Not matching"), "no scold on a pass");

  const one = renderTerminal([], { verdict: "PASS", exitCode: 0, blocking: 0, dataGaps: 0, pages: 1 });
  console.assert(one.includes("1 page match"), "singular reads correctly");

  const md = renderReport(results, agg, {
    timestamp: "2026-08-01T09:00:00Z", repo: "specter-agent", branch: "main", sha: "abc1234",
    designChanges: { dirty: true, changed: ["mockups/workflows.html"], added: [], removed: [] },
  });
  console.assert(md.includes("# Design parity — BLOCK"), "report titles with the verdict");
  console.assert(md.includes("Design changed since the last pull"), "flags a design-side edit");
  console.assert(md.includes("**Exit code:** 1"), "records the exit code");
  console.assert(md.includes("## Data gaps"), "explains why gaps do not block");

  _done("report");
}

// Guard on the FLAG, not the filename: matching only the path means importing
// this module from anywhere containing "report" runs the demo as a side effect.
if (process.argv[1]?.includes("report") && process.argv.includes("--self-check")) demo();
