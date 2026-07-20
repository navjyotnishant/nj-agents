#!/usr/bin/env node
/*
 * Primary author: nj-agents (arch-diagram skill)
 * Created on: 2026-07-20
 * Description: Flow-diagram renderer (sibling of icon_diagram.js) for process
 *   flows: nodes placed on an explicit col/row grid, joined by colored + labeled
 *   subtle-sketch (rough.js) arrows. Same house style — icon tiles, class colors,
 *   hand-drawn texture on borders/arrows, crisp icons/text. Supports "gate" nodes
 *   (emphasis) and a "batch" group box (the parallel fan-out). Grid placement means
 *   no overlaps by construction.
 * AI usage: Built with assistance from AI tools for implementation acceleration.
 *
 * Usage: node flow_diagram.js <model.json> <out.svg>
 * Model:
 * {
 *   "title","subtitle",
 *   "cols": <n>,                                  // grid width
 *   "nodes":[ {"id","label","icon?","role","col","row","sub?","kind?"} ],
 *       kind: "tile"(default) | "gate" | "out" ; role drives color
 *   "groups":[ {"label","role","cols":[c0,c1],"rows":[r0,r1],"caption?"} ]
 *   "edges":[ {"from","to","label?","role?","dashed?"} ]
 * }
 */
'use strict';
const fs = require('fs');
const rough = require('roughjs');
const { ICONS, ROLE, INK, SOFT, FAINT, PAPER, textWidth, fitFontSize } = require('./diagram_common.js');

const CELL_W = 210, CELL_H = 118, GX = 40, GY = 34, MARGIN = 40, TITLE_H = 66;
const NW = 176, NH = 96;

function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

