/*
 * Primary author: nj-agents (arch-diagram skill)
 * Created on: 2026-07-20
 * Description: Shared palette + crisp line-icon set for the icon/flow diagram
 *   renderers. One source of truth so both renderers use the same house style.
 * AI usage: Built with assistance from AI tools for implementation acceleration.
 */
'use strict';

/*
 * SEMANTIC-COLOR CONTRACT (the architect MUST pick the role by meaning):
 *   danger  (red)   → failure, block, stop, gate that rejects, error, "no write",
 *                     risk/PII detection. NEVER use for a successful outcome.
 *   success (green)  → success, pass, "done", the committed/produced output,
 *                     a workflow concluding well. NEVER use for a failure/block.
 *   review/authoring/social → class identity (which suite the node belongs to),
 *                     used for ordinary in-flow steps, not outcome semantics.
 *   neutral (grey)   → inputs / raw / pass-through with no good-or-bad meaning.
 * Rule of thumb: if a node means "something went wrong / was stopped", it is
 * danger; if it means "it worked / here's the result", it is success. A node's
 * outcome meaning overrides its class color.
 * The QA checker enforces this (see qa_diagram.js semantic-color check).
 */
const ROLE = {
  review:    { stripe: '#6366f1', ink: '#4338ca', soft: '#eef0fe' },
  authoring: { stripe: '#f59e0b', ink: '#b45309', soft: '#fef6e7' },
  social:    { stripe: '#0a66c2', ink: '#0a4f9e', soft: '#e8f1fb' },
  success:   { stripe: '#22a35a', ink: '#1c7a44', soft: '#e7f6ee' },
  danger:    { stripe: '#e5484d', ink: '#b4282d', soft: '#fdecec' },
  neutral:   { stripe: '#8b91a0', ink: '#4a4f5a', soft: '#f2f3f5' },
};

// Keyword → expected role, for the QA semantic-color check.
const OUTCOME_WORDS = {
  danger:  /\b(fail|failed|failure|block|blocks|blocked|stop|reject|rejected|error|invalid|denied|no write|unverified|unproven|violation|leak|risk)\b/i,
  success: /\b(pass|passed|success|succeed|done|complete|completed|approved|verified|valid|ok|shipped|committed|clean)\b/i,
};
const INK = '#1b1e24', SOFT = '#5a6070', FAINT = '#8b91a0', PAPER = '#ffffff';

// crisp line icons, 24x24 viewBox, drawn with stroke (no fill)
const ICONS = {
  shield:   '<path d="M12 3l7 3v5c0 4.5-3 7.6-7 9-4-1.4-7-4.5-7-9V6z"/>',
  search:   '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/>',
  bug:      '<rect x="7" y="8" width="10" height="11" rx="5"/><path d="M12 8V5M5 11H2M22 11h-3M5 17H3M21 17h-2M6 6L4 4M18 6l2-2"/>',
  gear:     '<circle cx="12" cy="12" r="3.2"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1"/>',
  package:  '<path d="M12 3l8 4v10l-8 4-8-4V7z"/><path d="M4 7l8 4 8-4M12 11v10"/>',
  brush:    '<path d="M4 20c1.5 0 3-1 3-3 0-1.1-.9-2-2-2s-2 .9-2 2c0 1 .3 2-1 3z"/><path d="M8 15l9-9a2 2 0 013 3l-9 9"/>',
  doclist:  '<rect x="4" y="3" width="14" height="18" rx="2"/><path d="M8 8h6M8 12h6M8 16h4"/>',
  diagram:  '<rect x="3" y="4" width="6" height="6" rx="1"/><rect x="15" y="4" width="6" height="6" rx="1"/><rect x="9" y="14" width="6" height="6" rx="1"/><path d="M6 10v2h12v-2M12 12v2"/>',
  camera:   '<rect x="3" y="6" width="18" height="14" rx="2"/><circle cx="12" cy="13" r="3.4"/><path d="M8 6l1.5-2h5L16 6"/>',
  news:     '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 8h6M7 12h10M7 16h10M15 8h2"/>',
  globe:    '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18"/>',
  send:     '<path d="M3 11l18-8-8 18-2.5-7.5z"/>',
  robot:    '<rect x="5" y="8" width="14" height="10" rx="2"/><circle cx="9.5" cy="13" r="1.3"/><circle cx="14.5" cy="13" r="1.3"/><path d="M12 4v4M9 4h6M4 12H2M22 12h-2"/>',
  download: '<path d="M12 3v11M7 10l5 5 5-5M4 20h16"/>',
  user:     '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/>',
  eye:      '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
  check:    '<circle cx="12" cy="12" r="9"/><path d="M8 12.5l2.5 2.5L16 9"/>',
  block:    '<circle cx="12" cy="12" r="9"/><path d="M6 6l12 12"/>',
  pencil:   '<path d="M4 20l4-1 10-10-3-3L5 16z"/><path d="M14 6l3 3"/>',
  file:     '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4"/>',
  box:      '<rect x="4" y="4" width="16" height="16" rx="2"/>',
};

// Average glyph advance per font-size (heuristic, matches qa_diagram.js).
// Linear glyph-advance model (advance ≈ 0.54 × fontSize), used identically by the
// renderers (fit-to-width) and qa_diagram.js (overflow check) so they never disagree.
function textWidth(str, size, bold) {
  const adv = size * 0.54;
  return String(str).length * adv * (bold ? 1.06 : 1);
}
// Mechanical auto-fix: pick the largest font-size ≤ `size` that fits `maxW`,
// down to `minSize`. Returns the size to use (the renderer then draws at it).
function fitFontSize(str, size, maxW, bold, minSize = 8.5) {
  let s = size;
  while (s > minSize && textWidth(str, s, bold) > maxW) s -= 0.5;
  return s;
}
// If even minSize overflows, truncate with an ellipsis to fit.
function fitText(str, size, maxW, bold) {
  if (textWidth(str, size, bold) <= maxW) return str;
  let s = String(str);
  while (s.length > 3 && textWidth(s + '…', size, bold) > maxW) s = s.slice(0, -1);
  return s + '…';
}

module.exports = { ROLE, OUTCOME_WORDS, INK, SOFT, FAINT, PAPER, ICONS, textWidth, fitFontSize, fitText };
