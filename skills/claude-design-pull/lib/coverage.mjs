// Author: navjyotnishant
// Created: 2026-08-01
// Last updated: 2026-08-01
// Description: Enforce that the manifest maps every class in a mockup, and derive the pairs from it.
//
// This module exists because of a specific, repeated failure: the manifest was
// authored by hand-picking "the important selectors", and the gate then reported
// a confident verdict about only those. Buttons went unmeasured across three
// rounds on a page whose most-clicked element is a button — the primary action
// was an inline-styled indigo pill against a design calling for a near-black 6px
// button, and the gate said nothing, because nothing had asked it to look.
//
// A partial manifest is worse than no manifest: it produces a number that reads
// like coverage. "34 findings" meant "34 findings among the eight things someone
// chose to look at", which is the same error as the "12/12 matching" this skill
// was built to prevent, one level up.
//
// So coverage is not a suggestion here. `auditCoverage()` BLOCKS on any class
// present in the mockup and absent from the map, and `derivePairs()` generates
// the pairs mechanically so the set cannot quietly diverge from the design.
//
// Run the self-check with:  node lib/coverage.mjs --self-check

/** Structural wrappers excluded from comparison.
 *
 *  A mockup renders as a standalone centred card; the live page renders inside
 *  an app shell. Comparing those measures the harness rather than the design.
 *  Deliberately tiny — every addition here is a thing the gate stops seeing. */
export const CHROME = new Set(["frame", "note", "wrap"]);

/** Strip the annotation block. The "what changed" prose is commentary for a
 *  human, not part of the design under comparison. */
export function designMarkup(html) {
  return html.replace(/<div class="note">[\s\S]*?<\/div>\s*(?=<\/body>)/i, "");
}

/**
 * Every class token in a mockup's markup, with occurrence counts.
 *
 * Counts matter for triage: `mini×11` is the row action button repeated down a
 * table, and an unmapped class with a high count is a large hole.
 */
export function classesOf(html) {
  const counts = new Map();
  for (const m of designMarkup(html).matchAll(/class="([^"]+)"/g))
    for (const c of m[1].split(/\s+/))
      if (c && !CHROME.has(c)) counts.set(c, (counts.get(c) || 0) + 1);
  return counts;
}

/**
 * Compound classes — `st ok`, `btn primary`, `badge adm`.
 *
 * These are distinct designs, not variants of one thing: the design gives
 * `.st.ok` a green pair and `.st.bad` a red one. Sampling only `.st` reads
 * whichever happens to be first in the document and silently reports the other
 * three as matching.
 */
export function compoundsOf(html) {
  const seen = new Set();
  for (const m of designMarkup(html).matchAll(/class="([^"]+)"/g)) {
    const parts = m[1].split(/\s+/).filter(Boolean).filter((c) => !CHROME.has(c));
    if (parts.length > 1) seen.add(parts.join("."));
  }
  return [...seen];
}

/**
 * Audit one page's class map against its mockup.
 *
 * Returns every class the mockup uses and the map does not resolve. A non-empty
 * result is a BLOCK: the manifest cannot describe coverage it does not have.
 */
export function auditCoverage(html, classMap = {}) {
  const counts = classesOf(html);
  const compounds = compoundsOf(html);

  const missing = [];
  for (const [cls, n] of counts) if (!(cls in classMap)) missing.push({ cls, count: n });
  for (const c of compounds) if (!(c in classMap)) missing.push({ cls: c, count: 1, compound: true });

  missing.sort((a, b) => b.count - a.count);
  const total = counts.size + compounds.length;
  return {
    total,
    mapped: total - missing.length,
    missing,
    // A classless mockup — generated decks and canvas exports are often fully
    // inline-styled — yields total === 0, and `missing.length === 0` is then
    // vacuously true. Reporting complete:true there would claim full coverage of
    // a document the class path cannot address at all: the exact "confident
    // verdict over nothing" this module exists to prevent. Callers must branch on
    // `classless` and anchor on structure instead (repeating element + a stable
    // attribute) — see SKILL.md Step 2.4.
    classless: total === 0,
    complete: total > 0 && missing.length === 0,
  };
}

/**
 * Generate the comparison pairs from the mockup plus the class map.
 *
 * `null` in the map means the app has no counterpart yet — that still produces
 * a pair, because a missing element IS the finding. `false` means deliberately
 * not compared, and is the only way to exclude something; it has to be written
 * down, which is what makes an omission reviewable instead of invisible.
 */
export function derivePairs(html, classMap = {}, { scope = "" } = {}) {
  const pairs = [];

  for (const [cls] of [...classesOf(html).entries()].sort((a, b) => b[1] - a[1])) {
    const live = classMap[cls];
    if (live === undefined || live === false) continue;
    pairs.push({ key: cls, mock: scope + "." + cls, live: live ?? `.sp-${cls}--absent` });
  }

  for (const combo of compoundsOf(html)) {
    const live = classMap[combo];
    if (live === undefined || live === false) continue;
    pairs.push({ key: combo, mock: scope + "." + combo, live });
  }

  return pairs;
}

