# The HTML skeleton

The report's actual markup. **Use this file, do not re-author it** — it is what
makes every issue look like the same publication rather than a fresh design each
week.

Four placeholders to fill:

| Placeholder | Replace with |
|---|---|
| `{title}` | `Vertical Pulse - <Vertical>` or `Account Deep-Dive - <Vertical>` |
| `{fonts}` | the Google Fonts href below |
| `{nav}` | one `<button class="tab" data-goto="N">` per page |
| `{pages}` | the page sections, in order: cover, one per account, market, competition |

The fonts href:

```
https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,700;0,900;1,400;1,700&family=Source+Serif+4:ital,opsz,wght@0,8..60,300;0,8..60,400;0,8..60,600;1,8..60,400&family=DM+Sans:wght@400;500;600;700&display=swap
```

## Rules

- **Self-contained, one file.** Inline every image as a base64 data URI. No
  external stylesheet, no external script, no remote image. The only external
  reference is the fonts link, which degrades to the named fallbacks.
- **Dark variant**: swap the `:root` values for the dark palette in
  `reference-render.md`. Nothing else changes.
- **Per-account colour** rides on `--brand`, set inline on each client
  `<section class="page client" style="--brand:#1B6BC5">`.
- The pager script at the bottom is required for flipping, but pages must still
  stack and print in order with JavaScript disabled.

## The skeleton

