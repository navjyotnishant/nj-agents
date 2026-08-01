// Author: navjyotnishant
// Created: 2026-08-01
// Last updated: 2026-08-01
// Description: Classify mockup-vs-live deltas and compute the verdict.
//
// This is the file that decides BLOCK, so it is the one that has to be right.
// Its whole job is refusing to call a page "matching" on evidence that does not
// support it — the failure this skill exists to prevent.
//
// Run the self-check with:  node lib/diff.mjs --self-check

/** Colours are compared after normalising to rgb(): the mockups write hex, the
 *  browser reports rgb(), and "#fff vs rgb(255,255,255)" is not a finding. */
function normColor(v) {
  if (typeof v !== "string") return v;
  const hex = v.trim().match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
  if (!hex) return v.replace(/\s+/g, "");
  const h = hex[1].length === 3 ? hex[1].split("").map((c) => c + c).join("") : hex[1];
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
  return `rgb(${r},${g},${b})`;
}

const norm = (v) => (typeof v === "string" ? normColor(v).replace(/\s+/g, " ").trim() : v);

/**
 * Compare one page's mockup facts against its live facts.
 *
 * Returns findings, each carrying its own severity. Nothing here aggregates —
 * `verdict()` does that, so the two decisions stay separately testable.
 */
export function diffPage(name, mock, live, page = {}) {
  const findings = [];
  const waived = new Set((page.waivers || []).map((w) => w.selector));
  const waiverFor = (sel) => (page.waivers || []).find((w) => w.selector === sel);

  // ── structure: required elements ──
  for (const [sel, count] of Object.entries(live.required || {})) {
    if (count > 0) continue;
    const w = waiverFor(sel);
    findings.push(w
      ? { kind: "data-gap", severity: "info", selector: sel,
          message: `${sel} absent — ${w.reason}`, tracked: w.tracked }
      : { kind: "structure", severity: "block", selector: sel,
          message: `required element ${sel} is missing` });
  }

  // ── structure: ordered text runs (columns, tabs) ──
  // The check that catches "restyled the chrome, left the table alone".
  for (const [key, want] of Object.entries(mock.sequences || {})) {
    const got = live.sequences?.[key] ?? [];
    if (JSON.stringify(want) === JSON.stringify(got)) continue;
    findings.push({
      kind: "structure", severity: "block", selector: key,
      message: `${key}: [${got.join(", ")}] → want [${want.join(", ")}]`,
    });
  }

  // ── structure + style: mapped pairs ──
  for (const [key, m] of Object.entries(mock.pairs || {})) {
    const l = live.pairs?.[key];

    if (!l || l.count === 0) {
      if (m.count === 0) continue;         // absent in both: the design does not use it here
      const w = waiverFor(key);
      findings.push(w
        ? { kind: "data-gap", severity: "info", selector: key,
            message: `${key} absent — ${w.reason}`, tracked: w.tracked }
        : { kind: "structure", severity: "block", selector: key,
            message: `${key} is missing (mockup has ${m.count})` });
      continue;
    }

    if (!m.style || !l.style) continue;
    for (const [prop, want] of Object.entries(m.style)) {
      const got = l.style[prop];
      if (norm(got) === norm(want)) continue;
      findings.push({
        kind: "style", severity: "block", selector: key,
        message: `${prop} ${got} → want ${want}`,
      });
    }
  }

  return { page: name, findings };
}

/**
 * Aggregate to one verdict.
 *
 * BLOCK is deliberately sticky: any blocking finding blocks, and there is no
 * score that lets a mostly-matching page read as done. A partial pass reported
 * as success is precisely how this went wrong before.
 */
