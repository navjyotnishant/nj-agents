#!/usr/bin/env node
/*
 * Primary author: nj-agents (arch-diagram skill)
 * Created on: 2026-07-20
 * Description: Icon-tile diagram renderer for the /arch-diagram skill.
 *   Turns a JSON diagram model into a self-contained SVG in the house style:
 *   Style-C icon tiles (crisp line icon on top, label under, class-color stripe)
 *   + Style-A polish (soft rounded cards, subtle shadow) + a SUBTLE Excalidraw
 *   hand-drawn texture (rough.js) on the tile borders and connectors. Icons and
 *   text stay crisp for legibility; only the outlines get the sketch wobble.
 *
 *   Layout is grid-driven (lanes = columns, tiles stack in rows) so tiles never
 *   overlap by construction, and connectors route on clean orthogonal channels.
 * AI usage: Built with assistance from AI tools for implementation acceleration.
 *
 * Deps: roughjs (npm install in this dir). Node stdlib otherwise.
 * Usage: node icon_diagram.js <model.json> <out.svg>
 *
 * Model JSON (see suite-overview.iconmodel.json for a full example):
 * {
 *   "title","subtitle",
 *   "lanes":[ {"id","label","role","items":[ {"id","label","icon","sub?","emphasis?"} ]} ],
 *   "notes":[ {"laneId","text"} ],
 *   "edges":[ {"from","to","label?","dashed?","role?"} ]   // from/to = item id or lane id
 * }
 * icon = one of the keys in ICONS below.
 */
'use strict';
const fs = require('fs');
const rough = require('roughjs');
const { ICONS, ROLE, INK, SOFT, FAINT, PAPER, textWidth, fitFontSize } = require('./diagram_common.js');

// ── geometry ────────────────────────────────────────────────────────────────
const TILE_W = 168, TILE_H = 92, GAP_Y = 16, GAP_X = 46;
const LANE_PAD = 20, LANE_HEAD = 44, MARGIN = 40, TITLE_H = 66;

function layout(model) {
  const lanes = model.lanes.map((l, i) => ({ ...l, i }));
  let x = MARGIN;
  let maxRows = 0;
  for (const lane of lanes) {
    lane.x = x;
    lane.w = TILE_W + LANE_PAD * 2;
    lane.items.forEach((it, r) => {
      it.x = lane.x + LANE_PAD;
      it.y = MARGIN + TITLE_H + LANE_HEAD + r * (TILE_H + GAP_Y);
      it.cx = it.x + TILE_W / 2;
      it.cy = it.y + TILE_H / 2;
    });
    maxRows = Math.max(maxRows, lane.items.length);
    x += lane.w + GAP_X;
  }
  const W = x - GAP_X + MARGIN;
  const laneBottom = MARGIN + TITLE_H + LANE_HEAD + maxRows * (TILE_H + GAP_Y) - GAP_Y + LANE_PAD;
  for (const lane of lanes) {
    lane.y = MARGIN + TITLE_H;
    lane.h = laneBottom - lane.y + (lane.note ? 34 : 0);
  }
  const H = laneBottom + 40 + (model.notes && model.notes.length ? 26 : 0);
  return { lanes, W, H };
}

function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