```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>The EM Weekly | {title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="{fonts}" rel="stylesheet">
<style>
  :root {
    --newsprint:#E8E4DC; --paper:#F5F1E8; --ink:#0A1E3D; --gold:#C8A96E;
    --body:#3D3830; --muted:#555048; --caption:#7A6F64; --rule:#C8C0B0;
    --insight:#F0EBE0; --blue:#0057A8; --orange:#E8560A; --red:#C0392B;
    --green:#1A7F5A; --slate:#4A6480;
    --chrome:#0A1E3D; --chrome-on:#F5F1E8;
    --brand:#0A1E3D;
    --f-head:'Playfair Display',Georgia,serif;
    --f-body:'Source Serif 4','Times New Roman',serif;
    --f-ui:'DM Sans',Arial,sans-serif;
  }
  * { box-sizing:border-box; }
  body {
    margin:0; background:var(--newsprint); color:var(--body);
    font-family:var(--f-body); font-size:14px; line-height:1.5;
    -webkit-font-smoothing:antialiased;
  }

  /* --- page shell: a bound issue, one page visible at a time --- */
  .issue { max-width:1080px; margin:0 auto; padding:0 0 40px; }
  .page {
    background:var(--paper); padding:26px 32px 34px;
    box-shadow:0 2px 20px rgba(0,0,0,.15); min-height:78vh;
  }
  /* JS hides all but the current page; without JS every page stacks and prints. */
  body.paged .page { display:none; }
  body.paged .page.on { display:block; animation:flip .28s ease-out; }
  @keyframes flip { from { opacity:0; transform:translateX(10px); } }
  @media (prefers-reduced-motion:reduce) { body.paged .page.on { animation:none; } }

  /* --- navigation --- */
  .nav {
    display:flex; flex-wrap:wrap; gap:1px; background:var(--chrome);
    padding:0; position:sticky; top:0; z-index:5;
  }
  .tab {
    flex:1 1 auto; background:transparent; border:0; cursor:pointer;
    font-family:var(--f-ui); font-size:11px; font-weight:600; letter-spacing:.1em;
    text-transform:uppercase; color:color-mix(in srgb, var(--chrome-on) 62%, transparent);
    padding:11px 12px; display:flex; align-items:baseline; gap:7px;
    justify-content:center; white-space:nowrap;
  }
  .tab-n { font-size:11px; color:var(--gold); }
  .tab:hover { color:var(--chrome-on); background:color-mix(in srgb, var(--chrome-on) 8%, transparent); }
  .tab[aria-current="true"] { background:var(--paper); color:var(--ink); }
  .tab[aria-current="true"] .tab-n { color:var(--orange); }
  .pager {
    display:flex; justify-content:space-between; align-items:center;
    padding:12px 32px; background:var(--chrome);
    font-family:var(--f-ui); font-size:11px; letter-spacing:.08em;
    text-transform:uppercase; color:color-mix(in srgb, var(--chrome-on) 58%, transparent);
  }
  .pager button {
    background:transparent; border:1px solid color-mix(in srgb, var(--chrome-on) 26%, transparent);
    color:var(--chrome-on);
    font-family:var(--f-ui); font-size:11px; letter-spacing:.08em; text-transform:uppercase;
    padding:6px 14px; cursor:pointer;
  }
  .pager button:disabled { opacity:.3; cursor:default; }
  .pager button:hover:not(:disabled) { background:color-mix(in srgb, var(--chrome-on) 13%, transparent); }

  /* --- shared type --- */
  .kicker {
    font-family:var(--f-ui); font-size:11px; font-weight:600; letter-spacing:.14em;
    text-transform:uppercase; color:var(--orange); margin-bottom:9px;
    padding-bottom:6px; border-bottom:1px solid var(--rule);
  }
  .kicker.light { color:var(--gold); border-bottom-color:rgba(200,169,110,.35); }
  .sub {
    font-family:var(--f-body); font-style:italic; font-size:12px;
    color:var(--caption); margin:-4px 0 10px;
  }
  .src {
    font-family:var(--f-ui); font-size:11px; font-style:normal;
    color:var(--caption); margin-left:6px; white-space:nowrap;
  }
  .thin { font-style:italic; color:var(--muted); }

  /* --- cover --- */
  .mast { text-align:center; border-bottom:2px solid var(--ink); padding-bottom:12px; }
  .logo { color:var(--ink); line-height:0; margin-bottom:12px; }
  .logo-type { font-family:var(--f-ui); font-weight:700; font-size:25px;
    letter-spacing:-.02em; line-height:1; }
  .logo-img { display:inline-block; margin-bottom:12px; height:auto; }
  .mast-rail {
    font-family:var(--f-ui); font-size:11px; letter-spacing:.18em; text-transform:uppercase;
    color:var(--muted); margin-bottom:12px;
  }
  .mast-title {
    margin:0; font-family:var(--f-head); font-weight:900;
    font-size:clamp(40px,6vw,62px); line-height:1; letter-spacing:-.02em; color:var(--ink);
  }
  .mast-sub {
    font-family:var(--f-body); font-style:italic; font-size:13px;
    color:var(--muted); margin-top:5px;
  }
  .mast-meta {
    background:var(--chrome); color:color-mix(in srgb, var(--chrome-on) 78%, transparent); margin:0 -32px 22px;
    padding:8px 32px; font-family:var(--f-ui); font-size:11px; letter-spacing:.06em;
    display:flex; flex-wrap:wrap; gap:10px; align-items:center;
  }
  .cov { margin-left:auto; display:flex; gap:8px; }
  .cov-chip { color:var(--gold); }
  .cov-chip[data-live="0"] { color:color-mix(in srgb, var(--chrome-on) 42%, transparent); }
  .cover-body { display:grid; grid-template-columns:1.6fr 1fr; gap:28px; }
  .cover-hed {
    margin:0 0 10px; font-family:var(--f-head); font-weight:700;
    font-size:clamp(24px,3.2vw,34px); line-height:1.18; color:var(--ink);
  }
  .cover-lede { margin:0; font-size:15px; line-height:1.62; }
  .cover-toc ol { margin:0; padding:0; list-style:none; }
  .toc {
    width:100%; text-align:left; background:transparent; border:0; cursor:pointer;
    border-bottom:1px solid var(--rule); padding:9px 0;
    display:flex; align-items:baseline; gap:10px; font-family:inherit;
  }
  .toc:hover .toc-name { color:var(--orange); }
  .toc-n { font-family:var(--f-ui); font-size:11px; color:var(--gold); }
  .toc-name { font-family:var(--f-head); font-weight:700; font-size:17px; color:var(--ink); }
  .toc-meta {
    margin-left:auto; font-family:var(--f-ui); font-size:11px; color:var(--caption);
  }

  /* --- client page --- */
  .page-head {
    background:var(--brand); color:#fff; margin:-26px -32px 20px; padding:14px 32px;
    display:flex; align-items:baseline; gap:14px; flex-wrap:wrap;
  }
  .page-head.plain { background:var(--chrome); }
  .page-n { font-family:var(--f-ui); font-size:11px; letter-spacing:.1em;
    color:color-mix(in srgb, var(--chrome-on) 68%, transparent); }
  .page-title {
    margin:0; font-family:var(--f-head); font-weight:700;
    font-size:clamp(24px,3vw,32px); line-height:1.1;
  }
  .page-tag {
    margin-left:auto; font-family:var(--f-ui); font-size:11px; letter-spacing:.12em;
    text-transform:uppercase; color:color-mix(in srgb, var(--chrome-on) 62%, transparent);
  }
  .client-body { display:grid; grid-template-columns:1.55fr 1fr; gap:26px; }
  .stories { margin:0; padding:0; list-style:none; counter-reset:s; }
  .stories li {
    counter-increment:s; position:relative; padding:10px 0 10px 26px;
    border-bottom:1px solid var(--rule);
  }
  .stories li::before {
    content:counter(s,decimal-leading-zero); position:absolute; left:0; top:11px;
    font-family:var(--f-ui); font-size:11px; font-weight:600; color:var(--brand);
  }
  .stories p { margin:0; font-size:14px; line-height:1.55; }

  /* people moves: a table so names and roles align down the column */
  .people { margin-top:20px; }
  .people table { width:100%; border-collapse:collapse; }
  .people td { padding:8px 8px 8px 0; border-bottom:1px solid var(--rule); vertical-align:baseline; }
  .people .who { font-family:var(--f-head); font-weight:700; font-size:15px; color:var(--ink); white-space:nowrap; }
  .people .verb { font-family:var(--f-ui); font-size:11px; font-weight:600; letter-spacing:.06em; text-transform:uppercase; white-space:nowrap; }
  .people .role { font-size:13px; }
  .people .prev { display:block; font-family:var(--f-ui); font-size:11px; color:var(--caption); }
  .people .when { font-family:var(--f-ui); font-size:11px; color:var(--caption); text-align:right; white-space:nowrap; }

  .insight { background:var(--insight); border-top:3px solid var(--brand); padding:14px 16px; }
  .insight p { margin:0; font-size:13px; line-height:1.62; }
  /* Ask This lives inside the insight: the questions are what the interpretation
     leads to, so they share one panel rather than competing as two sidebars. */
  .asks { margin-top:12px; padding-top:11px; border-top:1px solid var(--rule); }
  .asks-label {
    font-family:var(--f-ui); font-size:11px; font-weight:600; letter-spacing:.12em;
    text-transform:uppercase; color:var(--brand); margin-bottom:7px;
  }
  .asks ol { margin:0; padding-left:18px; }
  .asks li { margin-bottom:7px; font-size:13px; line-height:1.5; }
  .asks li:last-child { margin-bottom:0; }
  .asks li::marker { color:var(--brand); font-family:var(--f-ui); font-size:11px; }
  /* Article imagery. Fixed aspect + object-fit so a portrait or a banner both
     sit in the same slot; the frame is what keeps the grid honest, not the
     source image's proportions. */
  .thumb { width:100%; height:132px; object-fit:cover; display:block;
    margin-bottom:9px; border:1px solid #C8C0B0; }
  .thumb-sm { width:100%; height:84px; object-fit:cover; display:block;
    margin-bottom:7px; border:1px solid #C8C0B0; }
  .hero { width:100%; height:220px; object-fit:cover; display:block;
    margin-top:16px; border:1px solid #C8C0B0; }
  .context { margin-top:18px; }
  .context .feed li { padding:8px 0; }
  .context .feed p { font-size:12px; line-height:1.5; color:var(--muted); }

  a.src { color:var(--blue); text-decoration:none; border-bottom:1px solid transparent; }
  a.src:hover { border-bottom-color:var(--blue); }

  /* --- market + competition: three columns at newspaper density --- */
  .cols { display:grid; grid-template-columns:repeat(3,1fr); gap:24px; }
  .col { border-right:1px solid var(--rule); padding-right:24px; }
  .col:last-child { border-right:0; padding-right:0; }
  .feed { margin:0; padding:0; list-style:none; }
  .feed li { padding:9px 0; border-bottom:1px solid var(--rule); }
  .feed p { margin:0; font-size:13px; line-height:1.55; }
  .radar .tech {
    display:inline-block; background:var(--chrome); color:var(--gold);
    font-family:var(--f-ui); font-size:11px; padding:2px 9px; margin-bottom:5px;
  }
  .pill {
    display:inline-block; color:#fff; font-family:var(--f-ui); font-size:11px;
    font-weight:700; letter-spacing:.06em; padding:2px 8px; margin-bottom:5px;
  }
  .rival-head { display:flex; align-items:baseline; gap:8px; margin-bottom:4px; }
  .rival { font-family:var(--f-head); font-weight:700; font-size:16px; color:var(--ink); }
  .acct {
    font-family:var(--f-ui); font-size:11px; letter-spacing:.08em; text-transform:uppercase;
    background:var(--orange); color:#fff; padding:2px 7px;
  }
  .sowhat {
    margin:6px 0 0 !important; padding-left:10px; border-left:2px solid var(--orange);
    font-style:italic; color:var(--ink);
  }

  .lens { background:var(--chrome); margin:22px -32px -34px; padding:18px 32px 26px; }
  .lens .lens-cols { display:grid; grid-template-columns:repeat(auto-fit,minmax(230px,1fr)); gap:20px; }
  .lens p { margin:0; font-size:13px; line-height:1.6;
    color:color-mix(in srgb, var(--chrome-on) 88%, transparent); }
  .colophon {
    margin-top:22px; padding-top:12px; border-top:1px solid var(--rule);
    font-family:var(--f-ui); font-size:11px; color:var(--caption);
  }

  a:focus-visible, button:focus-visible { outline:2px solid var(--orange); outline-offset:2px; }

  @media (max-width:860px) {
    .cover-body, .client-body { grid-template-columns:1fr; }
    .cols { grid-template-columns:1fr; }
    .col { border-right:0; padding-right:0; border-bottom:1px solid var(--rule); padding-bottom:14px; }
    .col:last-child { border-bottom:0; }
    .page { padding:20px 18px 26px; }
    .page-head { margin:-20px -18px 16px; padding:12px 18px; }
    .mast-meta { margin:0 -18px 18px; padding:8px 18px; }
    .lens { margin:20px -18px -26px; padding:16px 18px 22px; }
    .people .when { display:none; }
  }
  @media print {
    body { background:#fff; }
    body.paged .page { display:block !important; page-break-after:always; }
    .nav, .pager { display:none; }
  }
</style>
</head>
<body>
<div class="issue">
{nav}
{pages}
<div class="pager">
  <button type="button" id="prev">&larr; Previous</button>
  <span id="where"></span>
  <button type="button" id="next">Next &rarr;</button>
</div>
</div>
<script>
(function () {
  var pages = Array.prototype.slice.call(document.querySelectorAll('.page'));
  var tabs = Array.prototype.slice.call(document.querySelectorAll('.tab'));
  if (pages.length < 2) return;            // nothing to flip
  document.body.classList.add('paged');    // only paginate once JS is running
  var at = 0;
  var where = document.getElementById('where');
  var prev = document.getElementById('prev');
  var next = document.getElementById('next');

  function show(i) {
    at = Math.max(0, Math.min(pages.length - 1, i));
    pages.forEach(function (p, n) { p.classList.toggle('on', n === at); });
    tabs.forEach(function (t, n) { t.setAttribute('aria-current', n === at ? 'true' : 'false'); });
    where.textContent = 'Page ' + (at + 1) + ' of ' + pages.length;
    prev.disabled = at === 0;
    next.disabled = at === pages.length - 1;
    window.scrollTo(0, 0);
  }

  tabs.forEach(function (t) {
    t.addEventListener('click', function () { show(Number(t.dataset.goto)); });
  });
  document.querySelectorAll('.toc').forEach(function (b) {
    b.addEventListener('click', function () { show(Number(b.dataset.goto)); });
  });
  prev.addEventListener('click', function () { show(at - 1); });
  next.addEventListener('click', function () { show(at + 1); });
  document.addEventListener('keydown', function (e) {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    if (e.key === 'ArrowRight') show(at + 1);
    if (e.key === 'ArrowLeft') show(at - 1);
  });
  show(0);
})();
</script>
</body></html>```