function main(){
  const [mp,op]=process.argv.slice(2);
  if(!mp||!op){console.error('usage: node flow_diagram.js <model.json> <out.svg>');process.exit(2);}
  const m=JSON.parse(fs.readFileSync(mp,'utf8'));
  const cols=m.cols||4;
  const rowsUsed=Math.max(...m.nodes.map(n=>n.row))+1;
  const cellX=c=>MARGIN+c*(CELL_W+GX);
  const cellY=r=>MARGIN+TITLE_H+r*(CELL_H+GY);
  const gridW=MARGIN*2+cols*CELL_W+(cols-1)*GX;
  // auto-fix (clipping): canvas must be wide enough for the title & subtitle too
  const titleW=m.title?MARGIN+textWidth(m.title,21,true)+MARGIN:0;
  const subW=m.subtitle?MARGIN+textWidth(m.subtitle,12.5,false)+MARGIN:0;
  const W=Math.max(gridW,titleW,subW);
  const H=cellY(rowsUsed)+MARGIN;

  const byId={};
  for(const n of m.nodes){ n.x=cellX(n.col)+(CELL_W-NW)/2; n.y=cellY(n.row)+(CELL_H-NH)/2; n.cx=n.x+NW/2; n.cy=n.y+NH/2; byId[n.id]=n; }

  const rc=rough.svg({ownerDocument:null,createElementNS:()=>({setAttribute(){},appendChild(){}})});
  const gen=rc.generator;
  const rp=d=>gen.toPaths(d).map(p=>`<path d="${p.d}" stroke="${p.stroke}" stroke-width="${p.strokeWidth}" fill="${p.fill||'none'}" stroke-linecap="round" stroke-linejoin="round"/>`).join('');

  const PAD=18, FW=W+PAD*2, FH=H+PAD*2;
  const o=[];
  o.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${FW}" height="${FH}" viewBox="0 0 ${FW} ${FH}" font-family="-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">`);
  o.push(`<defs><filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#1b1e24" flood-opacity="0.10"/></filter></defs>`);
  // outer frame (border) around the whole figure
  o.push(`<rect x="6" y="6" width="${FW-12}" height="${FH-12}" rx="18" fill="#ffffff" stroke="#e4e7ec" stroke-width="1.5"/>`);
  o.push(`<g transform="translate(${PAD},${PAD})">`);
  if(m.title){o.push(`<text x="${MARGIN}" y="${MARGIN+24}" font-size="21" font-weight="700" fill="${INK}">${esc(m.title)}</text>`);
    if(m.subtitle)o.push(`<text x="${MARGIN}" y="${MARGIN+46}" font-size="12.5" fill="${FAINT}">${esc(m.subtitle)}</text>`);}

  // groups (batch boxes) under everything
  for(const g of (m.groups||[])){
    const r=ROLE[g.role]||ROLE.neutral;
    const gx=cellX(g.cols[0])+8, gy=cellY(g.rows[0])+2;
    const gw=cellX(g.cols[1])+CELL_W-8-gx, gh=cellY(g.rows[1])+CELL_H-6-gy;
    const rr=gen.rectangle(gx,gy,gw,gh,{roughness:1.0,bowing:0.6,stroke:r.stripe,strokeWidth:1.3,fill:r.soft,fillStyle:'solid'});
    o.push(`<g stroke-dasharray="1 0">${rp(rr)}</g>`);
    if(g.label)o.push(`<text x="${gx+14}" y="${gy+20}" font-size="11.5" font-weight="700" fill="${r.ink}">${esc(g.label)}</text>`);
    if(g.caption)o.push(`<text x="${gx+gw/2}" y="${gy+gh-10}" font-size="10" fill="${FAINT}" text-anchor="middle">${esc(g.caption)}</text>`);
  }

  // layout sidecar for QA (node boxes, edge label boxes)
  const layoutMeta = { W, H, nodes: m.nodes.map(n=>({id:n.id,x:n.x,y:n.y,w:NW,h:NH,role:n.role||'neutral',label:[n.label,n.sub].filter(Boolean).join(' ')})), edgeLabels: [] };

  // edges (under nodes), orthogonal rough with arrowhead + label
  const A=(n,s)=> s==='r'?[n.x+NW,n.cy]: s==='l'?[n.x,n.cy]: s==='b'?[n.cx,n.y+NH]: s==='t'?[n.cx,n.y]:[n.cx,n.cy];
  for(const e of (m.edges||[])){
    const r=ROLE[e.role]||ROLE.neutral;
    const a=byId[e.from], b=byId[e.to];
    let p1,p2;
    if(b.col>a.col){p1=A(a,'r');p2=A(b,'l');}
    else if(b.col<a.col){p1=A(a,'l');p2=A(b,'r');}
    else if(b.row>a.row){p1=A(a,'b');p2=A(b,'t');}
    else {p1=A(a,'t');p2=A(b,'b');}
    const [x1,y1]=p1,[x2,y2]=p2;
    const mx=(x1+x2)/2;
    const opts={roughness:0.7,bowing:0.4,stroke:r.stripe,strokeWidth:1.7};
    const dash=e.dashed?' stroke-dasharray="6 5"':'';
    let segs;
    if(Math.abs(y1-y2)<2){ segs=[[x1,y1,x2,y2]]; }
    else if(p1[0]!==A(a,'l')[0]||b.col!==a.col){ segs=[[x1,y1,mx,y1],[mx,y1,mx,y2],[mx,y2,x2,y2]]; }
    else { const my=(y1+y2)/2; segs=[[x1,y1,x1,my],[x1,my,x2,my],[x2,my,x2,y2]]; }
    for(const [aa,bb,cc,dd] of segs){ o.push(`<g${dash}>${rp(gen.line(aa,bb,cc,dd,opts))}</g>`); }
    // arrowhead pointing into p2
    const last=segs[segs.length-1]; const dx=x2-last[0], dy=y2-last[1]; const ang=Math.atan2(dy,dx);
    const ah=(a2)=>[x2-9*Math.cos(a2), y2-9*Math.sin(a2)];
    const [hx1,hy1]=ah(ang-0.4),[hx2,hy2]=ah(ang+0.4);
    o.push(`<path d="M${hx1},${hy1} L${x2},${y2} L${hx2},${hy2}" fill="none" stroke="${r.stripe}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>`);
    if(e.label){
      const lw=textWidth(e.label,10,true);
      const vertical=Math.abs(x1-x2)<2;
      let lx,ly,anchor;
      if(vertical){ // place beside the line, not on the node it passes
        lx=x1+lw/2+8; ly=(y1+y2)/2+3; anchor='middle';
      } else {
        lx=mx; ly=(y1===y2?y1-8:Math.min(y1,y2)-6); anchor='middle';
      }
      o.push(`<text x="${lx}" y="${ly}" font-size="10" font-weight="600" fill="${r.ink}" text-anchor="${anchor}">${esc(e.label)}</text>`);
      layoutMeta.edgeLabels.push({text:e.label,x:lx-lw/2,y:ly-8,w:lw,h:12});
    }
  }

  // nodes
  for(const n of m.nodes){
    const r=ROLE[n.role]||ROLE.neutral;
    const gate=n.kind==='gate';
    o.push(`<rect x="${n.x}" y="${n.y}" width="${NW}" height="${NH}" rx="13" fill="${PAPER}" filter="url(#sh)"/>`);
    const card=gen.rectangle(n.x,n.y,NW,NH,{roughness:gate?1.2:0.9,bowing:0.7,stroke:r.stripe,strokeWidth:gate?2.4:1.4,fill:gate?r.soft:'none',fillStyle:'solid'});
    o.push(`<g>${rp(card)}</g>`);
    o.push(`<path d="M${n.x+13},${n.y+1.5} h${NW-26}" stroke="${r.stripe}" stroke-width="3" stroke-linecap="round"/>`);
    if(n.icon){
      const cx=n.cx, cy=n.y+30;
      o.push(`<circle cx="${cx}" cy="${cy}" r="16" fill="${r.soft}" stroke="${r.stripe}" stroke-width="1"/>`);
      o.push(`<g transform="translate(${cx-10},${cy-10}) scale(0.86)" fill="none" stroke="${r.stripe}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${ICONS[n.icon]||ICONS.box}</g>`);
      const lf=fitFontSize(n.label,12.5,NW-16,true);
      o.push(`<text x="${n.cx}" y="${n.y+64}" font-size="${lf}" font-weight="600" fill="${INK}" text-anchor="middle">${esc(n.label)}</text>`);
      if(n.sub){const sf=fitFontSize(n.sub,10,NW-22,false);o.push(`<text x="${n.cx}" y="${n.y+80}" font-size="${sf}" fill="${gate?r.ink:FAINT}" text-anchor="middle">${esc(n.sub)}</text>`);}
    } else {
      // text-only node (gate/out) — centered label + sub, shrink-to-fit
      const lf=fitFontSize(n.label,13,NW-16,true);
      o.push(`<text x="${n.cx}" y="${n.y+ (n.sub?42:52)}" font-size="${lf}" font-weight="700" fill="${r.ink}" text-anchor="middle">${esc(n.label)}</text>`);
      if(n.sub){const sf=fitFontSize(n.sub,10.5,NW-22,false);o.push(`<text x="${n.cx}" y="${n.y+62}" font-size="${sf}" fill="${SOFT}" text-anchor="middle">${esc(n.sub)}</text>`);}
    }
  }
  o.push('</g>');
  o.push('</svg>');
  fs.writeFileSync(op,o.join('\n'));
  // sidecar in content coords; QA uses these (W/H here = content box, matches nodes/labels)
  fs.writeFileSync(op.replace(/\.svg$/,'.layout.json'), JSON.stringify(layoutMeta));
  console.log(`wrote ${op} (${FW}x${FH})`);
}
main();
