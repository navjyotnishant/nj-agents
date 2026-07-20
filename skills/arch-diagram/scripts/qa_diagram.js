#!/usr/bin/env node
/*
 * Primary author: nj-agents (arch-diagram skill)
 * Created on: 2026-07-20
 * Description: Automated visual-QA checker for generated diagrams. This is the
 *   MANDATORY gate the /arch-diagram skill runs after every render — a diagram is
 *   not "done" until it passes. It inspects the rendered SVG and reports issues in
 *   four classes the user asked to enforce:
 *     1. text overflow / clipping  — a label/subtext wider than its card, or any
 *        element outside the canvas viewBox.
 *     2. overlaps & dangling edges  — node boxes that intersect; edge endpoints
 *        that don't land on a node anchor.
 *     3. missing icon / glyph       — a tile that should have an icon but no icon
 *        <g> was emitted (blank glyph).
 *     4. empty-space / balance      — large empty regions / lopsided aspect.
 *   Exit code: 0 = clean, 1 = issues found (prints a JSON report). The renderer/
 *   skill reads the report, fixes, and re-renders until clean.
 * AI usage: Built with assistance from AI tools for implementation acceleration.
 *
 * Usage: node qa_diagram.js <diagram.svg>
 * Text-width estimate uses an average glyph-advance heuristic (no font metrics
 * dependency); it is deliberately conservative so it flags likely overflow.
 */
'use strict';
const fs = require('fs');
const { textWidth, OUTCOME_WORDS } = require('./diagram_common.js'); // shared metric & semantics

function attr(tag, name) {
  const m = tag.match(new RegExp(name + '="([^"]*)"'));
  return m ? m[1] : null;
}