## Page markup

Fill `{pages}` with these sections, in order. Class names are load-bearing: the
stylesheet above targets them.

### Cover

```html
<section class="page cover" data-page="0">
  <div class="mast">
    <div class="logo" role="img" aria-label="Cybage">…wordmark, inline SVG or type…</div>
    <div class="mast-rail">Engagement Manager Intelligence</div>
    <h1 class="mast-title">Vertical Pulse - FinTech</h1>
    <div class="mast-sub">The EM Weekly &middot; Relationship Intelligence &amp; Market Pulse</div>
  </div>
  <div class="mast-meta">Week of 2026-07-28 &nbsp;|&nbsp; 3 accounts &nbsp;|&nbsp; tier core
    <span class="cov"><span class="cov-chip" data-live="1">web</span>…</span>
  </div>
  <div class="cover-body">
    <div class="cover-lead">
      <div class="kicker">Lead story</div>
      <h2 class="cover-hed">…headline…</h2>
      <p class="cover-lede">…lede…</p>
      <img class="hero" src="data:image/jpeg;base64,…" alt="…">
    </div>
    <div class="cover-toc">
      <div class="kicker">In this issue</div>
      <ol>
        <li><button class="toc" data-goto="1" type="button">
          <span class="toc-n">01</span>
          <span class="toc-name">Remitly</span>
          <span class="toc-meta">2 stories &middot; 2 people moves</span>
        </button></li>
      </ol>
    </div>
  </div>
</section>
```