function main() {
  const [modelPath, outPath] = process.argv.slice(2);
  if (!modelPath || !outPath) { console.error('usage: node icon_diagram.js <model.json> <out.svg>'); process.exit(2); }
  const model = JSON.parse(fs.readFileSync(modelPath, 'utf8'));
  const lay = layout(model);
  const { lanes, H } = lay;
  // auto-fix (clipping): widen canvas so title & subtitle never run off-edge
  const MARGIN2 = 40;
  const titleW = model.title ? MARGIN2 + textWidth(model.title, 24, true) + MARGIN2 : 0;
  const subW = model.subtitle ? MARGIN2 + textWidth(model.subtitle, 13, false) + MARGIN2 : 0;
  const W = Math.max(lay.W, titleW, subW);

  const itemById = {};
  lanes.forEach(l => l.items.forEach(it => { itemById[it.id] = it; }));
  const laneById = {}; lanes.forEach(l => { laneById[l.id] = l; });

  // rough.js generator → SVG path strings
  const rc = rough.svg(/* stub svg node */ { ownerDocument: null,
    createElementNS: () => ({ setAttribute() {}, appendChild() {}, }) });
  const gen = rc.generator;
  const roughPath = (drawable) => gen.toPaths(drawable)
    .map(p => `<path d="${p.d}" stroke="${p.stroke}" stroke-width="${p.strokeWidth}" fill="${p.fill || 'none'}" stroke-linecap="round" stroke-linejoin="round"/>`).join('');

  const PAD = 18, FW = W + PAD * 2, FH = H + PAD * 2;
  const out = [];
  out.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${FW}" height="${FH}" viewBox="0 0 ${FW} ${FH}" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">`);
  out.push(`<defs><filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#1b1e24" flood-opacity="0.10"/></filter></defs>`);
  out.push(`<rect x="6" y="6" width="${FW - 12}" height="${FH - 12}" rx="18" fill="#ffffff"/>`);
  const frame = gen.rectangle(8, 8, FW - 16, FH - 16, { roughness: 1.1, bowing: 0.8, stroke: '#1b1e24', strokeWidth: 1.8, fill: 'none' });
  out.push(`<g>${roughPath(frame)}</g>`);
  out.push(`<g transform="translate(${PAD},${PAD})">`);

  // title
  if (model.title) {
    out.push(`<text x="${MARGIN}" y="${MARGIN + 26}" font-size="24" font-weight="700" fill="${INK}">${esc(model.title)}</text>`);
    if (model.subtitle) out.push(`<text x="${MARGIN}" y="${MARGIN + 50}" font-size="13" fill="${FAINT}">${esc(model.subtitle)}</text>`);
  }

  // lanes (subtle rough rounded rect)
  for (const lane of lanes) {
    const r = ROLE[lane.role] || ROLE.neutral;
    const rr = gen.rectangle(lane.x, lane.y, lane.w, lane.h, { roughness: 1.0, bowing: 0.6, stroke: r.stripe, strokeWidth: 1.4, fill: r.soft, fillStyle: 'solid' });
    out.push(`<g>${roughPath(rr)}</g>`);
    out.push(`<text x="${lane.x + LANE_PAD}" y="${lane.y + 27}" font-size="13" font-weight="700" fill="${r.ink}" letter-spacing="0.4">${esc(lane.label)}</text>`);
  }

  // connectors FIRST (under tiles), rough lines
  const anchor = (id, side) => {
    const it = itemById[id]; const ln = laneById[id];
    if (it) {
      if (side === 'r') return [it.x + TILE_W, it.cy];
      if (side === 'l') return [it.x, it.cy];
      if (side === 'b') return [it.cx, it.y + TILE_H];
      return [it.cx, it.cy];
    }
    if (ln) {
      if (side === 'r') return [ln.x + ln.w, ln.y + ln.h / 2];
      if (side === 'l') return [ln.x, ln.y + ln.h / 2];
      return [ln.x + ln.w / 2, ln.y + ln.h / 2];
    }
    return [0, 0];
  };
  for (const e of (model.edges || [])) {
    const r = ROLE[e.role] || ROLE.neutral;
    const [x1, y1] = anchor(e.from, 'r');
    const [x2, y2] = anchor(e.to, 'l');
    const midx = (x1 + x2) / 2;
    // orthogonal 3-segment path via rough line segments
    const opts = { roughness: 0.8, bowing: 0.4, stroke: r.stripe, strokeWidth: 1.6 };
    const segs = [[x1, y1, midx, y1], [midx, y1, midx, y2], [midx, y2, x2, y2]];
    let dashPrefix = e.dashed ? ' stroke-dasharray="6 5"' : '';
    for (const [a, b, c, d] of segs) {
      const ln = gen.line(a, b, c, d, opts);
      out.push(`<g${dashPrefix}>${roughPath(ln)}</g>`);
    }
    // arrowhead
    const ang = Math.atan2(y2 - y2, x2 - midx) || 0;
    out.push(`<path d="M${x2 - 8},${y2 - 4} L${x2},${y2} L${x2 - 8},${y2 + 4}" fill="none" stroke="${r.stripe}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>`);
    if (e.label) out.push(`<text x="${midx}" y="${Math.min(y1, y2) - 6}" font-size="10" fill="${r.ink}" text-anchor="middle">${esc(e.label)}</text>`);
  }

  // tiles (icon + label), rough border + crisp icon/text
  for (const lane of lanes) {
    const r = ROLE[lane.role] || ROLE.neutral;
    for (const it of lane.items) {
      const role = ROLE[it.role || lane.role] || r;
      // card (rough, white fill, shadow via filter on a plain rect underlay)
      out.push(`<rect x="${it.x}" y="${it.y}" width="${TILE_W}" height="${TILE_H}" rx="13" fill="${PAPER}" filter="url(#sh)"/>`);
      const card = gen.rectangle(it.x, it.y, TILE_W, TILE_H, { roughness: it.emphasis ? 1.1 : 0.9, bowing: 0.7, stroke: role.stripe, strokeWidth: it.emphasis ? 2.2 : 1.4, fill: 'none' });
      out.push(`<g>${roughPath(card)}</g>`);
      // top stripe
      out.push(`<path d="M${it.x + 13},${it.y + 1.5} h${TILE_W - 26}" stroke="${role.stripe}" stroke-width="3" stroke-linecap="round"/>`);
      // icon chip (gradient-free soft circle in class color) + crisp line icon
      const chipR = 17, chipCx = it.cx, chipCy = it.y + 30;
      out.push(`<circle cx="${chipCx}" cy="${chipCy}" r="${chipR}" fill="${role.soft}" stroke="${role.stripe}" stroke-width="1"/>`);
      const ic = ICONS[it.icon] || ICONS.box;
      out.push(`<g transform="translate(${chipCx - 11},${chipCy - 11}) scale(0.92)" fill="none" stroke="${role.stripe}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${ic}</g>`);
      // label (shrink-to-fit within the tile width — mechanical auto-fix)
      const lf = fitFontSize(it.label, 12.5, TILE_W - 16, true);
      out.push(`<text x="${it.cx}" y="${it.y + 66}" font-size="${lf}" font-weight="600" fill="${INK}" text-anchor="middle">${esc(it.label)}</text>`);
      if (it.sub) { const sf = fitFontSize(it.sub, 10, TILE_W - 16, false); out.push(`<text x="${it.cx}" y="${it.y + 81}" font-size="${sf}" fill="${FAINT}" text-anchor="middle">${esc(it.sub)}</text>`); }
    }
    if (lane.note) {
      out.push(`<text x="${lane.x + LANE_PAD}" y="${lane.y + lane.h - 12}" font-size="10" fill="${(ROLE[lane.role] || ROLE.neutral).ink}">${esc(lane.note)}</text>`);
    }
  }

  out.push('</g>');
  out.push('</svg>');
  fs.writeFileSync(outPath, out.join('\n'));
  console.log(`wrote ${outPath} (${FW}x${FH})`);
}
main();