/** Two stacked `.frame` sections is a real mockup pattern (a page split into
 *  two proposed screens). An unscoped selector collects from both, so a `th`
 *  sequence mixes two unrelated tables and reports a false mismatch. */
export function frameScope(html) {
  return (html.match(/class="frame"/g) || []).length > 1 ? ".frame:first-of-type " : "";
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
    console.error(`\n${name} self-check FAILED — ${_failed} assertion(s)`);
    process.exit(1);
  }
  console.log(`${name} self-check OK`);
}

// ── self-check ───────────────────────────────────────────────────────────────

function demo() {
  // A miniature of the real workflows mockup, including the button that went
  // unmeasured for three rounds.
  const html = `<body>
    <div class="frame">
      <div class="toolbar"><span class="chipf on">All</span><span class="chipf">Failing</span></div>
      <button class="btn primary">+ New workflow</button>
      <button class="mini">Edit</button><button class="mini dark">Run</button>
      <span class="st ok">passed</span><span class="st bad">failed</span>
    </div>
    <div class="note"><b>What changed.</b> Commentary that is not design.</div>
  </body>`;

  // 1. Annotations are commentary, never compared.
  console.assert(!designMarkup(html).includes("What changed"), "annotation block is stripped");

  // 2. THE BUTTON HOLE. A map covering only the toolbar must be reported as
  //    incomplete — this is the exact state that shipped a wrong button.
  {
    const partial = { toolbar: ".sp-toolbar", chipf: ".sp-chip" };
    const a = auditCoverage(html, partial);
    console.assert(!a.complete, "a partial map must NOT report complete");
    const names = a.missing.map((m) => m.cls);
    console.assert(names.includes("btn"), "the unmapped button must be named");
    console.assert(names.includes("mini"), "so must the row action button");
    console.assert(names.includes("btn.primary"), "and the compound variant");
  }

  // 3. Occurrence counts drive triage — the biggest hole first.
  {
    const a = auditCoverage(html, {});
    console.assert(a.missing[0].count >= a.missing[a.missing.length - 1].count,
      "missing classes are ordered by how often they appear");
  }

  // 4. A complete map passes. A gate that can never go green teaches people to
  //    ignore it, which is its own failure mode.
  {
    const full = {
      toolbar: ".sp-toolbar", chipf: ".sp-chip", btn: ".sp-btn", mini: ".sp-btn-sm",
      st: ".sp-st", on: false, primary: false, dark: false, ok: false, bad: false,
      "chipf.on": ".sp-chip-on", "btn.primary": ".sp-btn-primary",
      "mini.dark": ".sp-btn-sm.sp-btn-primary", "st.ok": ".sp-st-ok", "st.bad": ".sp-st-bad",
    };
    const a = auditCoverage(html, full);
    console.assert(a.complete, `a full map reports complete, missing: ${a.missing.map(m=>m.cls)}`);
    console.assert(a.mapped === a.total, "mapped equals total when complete");
  }

  // 5. Compounds become their own pairs: .st.ok and .st.bad are different
  //    designs, and one sample of .st cannot speak for both.
  {
    const map = { st: ".sp-st", "st.ok": ".sp-st-ok", "st.bad": ".sp-st-bad" };
    const pairs = derivePairs(html, map);
    const keys = pairs.map((p) => p.key);
    console.assert(keys.includes("st.ok") && keys.includes("st.bad"),
      "each status variant gets its own pair");
    console.assert(pairs.find((p) => p.key === "st.ok").mock === ".st.ok",
      "compound selector is built correctly");
  }

  // 6. null means "no counterpart yet" and MUST still produce a pair — the
  //    missing element is the finding, not a reason to skip the check.
  {
    const pairs = derivePairs(html, { btn: null });
    console.assert(pairs.length === 1, "a null mapping still yields a pair");
    console.assert(pairs[0].live.includes("--absent"), "and points at a selector that cannot match");
  }

  // 7. false is the ONLY way to exclude, and it has to be written down.
  {
    console.assert(derivePairs(html, { btn: false }).length === 0, "false excludes");
    console.assert(derivePairs(html, {}).length === 0, "unmapped yields no pair (audit catches it)");
  }

  // 8. Two frames scope the selectors; one frame does not.
  {
    console.assert(frameScope(html) === "", "a single frame needs no scope");
    const two = `<div class="frame">a</div><div class="frame">b</div>`;
    console.assert(frameScope(two) === ".frame:first-of-type ", "two frames scope to the first");
  }

  _done("coverage");
}

// Guard on the FLAG, not the filename: matching only the path means importing
// this module from anywhere containing "coverage" runs the demo as a side effect.
if (process.argv[1]?.includes("coverage") && process.argv.includes("--self-check")) demo();