### One page per account

```html
<section class="page client" data-page="1" style="--brand:#1B6BC5">
  <header class="page-head">
    <div class="page-n">01 / 03</div>
    <h2 class="page-title">Remitly</h2>
    <div class="page-tag">Client Intelligence</div>
  </header>
  <div class="client-body">
    <div class="col-main">
      <div class="kicker">This week</div>
      <ol class="stories">
        <li>
          <img class="thumb" src="data:image/jpeg;base64,…" alt="…">
          <p>…the fact…<a class="src" href="https://…" target="_blank"
             rel="noopener noreferrer">domain.com <span aria-hidden="true">&rarr;</span></a></p>
        </li>
      </ol>

      <div class="people">
        <div class="kicker">People moves</div>
        <table>
          <tr><td>
            <a class="prow" href="https://…" target="_blank" rel="noopener noreferrer">
              <span class="who">Sarah Nakamura</span>
              <span class="verb">Promoted to</span>
              <span class="role">Chief Technology Officer<small>was VP Engineering</small></span>
              <span class="when">2026-07-18</span>
            </a>
          </td></tr>
        </table>
      </div>
    </div>

    <aside class="col-side">
      <div class="insight">
        <div class="kicker">EM Insight</div>
        <p>…interpretation…</p>
        <div class="asks">
          <div class="asks-label">Ask this</div>
          <ol><li>…question…</li></ol>
        </div>
      </div>
      <div class="context">
        <div class="kicker">In the vertical</div>
        <div class="sub">Market context for this week's calls</div>
        <ul class="feed"><li><p>…item…<a class="src" href="…">domain.com &rarr;</a></p></li></ul>
      </div>
    </aside>
  </div>
</section>
```