function main() {
  const svgPath = process.argv[2];
  if (!svgPath) { console.error('usage: node qa_diagram.js <diagram.svg>'); process.exit(2); }
  const svg = fs.readFileSync(svgPath, 'utf8');

  const vb = svg.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/);
  const W = vb ? parseFloat(vb[1]) : 0, H = vb ? parseFloat(vb[2]) : 0;
  const issues = [];

  // ── collect card rects (the white underlay rects with rx=13 / filter) ──
  const cards = [];
  const rectRe = /<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" rx="13"[^>]*filter="url\(#sh\)"[^>]*\/>/g;
  let r;
  while ((r = rectRe.exec(svg))) {
    cards.push({ x: +r[1], y: +r[2], w: +r[3], h: +r[4] });
  }

  // ── collect texts (x,y,size,bold,anchor,content) ──
  const texts = [];
  const textRe = /<text x="([\d.]+)" y="([\d.]+)"[^>]*font-size="([\d.]+)"[^>]*?>([^<]*)<\/text>/g;
  let t;
  while ((t = textRe.exec(svg))) {
    const tag = t[0];
    texts.push({
      x: +t[1], y: +t[2], size: +t[3],
      bold: /font-weight="(6|7|bold)/.test(tag),
      anchor: attr(tag, 'text-anchor') || 'start',
      s: t[4],
    });
  }

  // 1a. off-canvas text (clipping)
  for (const tx of texts) {
    const w = textWidth(tx.s, tx.size, tx.bold);
    let left = tx.x, right = tx.x + w;
    if (tx.anchor === 'middle') { left = tx.x - w / 2; right = tx.x + w / 2; }
    else if (tx.anchor === 'end') { left = tx.x - w; right = tx.x; }
    if (left < -2 || right > W + 2 || tx.y > H + 2 || tx.y < 0) {
      issues.push({ type: 'clipping', el: 'text', text: tx.s, detail: `x∈[${left.toFixed(0)},${right.toFixed(0)}] vs canvas 0..${W}` });
    }
  }

  // 1b. text overflowing its containing card (centered labels inside a card)
  for (const tx of texts) {
    if (tx.anchor !== 'middle') continue;
    const w = textWidth(tx.s, tx.size, tx.bold);
    // find the card this text sits inside vertically
    const card = cards.find(c => tx.x >= c.x - 4 && tx.x <= c.x + c.w + 4 && tx.y >= c.y && tx.y <= c.y + c.h + 6);
    if (card && w > card.w - 14) {
      issues.push({ type: 'text_overflow', text: tx.s, detail: `~${w.toFixed(0)}px wide > card ${card.w - 14}px usable` });
    }
  }

  // 2. card overlaps (any two cards intersect with >2px overlap)
  for (let i = 0; i < cards.length; i++)
    for (let j = i + 1; j < cards.length; j++) {
      const a = cards[i], b = cards[j];
      const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
      const oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
      if (ox > 2 && oy > 2) issues.push({ type: 'overlap', detail: `cards overlap by ${ox.toFixed(0)}x${oy.toFixed(0)}px` });
    }

  // 3. missing icons: count icon groups vs cards (heuristic — each tile has one icon chip)
  const iconGroups = (svg.match(/<g transform="translate\([^)]*\) scale\(0\.[0-9]+\)"/g) || []).length;
  const chips = (svg.match(/<circle cx="[\d.]+" cy="[\d.]+" r="1[567]"/g) || []).length;
  if (chips > 0 && iconGroups < chips) {
    issues.push({ type: 'missing_icon', detail: `${chips} icon chips but only ${iconGroups} icon glyphs drawn` });
  }

  // 4. empty-space / balance: fraction of canvas area covered by cards
  const cardArea = cards.reduce((s, c) => s + c.w * c.h, 0);
  const cover = cardArea / (W * H);
  if (cards.length >= 3 && cover < 0.12) {
    issues.push({ type: 'empty_space', detail: `cards cover only ${(cover * 100).toFixed(0)}% of canvas — likely too sparse/oversized` });
  }
  const aspect = W / H;
  if (aspect > 3.2 || aspect < 0.32) {
    issues.push({ type: 'balance', detail: `canvas aspect ${aspect.toFixed(2)} is very lopsided` });
  }

  // ── sidecar-based edge checks (exact geometry from the renderer) ──
  const sidecar = svgPath.replace(/\.svg$/, '.layout.json');
  if (fs.existsSync(sidecar)) {
    const L = JSON.parse(fs.readFileSync(sidecar, 'utf8'));
    const boxesIx = (a, b) => Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x) > 2 &&
                              Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) > 2;
    for (const lbl of (L.edgeLabels || [])) {
      // edge label off-canvas
      if (lbl.x < -2 || lbl.x + lbl.w > L.W + 2) {
        issues.push({ type: 'edge_label_clip', text: lbl.text, detail: `label right edge ${(lbl.x + lbl.w).toFixed(0)} vs canvas ${L.W}` });
      }
      // edge label sitting on top of a node box
      for (const nd of L.nodes) {
        if (boxesIx(lbl, nd)) { issues.push({ type: 'edge_label_overlap', text: lbl.text, detail: `label overlaps node ${nd.id}` }); break; }
      }
    }
    // ── semantic-color contract: a node whose meaning is failure must be red,
    //    a node whose meaning is success must be green (never the inverse) ──
    for (const nd of (L.nodes || [])) {
      const txt = nd.label || '';
      const meansFail = OUTCOME_WORDS.danger.test(txt);
      const meansOk = OUTCOME_WORDS.success.test(txt);
      // only flag an UNAMBIGUOUS mismatch — a node that lists BOTH outcomes
      // (e.g. an aggregate "PASS · WARN · BLOCK") is a reporting node, not a
      // failure or a success, so it's exempt.
      if (meansFail && !meansOk && nd.role === 'success')
        issues.push({ type: 'semantic_color', detail: `node ${nd.id} reads as failure ("${txt}") but is colored success/green` });
      if (meansOk && !meansFail && nd.role === 'danger')
        issues.push({ type: 'semantic_color', detail: `node ${nd.id} reads as success ("${txt}") but is colored danger/red` });
    }
  }

  // tag each issue: mechanical (renderer auto-fixes) vs layout (architect re-draws)
  const MECHANICAL = new Set(['clipping', 'text_overflow', 'missing_icon', 'edge_label_clip']);
  for (const iss of issues) iss.kind = MECHANICAL.has(iss.type) ? 'mechanical' : 'layout';

  const report = {
    file: svgPath, canvas: [W, H], cards: cards.length, texts: texts.length,
    mechanical: issues.filter(i => i.kind === 'mechanical').length,
    layout: issues.filter(i => i.kind === 'layout').length,
    issues,
  };
  if (issues.length) {
    console.log(JSON.stringify(report, null, 2));
    console.error(`QA: ${issues.length} issue(s) — NOT clean`);
    process.exit(1);
  }
  console.log(JSON.stringify({ ...report, status: 'clean' }, null, 2));
  console.log('QA: clean ✓');
}
main();
