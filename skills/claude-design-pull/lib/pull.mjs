// Author: navjyotnishant
// Created: 2026-08-01
// Last updated: 2026-08-01
// Description: Reconcile pulled Claude Design mockups against the committed copies.
//
// The mockups live in the repo so the gate runs offline and in CI, and so a
// design edit is a visible event rather than a silent redefinition of what
// "matching" means. This module decides what changed and never writes without
// being told to — the skill reports design-side drift before adopting it.
//
// Run the self-check with:  node lib/pull.mjs --self-check

import { createHash } from "node:crypto";

export const sha = (text) => createHash("sha256").update(text ?? "").digest("hex").slice(0, 12);

/**
 * Compare freshly-pulled mockups with what is committed.
 *
 * `changed` is the interesting case: the design moved under a page that may
 * already have been signed off. The skill reports those before overwriting, so
 * "the gate started failing" is traceable to a design edit rather than a mystery.
 */
export function reconcile(remote, local) {
  const added = [], changed = [], removed = [], unchanged = [];

  for (const [path, text] of Object.entries(remote)) {
    if (!(path in local)) { added.push(path); continue; }
    (sha(text) === sha(local[path]) ? unchanged : changed).push(path);
  }
  for (const path of Object.keys(local)) {
    if (!(path in remote)) removed.push(path);
  }

  return {
    added: added.sort(), changed: changed.sort(),
    removed: removed.sort(), unchanged: unchanged.sort(),
    dirty: added.length + changed.length + removed.length > 0,
  };
}

/** Strip the annotation block mockups carry — the "what changed" prose is
 *  commentary for a human, not part of the design being matched. */
export function stripAnnotations(html) {
  return html.replace(/<div class="note">[\s\S]*?<\/div>\s*(?=<\/body>)/i, "");
}

/**
 * Extract the <style> block, so a page's CSS can be adopted verbatim.
 *
 * Retyping these by hand is what caused the drift this skill exists to catch:
 * every hand-transcription lost a pixel or two per element, and the accumulation
 * is what read as "still different".
 */
export function extractStyle(html) {
  const m = html.match(/<style>([\s\S]*?)<\/style>/i);
  return m ? m[1].trim() : "";
}

/**
 * Find CSS rules that the mockups define INCONSISTENTLY across files.
 *
 * Mockups are usually authored one page at a time, so the "same" component
 * drifts between them: on the project this was written for, `.btn` was 30px on
 * two pages, 29px on a third and 28px on a fourth, with the padding and
 * font-size varying too.
 *
 * This matters because it makes "match the design exactly" unsatisfiable. Port
 * one page's value into a shared stylesheet and the other pages start failing —
 * that is not a regression to chase, it is a contradiction in the source. Run
 * this BEFORE porting any shared rule, and pick deliberately rather than
 * discovering the conflict through a rising finding count.
 *
 * `sources` maps a page name to its mockup HTML.
 */
export function conflictingRules(sources, selectors) {
  const conflicts = [];

  for (const sel of selectors) {
    // Match the rule for exactly this selector: `.btn{...}` but never
    // `.btn.primary{...}` or `.sp-btn{...}`.
    const re = new RegExp(`(?:^|[},])\\s*${sel.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*\\{([^}]*)\\}`, "m");
    const byPage = {};

    for (const [page, html] of Object.entries(sources)) {
      const m = html.match(re);
      if (!m) continue;
      const decls = {};
      for (const d of m[1].split(";")) {
        const [k, ...v] = d.split(":");
        if (k?.trim() && v.length) decls[k.trim()] = v.join(":").trim();
      }
      byPage[page] = decls;
    }

    const pages = Object.keys(byPage);
    if (pages.length < 2) continue;

    // Every property named anywhere, so a declaration present on one page and
    // absent on another counts as a difference rather than passing silently.
    const props = new Set(pages.flatMap((p) => Object.keys(byPage[p])));
    for (const prop of props) {
      const values = new Map();
      for (const p of pages) {
        const v = byPage[p][prop] ?? "(unset)";
        if (!values.has(v)) values.set(v, []);
        values.get(v).push(p);
      }
      if (values.size > 1) {
        conflicts.push({
          selector: sel,
          property: prop,
          variants: [...values.entries()]
            .map(([value, pages]) => ({ value, pages }))
            .sort((a, b) => b.pages.length - a.pages.length),
        });
      }
    }
  }

  return conflicts;
}

/** Which manifest pages have no mockup file — a manifest that references a
 *  design nobody pulled would otherwise silently check nothing. */