### Market and Competition

```html
<section class="page market" data-page="4">
  <header class="page-head plain">
    <h2 class="page-title">The Market</h2>
    <div class="page-tag">Vertical context for every account</div>
  </header>
  <div class="cols">
    <div class="col">
      <div class="kicker">Vertical pulse</div>
      <ul class="feed"><li><p>…<a class="src" href="…">domain.com &rarr;</a></p></li></ul>
    </div>
    <div class="col">
      <div class="kicker">Technology radar</div>
      <ul class="feed radar"><li><div class="tech">Agentic AI</div><p>…</p></li></ul>
    </div>
    <div class="col">
      <div class="kicker">Deals &amp; signals</div>
      <ul class="feed deals">
        <li><span class="pill" style="background:#C0392B">Direct</span><p>…</p></li>
      </ul>
    </div>
  </div>
</section>
```

Competition uses the same `.cols` / `.col` / `.feed` structure, with
`<div class="rival-head"><span class="rival">TCS</span><span class="acct">Remitly</span></div>`
per entry and an optional `<p class="sowhat">…</p>`.

### Pager

Immediately after the last `</section>`, inside `.issue`:

```html
<div class="pager">
  <button type="button" id="prev">&larr; Previous</button>
  <span id="where"></span>
  <button type="button" id="next">Next &rarr;</button>
</div>
```

The script at the bottom of the skeleton wires the tabs, the contents buttons, the
pager and the arrow keys. It adds `body.paged` itself, so with JavaScript disabled
every page stays visible and prints in order.
