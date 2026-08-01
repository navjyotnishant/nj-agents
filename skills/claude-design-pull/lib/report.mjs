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

// ── HTML report ──────────────────────────────────────────────────────────────

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

/** "fontSize 16px → want 13px" → the three parts, so the delta can be shown as
 *  a before/after pair rather than a sentence to parse by eye. */
function splitStyle(msg) {
  const m = msg.match(/^(\w+) (.*?) → want (.*)$/);
  return m ? { prop: m[1], got: m[2], want: m[3] } : null;
}

const IS_COLOR = (p) => p === "color" || p === "backgroundColor";

/** Render a value with its own appearance where that IS the finding: a colour
 *  as a swatch, a radius as an actual corner. "6px vs 999px" argued in prose is
 *  the thing that kept getting waved through. */
function valueCell(prop, v, side) {
  const bits = [`<code class="v ${side}">${esc(v)}</code>`];
  if (IS_COLOR(prop)) bits.unshift(`<span class="sw" style="background:${esc(v)}"></span>`);
  if (prop === "borderRadius") bits.unshift(`<span class="rad" style="border-radius:${esc(v)}"></span>`);
  return bits.join("");
}

/**
 * A standalone, theme-aware HTML report.
 *
 * Same content as the Markdown, but 200 findings across five pages is a
 * scanning task, and a flat Markdown table is not scannable. Structural
 * findings sort above style findings because a missing element outranks a wrong
 * pixel, and each page gets a jump tile.
 *
 * Self-contained by construction: no external CSS, fonts, or scripts, so it
 * opens from disk and survives being attached to a PR.
 */
