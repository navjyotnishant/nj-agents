// Author: navjyotnishant
// Created: 2026-08-01
// Last updated: 2026-08-01
// Description: Render a mockup and its live page, extract comparable facts from both.
//
// Everything here is deliberately mechanical. The whole reason this skill exists
// is that "it looks right" was wrong four times in a row on the same project —
// the pages read as matching while columns were missing and every rounded control
// was 18px instead of 6px. So nothing in this file forms an opinion: it reports
// what the browser computed, and diff.mjs decides.
//
// Run the self-check with:  node lib/measure.mjs --self-check

/** Properties compared on every mapped element pair.
 *
 *  Kept deliberately short. Each one has caught a real regression on this
 *  project; anything broader (margins, line-height, letter-spacing) produced
 *  noise from real-vs-mock content differences without catching anything new. */
export const COMPARED_PROPS = [
  "fontSize",
  "fontWeight",
  "padding",
  "borderRadius",
  "borderWidth",
  "color",
  "backgroundColor",
  "textTransform",
];

/** Browser-side extractor. Serialized into the page, so it must be standalone —
 *  no imports, no closure over anything in this module. */
export function extractorSource() {
  return `(spec) => {
    const cs = (el) => getComputedStyle(el);
    const PROPS = ${JSON.stringify(COMPARED_PROPS)};

    const styleOf = (el) => {
      const c = cs(el);
      const out = {};
      for (const p of PROPS) out[p] = c[p];
      return out;
    };

    const textOf = (el) => (el.textContent || "").replace(/\\s+/g, " ").trim();

    const facts = { pairs: {}, required: {}, sequences: {} };

    for (const pair of spec.pairs || []) {
      const sel = spec.side === "mock" ? pair.mock : pair.live;
      const nodes = [...document.querySelectorAll(sel)];
      facts.pairs[pair.key] = {
        selector: sel,
        count: nodes.length,
        // Style is read from the first match only: these are class-driven
        // designs, so element two differing from element one is a page bug
        // rather than something the design specifies.
        style: nodes[0] ? styleOf(nodes[0]) : null,
        texts: nodes.slice(0, 12).map(textOf),
      };
    }

    for (const sel of spec.require || []) {
      facts.required[sel] = document.querySelectorAll(sel).length;
    }

    // Ordered text runs — column headers, tab labels. This is the check that
    // catches "the toolbar was restyled but the table kept its old columns".
    for (const seq of spec.sequences || []) {
      facts.sequences[seq.key] = [...document.querySelectorAll(
        spec.side === "mock" ? seq.mock : seq.live
      )].map(textOf).filter(Boolean);
    }

    return facts;
  }`;
}

/** Normalise a mockup selector spec into the shape the extractor wants. */
export function buildSpec(page, side) {
  return {
    side,
    pairs: (page.pairs || []).map((p, i) => ({
      key: p.key || p.live || p.mock || `pair-${i}`,
      mock: p.mock,
      live: p.live,
    })),
    require: side === "live" ? page.require || [] : [],
    sequences: (page.sequences || []).map((s, i) => ({
      key: s.key || `seq-${i}`,
      mock: s.mock,
      live: s.live,
    })),
  };
}

/**
 * Count raw colour literals in the page's source files.
 *
 * Not a gate — a drift meter. Every hardcoded hex is a place the design can
 * diverge without anyone noticing; on the project that motivated this skill
 * there were 915 of them against 142 token classes. Reported so the number can
 * be watched, and so a sudden jump is visible in review.
 */
export function countColorLiterals(sources) {
  const hex = /#[0-9a-fA-F]{3,8}\b/g;
  let total = 0;
  const perFile = {};
  for (const [file, text] of Object.entries(sources)) {
    const n = (text.match(hex) || []).length;
    if (n) { perFile[file] = n; total += n; }
  }
  return { total, perFile };
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
  const page = {
    pairs: [
      { mock: ".toolbar", live: ".sp-toolbar" },
      { key: "chip", mock: ".chipf", live: ".sp-chip" },
    ],
    require: [".sp-spark"],
    sequences: [{ key: "columns", mock: "th", live: "th" }],
  };

  const mockSpec = buildSpec(page, "mock");
  const liveSpec = buildSpec(page, "live");

  console.assert(mockSpec.pairs[0].key === ".sp-toolbar", "key falls back to the live selector");
  console.assert(mockSpec.pairs[1].key === "chip", "an explicit key wins");
  console.assert(mockSpec.require.length === 0, "require is a live-side check only");
  console.assert(liveSpec.require.length === 1, "require applies to the live side");
  console.assert(liveSpec.sequences[0].live === "th", "sequences carry both selectors");

  // The extractor must be self-contained: it is stringified into the page, so a
  // reference to anything in module scope would throw at evaluation time.
  const src = extractorSource();
  console.assert(src.includes("getComputedStyle"), "extractor reads computed styles");
  console.assert(!/\bCOMPARED_PROPS\b(?!\s*=)/.test(src.replace(JSON.stringify(COMPARED_PROPS), "")),
    "extractor must inline the prop list, not close over it");
  console.assert(src.includes(JSON.stringify(COMPARED_PROPS)), "prop list is inlined");

  const drift = countColorLiterals({
    "a.tsx": 'color: "#ff6d5a"; background: "#fff"; border: "#dfe3e8"',
    "b.tsx": "no colours here",
  });
  console.assert(drift.total === 3, `counts hex literals, got ${drift.total}`);
  console.assert(!("b.tsx" in drift.perFile), "clean files are omitted");

  _done("measure");
}

// Guard on the FLAG, not the filename: matching only the path means importing
// this module from anywhere containing "measure" runs the demo as a side effect.
if (process.argv[1]?.includes("measure") && process.argv.includes("--self-check")) demo();