export function verdict(results) {
  const all = results.flatMap((r) => r.findings);
  const blocking = all.filter((f) => f.severity === "block");
  const gaps = all.filter((f) => f.kind === "data-gap");

  return {
    verdict: blocking.length ? "BLOCK" : gaps.length ? "WARN" : "PASS",
    exitCode: blocking.length ? 1 : 0,   // CONVENTIONS §5: 0 for PASS/WARN, 1 for BLOCK
    blocking: blocking.length,
    dataGaps: gaps.length,
    pages: results.length,
  };
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
// Every case below is a real failure from the session that motivated this skill.

function demo() {
  const facts = (o = {}) => ({ pairs: {}, required: {}, sequences: {}, ...o });
  const styled = (s) => ({ count: 1, style: s, texts: [] });

  // 1. Identical pages pass.
  {
    const m = facts({ pairs: { btn: styled({ fontSize: "11px", borderRadius: "6px" }) } });
    const l = facts({ pairs: { btn: styled({ fontSize: "11px", borderRadius: "6px" }) } });
    const r = diffPage("p", m, l);
    console.assert(r.findings.length === 0, "identical pages produce no findings");
    console.assert(verdict([r]).verdict === "PASS", "and PASS");
  }

  // 2. THE RADIUS BUG. --radius: 1.25rem made every control 18px instead of 6px,
  //    and survived several passes of matching by eye.
  {
    const m = facts({ pairs: { btn: styled({ borderRadius: "6px" }) } });
    const l = facts({ pairs: { btn: styled({ borderRadius: "18px" }) } });
    const v = verdict([diffPage("p", m, l)]);
    console.assert(v.verdict === "BLOCK", "an 18px radius against a 6px design must BLOCK");
    console.assert(v.exitCode === 1, "and exit non-zero");
  }

  // 3. THE COLUMNS BUG. The toolbar was rebuilt while the table kept its columns.
  {
    const m = facts({ sequences: { columns: ["Workflow", "Last 5 runs", "Last run", "Repo"] } });
    const l = facts({ sequences: { columns: ["Workflow", "Nodes", "Last run"] } });
    const r = diffPage("workflows", m, l);
    console.assert(r.findings.some((f) => f.kind === "structure"), "wrong columns are structural");
    console.assert(verdict([r]).verdict === "BLOCK", "and must BLOCK");
  }

  // 4. THE MISSING-ELEMENT BUG. The sparkline the design specified was never built.
  {
    const l = facts({ required: { ".sp-spark": 0 } });
    const v = verdict([diffPage("workflows", facts(), l)]);
    console.assert(v.verdict === "BLOCK", "a missing required element must BLOCK");
  }

  // 5. Data gaps WARN, never BLOCK — so nobody fakes data to go green.
  {
    const page = { waivers: [{ selector: ".failure-reason", reason: "no error field on WorkflowRun", tracked: "GH#14" }] };
    const l = facts({ required: { ".failure-reason": 0 } });
    const r = diffPage("workflows", facts(), l, page);
    console.assert(r.findings[0].kind === "data-gap", "a waived absence is a data gap");
    const v = verdict([r]);
    console.assert(v.verdict === "WARN" && v.exitCode === 0, "data gaps warn and allow the pipeline");
  }

  // 6. Colour equality across notations — #fff and rgb(255,255,255) are the same.
  {
    const m = facts({ pairs: { b: styled({ color: "#fff" }) } });
    const l = facts({ pairs: { b: styled({ color: "rgb(255, 255, 255)" }) } });
    console.assert(diffPage("p", m, l).findings.length === 0, "hex and rgb must compare equal");
    const m3 = facts({ pairs: { b: styled({ color: "#ff6d5a" }) } });
    const l3 = facts({ pairs: { b: styled({ color: "rgb(255, 109, 90)" }) } });
    console.assert(diffPage("p", m3, l3).findings.length === 0, "6-digit hex too");
  }

  // 7. One bad page among good ones still blocks the run — no averaging.
  {
    const ok = diffPage("a", facts(), facts());
    const bad = diffPage("b", facts({ required: {} }), facts({ required: { ".x": 0 } }));
    const v = verdict([ok, ok, ok, bad]);
    console.assert(v.verdict === "BLOCK", "3 of 4 passing is still BLOCK");
    console.assert(v.blocking === 1 && v.pages === 4, "counts are reported honestly");
  }

  // 8. An element absent from BOTH is not a finding: the design does not use it here.
  {
    const m = facts({ pairs: { x: { count: 0, style: null, texts: [] } } });
    const l = facts({ pairs: { x: { count: 0, style: null, texts: [] } } });
    console.assert(diffPage("p", m, l).findings.length === 0, "absent in both is fine");
  }

  _done("diff");
}

// Guard on the FLAG, not the filename: matching only the path means importing
// this module from anywhere containing "diff" runs the demo as a side effect.
if (process.argv[1]?.includes("diff") && process.argv.includes("--self-check")) demo();