export function missingMockups(manifest, available) {
  const have = new Set(available);
  return Object.entries(manifest.pages || {})
    .filter(([, p]) => p.mockup && !have.has(p.mockup))
    .map(([name, p]) => ({ page: name, mockup: p.mockup }));
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
  // Nothing pulled yet: everything is an addition.
  {
    const r = reconcile({ "a.html": "x" }, {});
    console.assert(r.added.length === 1 && r.dirty, "a first pull is all additions");
  }

  // Identical content is not a change, whitespace and all.
  {
    const r = reconcile({ "a.html": "same" }, { "a.html": "same" });
    console.assert(r.unchanged.length === 1 && !r.dirty, "identical content is clean");
  }

  // THE CASE THAT MATTERS: the design moved. Must surface, not silently adopt.
  {
    const r = reconcile({ "a.html": "v2" }, { "a.html": "v1" });
    console.assert(r.changed.includes("a.html"), "a design edit is reported as changed");
    console.assert(r.dirty, "and marks the pull dirty");
  }

  // A page deleted from the design project.
  {
    const r = reconcile({}, { "gone.html": "x" });
    console.assert(r.removed.includes("gone.html"), "deletions are reported");
  }

  // Annotations are commentary, not design.
  {
    const html = '<body><div class="frame">real</div><div class="note"><b>What changed.</b></div></body>';
    const out = stripAnnotations(html);
    console.assert(!out.includes("What changed"), "annotation block is stripped");
    console.assert(out.includes("real"), "the design itself survives");
  }

  // Style extraction — the path that avoids retyping.
  {
    const css = extractStyle("<head><style>  .a{color:red}  </style></head>");
    console.assert(css === ".a{color:red}", `extracts and trims, got ${JSON.stringify(css)}`);
    console.assert(extractStyle("<p>no style</p>") === "", "absent style yields empty");
  }

  // A manifest pointing at a mockup nobody pulled must not pass silently.
  {
    const man = { pages: { a: { mockup: "mockups/a.html" }, b: { mockup: "mockups/b.html" } } };
    const missing = missingMockups(man, ["mockups/a.html"]);
    console.assert(missing.length === 1 && missing[0].page === "b", "missing mockups are named");
  }

  // THE CONTRADICTION. Mockups authored page-by-page disagree about the same
  // component, which makes "match the design exactly" unsatisfiable until
  // someone chooses. Porting one page's value silently breaks the others.
  {
    const sources = {
      workflows: ".btn{height:30px;padding:0 12px;font-size:11.5px}",
      skills:    ".btn{height:30px;padding:0 12px;font-size:11.5px}",
      users:     ".btn{height:28px;padding:0 11px;font-size:11px}",
      builder:   ".btn{height:29px;padding:0 11px;font-size:11px}",
    };
    const c = conflictingRules(sources, [".btn"]);
    const h = c.find((x) => x.property === "height");
    console.assert(h, "a height disagreement is reported");
    console.assert(h.variants.length === 3, `three distinct heights, got ${h?.variants.length}`);
    // The most common value leads, so the choice can be made on evidence.
    console.assert(h.variants[0].value === "30px", "the dominant value sorts first");
    console.assert(h.variants[0].pages.length === 2, "and carries the pages that agree on it");
  }

  // Agreement is not a conflict — a rule identical everywhere must stay quiet,
  // or the report becomes noise nobody reads.
  {
    const same = { a: ".chip{border-radius:999px}", b: ".chip{border-radius:999px}" };
    console.assert(conflictingRules(same, [".chip"]).length === 0, "identical rules are not conflicts");
  }

  // A property present on one page and missing on another IS a difference:
  // the element renders differently, which is the whole question.
  {
    const partial = { a: ".x{color:red;font-weight:700}", b: ".x{color:red}" };
    const c = conflictingRules(partial, [".x"]);
    console.assert(c.length === 1 && c[0].property === "font-weight", "an absent declaration counts");
  }

  // Selector matching must be exact: `.btn` must never pick up `.btn.primary`
  // or `.sp-btn`, or every compound variant reads as a conflict.
  {
    const s = { a: ".btn{height:30px}.btn.primary{height:40px}", b: ".btn{height:30px}" };
    console.assert(conflictingRules(s, [".btn"]).length === 0, "compound rules are not confused for the base");
  }

  _done("pull");
}

// Guard on the FLAG, not the filename: matching only the path means importing
// this module from anywhere containing "pull" runs the demo as a side effect.
if (process.argv[1]?.includes("pull") && process.argv.includes("--self-check")) demo();