export function renderHtml(results, agg, meta = {}) {
  const counts = results.map((r) => ({
    page: r.page,
    structure: r.findings.filter((f) => f.kind === "structure").length,
    style: r.findings.filter((f) => f.kind === "style").length,
    gap: r.findings.filter((f) => f.kind === "data-gap").length,
  }));
  const total = results.reduce((n, r) => n + r.findings.length, 0);

  const tiles = counts.map((c) => `
  <a class="tile v-${agg.verdict.toLowerCase()}" href="#${esc(c.page)}">
    <span class="tile-n">${esc(c.page)}</span>
    <span class="tile-c"><b>${c.structure}</b> structure · <b>${c.style}</b> style${c.gap ? ` · <b>${c.gap}</b> gap` : ""}</span>
  </a>`).join("");

  const sections = results.map((r) => {
    const order = { structure: 0, "data-gap": 1, style: 2 };
    const rows = [...r.findings]
      .sort((a, b) => (order[a.kind] ?? 3) - (order[b.kind] ?? 3))
      .map((f) => {
        const tag = `<span class="tag tag-${f.kind === "structure" ? "s" : f.kind === "data-gap" ? "g" : "y"}">${esc(f.kind)}</span>`;
        const cls = f.kind === "structure" ? "r-struct" : f.kind === "data-gap" ? "r-gap" : "";
        const d = f.kind === "style" ? splitStyle(f.message) : null;
        if (!d) {
          const trk = f.tracked ? ` <span class="trk">tracked ${esc(f.tracked)}</span>` : "";
          return `<tr class="${cls}"><td class="k">${tag}</td><td class="sel"><code>${esc(f.selector ?? "")}</code></td><td class="msg" colspan="2">${esc(f.message)}${trk}</td></tr>`;
        }
        return `<tr><td class="k">${tag}</td><td class="sel"><code>${esc(f.selector ?? "")}</code> <span class="prop">${esc(d.prop)}</span></td><td class="got">${valueCell(d.prop, d.got, "is")}</td><td class="want">${valueCell(d.prop, d.want, "want")}</td></tr>`;
      }).join("");

    const c = counts.find((x) => x.page === r.page);
    const pills = [
      c.structure ? `<span class="pill pill-s">${c.structure} structural</span>` : "",
      c.style ? `<span class="pill pill-y">${c.style} style</span>` : "",
      c.gap ? `<span class="pill pill-g">${c.gap} data gap</span>` : "",
    ].join("");

    return `
  <section id="${esc(r.page)}" class="pg">
    <header class="pg-h"><h2>${esc(r.page)}</h2><div class="pg-m">${pills || '<span class="pill pill-p">matches</span>'}</div></header>
    ${r.findings.length ? `<div class="scroll"><table><thead><tr><th>Class</th><th>Element</th><th>Is</th><th>Should be</th></tr></thead><tbody>${rows}</tbody></table></div>`
      : `<p class="ok">Matches its design.</p>`}
  </section>`;
  }).join("");

  const head = agg.verdict === "PASS"
    ? `${agg.pages} page${agg.pages === 1 ? "" : "s"} match their design`
    : `${total} mismatch${total === 1 ? "" : "es"} across ${agg.pages} page${agg.pages === 1 ? "" : "s"}`;

  const drift = meta.drift
    ? `<span>Colour literals <b>${meta.drift.total}</b>${meta.drift.delta ? ` (${meta.drift.delta > 0 ? "+" : ""}${meta.drift.delta})` : ""}</span>`
    : "";

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Design parity — ${esc(agg.verdict)}${meta.repo ? ` · ${esc(meta.repo)}` : ""}</title>
<style>
  :root{
    --paper:#fbfcfd; --card:#fff; --ink:#0f172a; --muted:#8792a6; --faint:#b9c2cf;
    --line:#e4e9f0; --line2:#f1f4f8;
    --block:#dc2626; --block-bg:#fef2f2; --block-br:#fecaca;
    --warn:#d97706; --warn-bg:#fffbeb; --warn-br:#fde68a;
    --pass:#16a34a; --pass-bg:#f0fdf4;
    --accent:#4f46e5;
    --mono:ui-monospace,SFMono-Regular,Menlo,monospace;
    --sans:ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
  }
  @media (prefers-color-scheme:dark){:root{
    --paper:#0b0d12; --card:#12151c; --ink:#e7ecf3; --muted:#8794a8; --faint:#5b6779;
    --line:#222835; --line2:#1a1f29;
    --block:#f87171; --block-bg:#2a1416; --block-br:#5c2326;
    --warn:#fbbf24; --warn-bg:#2a2010; --warn-br:#5c4318;
    --pass:#4ade80; --pass-bg:#10251a; --accent:#a5b4fc;
  }}
  :root[data-theme="dark"]{
    --paper:#0b0d12; --card:#12151c; --ink:#e7ecf3; --muted:#8794a8; --faint:#5b6779;
    --line:#222835; --line2:#1a1f29;
    --block:#f87171; --block-bg:#2a1416; --block-br:#5c2326;
    --warn:#fbbf24; --warn-bg:#2a2010; --warn-br:#5c4318;
    --pass:#4ade80; --pass-bg:#10251a; --accent:#a5b4fc;
  }
  :root[data-theme="light"]{
    --paper:#fbfcfd; --card:#fff; --ink:#0f172a; --muted:#8792a6; --faint:#b9c2cf;
    --line:#e4e9f0; --line2:#f1f4f8;
    --block:#dc2626; --block-bg:#fef2f2; --block-br:#fecaca;
    --warn:#d97706; --warn-bg:#fffbeb; --warn-br:#fde68a;
    --pass:#16a34a; --pass-bg:#f0fdf4; --accent:#4f46e5;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--paper);color:var(--ink);font:13.5px/1.55 var(--sans);
    font-variant-numeric:tabular-nums;-webkit-font-smoothing:antialiased;padding:26px 20px 60px}
  .wrap{max-width:1080px;margin:0 auto;display:flex;flex-direction:column;gap:20px}
  .hero{background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden}
  .hero-top{display:flex;align-items:flex-start;gap:16px;padding:20px 22px;border-bottom:1px solid var(--line)}
  .h-BLOCK{background:var(--block-bg)} .h-WARN{background:var(--warn-bg)} .h-PASS{background:var(--pass-bg)}
  .mark{width:38px;height:38px;border-radius:9px;flex:none;display:grid;place-items:center;
    color:#fff;font-size:19px;font-weight:800;line-height:1}
  .m-BLOCK{background:var(--block)} .m-WARN{background:var(--warn)} .m-PASS{background:var(--pass)}
  .hero h1{margin:0;font-size:21px;font-weight:850;letter-spacing:-.015em}
  .t-BLOCK{color:var(--block)} .t-WARN{color:var(--warn)} .t-PASS{color:var(--pass)}
  .hero .sub{margin-top:3px;font-size:12.5px;color:var(--ink);opacity:.72}
  .meta{display:flex;flex-wrap:wrap;gap:0 26px;padding:12px 22px;font-size:11.5px;color:var(--muted)}
  .meta b{color:var(--ink);font-weight:650;font-family:var(--mono);font-size:11px}
  .tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(178px,1fr));gap:9px}
  .tile{display:flex;flex-direction:column;gap:3px;padding:12px 14px;text-decoration:none;
    background:var(--card);border:1px solid var(--line);border-left:3px solid var(--block);
    border-radius:9px;color:inherit;transition:border-color .12s,transform .12s}
  .tile.v-pass{border-left-color:var(--pass)} .tile.v-warn{border-left-color:var(--warn)}
  .tile:hover{transform:translateY(-1px);border-color:var(--accent)}
  .tile:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
  .tile-n{font-size:13px;font-weight:750}
  .tile-c{font-size:11px;color:var(--muted)} .tile-c b{color:var(--ink);font-weight:700}
  .pg{background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden}
  .pg-h{display:flex;align-items:center;gap:11px;padding:13px 18px;border-bottom:1px solid var(--line)}
  .pg-h h2{margin:0;font-size:15px;font-weight:800;letter-spacing:-.01em}
  .pg-m{margin-left:auto;display:flex;gap:6px;flex-wrap:wrap}
  .pill{font-size:10px;font-weight:750;padding:2.5px 8px;border-radius:999px;border:1px solid}
  .pill-s{color:var(--block);background:var(--block-bg);border-color:var(--block-br)}
  .pill-y{color:var(--muted);background:var(--line2);border-color:var(--line)}
  .pill-g{color:var(--warn);background:var(--warn-bg);border-color:var(--warn-br)}
  .pill-p{color:var(--pass);background:var(--pass-bg);border-color:var(--pass)}
  .ok{margin:0;padding:14px 18px;font-size:12.5px;color:var(--pass)}
  .scroll{overflow-x:auto}
  table{width:100%;border-collapse:collapse;min-width:600px}
  th{text-align:left;font-size:9px;font-weight:800;letter-spacing:.09em;text-transform:uppercase;
    color:var(--faint);padding:8px 18px;border-bottom:1px solid var(--line);white-space:nowrap}
  td{padding:8px 18px;border-bottom:1px solid var(--line2);vertical-align:middle}
  tbody tr:last-child td{border-bottom:none}
  tr.r-struct td{background:var(--block-bg)} tr.r-gap td{background:var(--warn-bg)}
  .k{width:1%;white-space:nowrap}
  .tag{font-size:8.5px;font-weight:800;letter-spacing:.07em;text-transform:uppercase;
    padding:2px 6px;border-radius:3px;white-space:nowrap}
  .tag-s{background:var(--block);color:#fff}
  .tag-y{background:var(--line2);color:var(--muted)}
  .tag-g{background:var(--warn);color:#fff}
  .sel code{font:11px var(--mono);color:var(--ink)}
  .prop{font:10.5px var(--mono);color:var(--accent);margin-left:5px}
  .msg{font-size:12px}
  .trk{font:10px var(--mono);color:var(--warn);border:1px solid var(--warn-br);padding:1px 5px;border-radius:3px}
  .got,.want{white-space:nowrap;width:1%}
  .v{font:11.5px var(--mono);padding:2px 6px;border-radius:4px}
  .v.is{color:var(--block);background:var(--block-bg);text-decoration:line-through}
  .v.want{color:var(--pass);background:var(--pass-bg)}
  .sw{display:inline-block;width:11px;height:11px;border-radius:3px;margin-right:5px;
    border:1px solid rgba(128,138,157,.45);vertical-align:-1px}
  .rad{display:inline-block;width:15px;height:15px;margin-right:5px;vertical-align:-3px;
    border:1.5px solid currentColor;opacity:.55}
  footer{font-size:11px;color:var(--muted);text-align:center;line-height:1.7}
  footer code{font:10.5px var(--mono)}
  @media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>
</head>
<body>
<div class="wrap">
  <div class="hero">
    <div class="hero-top h-${esc(agg.verdict)}">
      <div class="mark m-${esc(agg.verdict)}">${ICON[agg.verdict]}</div>
      <div>
        <h1 class="t-${esc(agg.verdict)}">${esc(agg.verdict)} — ${esc(head)}</h1>
        <div class="sub">${agg.verdict === "PASS"
          ? "Structure and computed styles match the approved design."
          : "Every delta below is a measured difference between the approved mockup and the running page."}</div>
      </div>
    </div>
    <div class="meta">
      ${meta.repo ? `<span>Repo <b>${esc(meta.repo)}</b></span>` : ""}
      ${meta.branch ? `<span>Branch <b>${esc(meta.branch)}</b></span>` : ""}
      ${meta.sha ? `<span>Commit <b>${esc(meta.sha)}</b></span>` : ""}
      ${meta.designProject ? `<span>Design <b>${esc(String(meta.designProject).slice(0, 8))}</b></span>` : ""}
      <span>Exit <b>${agg.exitCode}</b></span>
      ${drift}
    </div>
  </div>
  <div class="tiles">${tiles}</div>
  ${sections}
  <footer>Measured ${esc(meta.timestamp ?? "")} by <code>/claude-design-pull</code> — computed styles from both sides, never judged by eye.<br>
  Content differences (real data vs mock data) are ignored by design. There is no partial credit.</footer>
</div>
</body>
</html>
`;
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
      // A colour and a radius delta, because those two render as an actual
      // swatch and an actual corner in the HTML — the part most worth asserting.
      { kind: "style", severity: "block", selector: "chip", message: "backgroundColor rgb(79, 70, 229) → want rgb(15, 17, 23)" },
      { kind: "style", severity: "block", selector: "chip", message: "borderRadius 999px → want 6px" },
      { kind: "data-gap", severity: "info", selector: ".reason", message: "no error field", tracked: "GH#14" },
    ],
  }];
  const agg = { verdict: "BLOCK", exitCode: 1, blocking: 4, dataGaps: 1, pages: 1 };

  const term = renderTerminal(results, agg, { total: 915, delta: 12 });
  console.assert(term.startsWith("✗ BLOCK"), "leads with the verdict");
  console.assert(term.includes("4 mismatches, 1 data gap"), "counts both classes");
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
  console.assert(md.includes("borderRadius 999px"), "radius deltas reach the markdown too");
  console.assert(md.includes("## Data gaps"), "explains why gaps do not block");

  // ── HTML ──
  const html = renderHtml(results, agg, {
    timestamp: "2026-08-01T09:00:00Z", repo: "specter-agent", branch: "main", sha: "abc1234",
    drift: { total: 1037, delta: 122 },
  });
  console.assert(html.startsWith("<!doctype html>"), "HTML is a complete document");
  console.assert(html.includes("</html>"), "and is closed");
  console.assert(html.includes("BLOCK — 5 mismatches"), "leads with the verdict and the count");
  console.assert(!/\b\d+\s*\/\s*\d+\b/.test(html), "never prints a score");
  console.assert(html.includes('<span class="sw"'), "colour deltas render as swatches");
  console.assert(html.includes('data-theme="dark"') && html.includes('data-theme="light"'),
    "both theme overrides are present, so the viewer's toggle wins either way");
  console.assert(html.includes("prefers-color-scheme"), "and the OS preference is honoured");
  console.assert(html.includes("overflow-x:auto"), "wide tables scroll inside their own container");
  console.assert(!/<(script|link rel="stylesheet"|img [^>]*src="http)/i.test(html),
    "self-contained: no external script, stylesheet, or remote image");
  console.assert(html.includes("tracked GH#14"), "tracking refs survive into the HTML");
  // Structure must sort above style: a missing element outranks a wrong pixel.
  console.assert(html.indexOf("tag-s") < html.indexOf("tag-y"), "structural rows come first");

  const passHtml = renderHtml([{ page: "workflows", findings: [] }],
    { verdict: "PASS", exitCode: 0, blocking: 0, dataGaps: 0, pages: 1 });
  console.assert(passHtml.includes("Matches its design."), "a clean page says so");
  console.assert(passHtml.includes("m-PASS"), "and is styled as a pass, not a block");

  _done("report");
}

// Guard on the FLAG, not the filename: matching only the path means importing
// this module from anywhere containing "report" runs the demo as a side effect.
if (process.argv[1]?.includes("report") && process.argv.includes("--self-check")) demo();
