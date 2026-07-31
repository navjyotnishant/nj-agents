"""Generate every documentation page from the source files, at build time.

Nothing is copied, mirrored, or symlinked into a docs folder. Pages are written into
mkdocs' VIRTUAL docs tree via mkdocs_gen_files, so no generated page exists on disk
and none can drift from the thing it documents. Delete a skill and its page is gone
on the next build; add one and it appears with no registration step.

The skill<->agent wiring is DERIVED, never hand-maintained. No agent declares a
`skills:` frontmatter key -- all 25 carry exactly name/description/tools/color/author
-- so the wiring is recovered from the backticked references inside each SKILL.md,
filtered by set membership against agents/*.md. A reference to a skill or agent that
does not exist raises and FAILS THE BUILD.

Author: navjyotnishant
Created: 2026-07-30
Description: mkdocs-gen-files hook -- builds the skills/agents/harness reference.
"""

import re
from collections import defaultdict
from pathlib import Path

import mkdocs_gen_files

ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = ROOT / "skills"
AGENTS_DIR = ROOT / "agents"
REPO_URL = "https://github.com/navjyotnishant/nj-agents/blob/main"

# Order is deliberate: it is the order a reader meets the toolkit, not alphabetical.
CLASSES = {
    "review": (
        "Review",
        "Advise only. Reads changes, reports findings, and never writes a file or "
        "commits. Shared rules: [`CONVENTIONS.md`]({REPO_URL}/CONVENTIONS.md).",
    ),
    "authoring": (
        "Authoring",
        "Writes exactly one artifact into the repo, then **proposes** the commit — "
        "never runs git itself. Shared rules: [`CONVENTIONS-authoring.md`]({REPO_URL}/CONVENTIONS-authoring.md).",
    ),
    "workflow": (
        "Workflow",
        "Reads a diff and drafts a change artifact — a PR or a commit message — then "
        "proposes it. Sits between review and authoring; never runs git.",
    ),
    "pm": (
        "PM-authoring",
        "Writes a work item into whatever tracker is connected, then proposes the "
        "create. Shared rules: [`CONVENTIONS-pm.md`]({REPO_URL}/CONVENTIONS-pm.md).",
    ),
    "social": (
        "Social",
        "Produces paste-ready copy. Never writes to the repo, never auto-posts.",
    ),
}


class BuildError(Exception):
    """A derived reference did not resolve. The build must not continue."""


def parse_frontmatter(path: Path) -> tuple[dict, str]:
    """Return (frontmatter, body). Only top-level `key: value` pairs are read —
    these files have no nested YAML, so a full parser would be dead weight."""
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise BuildError(f"{path.relative_to(ROOT)}: no frontmatter")
    end = text.index("\n---\n", 4)
    meta = {}
    for line in text[4:end].splitlines():
        if ":" in line and not line.startswith((" ", "\t", "#")):
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip().strip('"')
    return meta, text[end + 5 :]


def strip_comments(text: str) -> str:
    """Template scaffolding legitimately names the tokens we scan for, so a card
    generated from a fresh scaffold would otherwise inherit references it does not
    actually make. Same reasoning as check.sh's body()."""
    return re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)


def load_sources():
    skills, agents = {}, {}
    for d in sorted(SKILLS_DIR.iterdir()):
        f = d / "SKILL.md"
        if f.is_file():
            meta, body = parse_frontmatter(f)
            skills[d.name] = {"meta": meta, "body": body, "path": f}
    for f in sorted(AGENTS_DIR.glob("*.md")):
        meta, body = parse_frontmatter(f)
        agents[f.stem] = {"meta": meta, "body": body, "path": f}
    return skills, agents


def derive_wiring(skills: dict, agents: dict):
    """Skill -> agents it spawns, and the reverse.

    Filtering is by SET MEMBERSHIP against agents/, not by check.sh's suffix
    allow-list (`*-reviewer|*-writer|...`). That list exists so check.sh can spot
    references to files that do not exist; a generator has no such need, and the
    pattern would silently drop a future agent named e.g. `foo-validator`.

    Four names — dead-code-finder, test-gap-finder, deps-upgrade, social-post — belong
    to BOTH a skill and an agent, so a naive scrape self-matches inside the skill's own
    file. Each of those four genuinely does spawn its same-named agent, so the result
    happens to be right, but nothing here relies on that coincidence: membership in
    `agents` is the only test applied.
    """
    spawns = defaultdict(list)
    spawned_by = defaultdict(list)

    for name, s in skills.items():
        body = strip_comments(s["body"])
        for ref in sorted(set(re.findall(r"`([a-z0-9][a-z0-9-]{2,})`", body))):
            if ref in agents and ref not in spawns[name]:
                spawns[name].append(ref)
                spawned_by[ref].append(name)

    # The requirement: a reference to something that does not exist fails the build.
    # check.sh enforces this too, but the docs build must not silently emit a dead
    # link if someone bypasses it.
    orphans = [a for a in agents if not spawned_by[a]]
    if orphans:
        raise BuildError(
            "these agents are referenced by no skill, so their page would have no "
            f"inbound link: {', '.join(sorted(orphans))}"
        )
    return spawns, spawned_by


def dependencies(body: str) -> list[tuple[str, str]]:
    """(tool, what happens without it) from the skill's own ## Dependencies table.
    Parsed rather than retyped, so the page cannot disagree with the skill."""
    m = re.search(r"^## Dependencies\b.*?\n(.*?)(?=\n## |\Z)", strip_comments(body), re.S | re.M)
    if not m:
        return []
    out = []
    for row in re.findall(r"^\|(.+?)\|(.+?)\|(.+?)\|\s*$", m.group(1), re.M):
        tool, _use, without = (c.strip() for c in row)
        if tool.lower() in ("tool", "") or set(tool) <= set("-: "):
            continue
        out.append((tool, without))
    return out


def cost_shape(body: str) -> str | None:
    m = re.search(r"\*\*Cost shape:\*\*\s*(.+?)\.\s", strip_comments(body), re.DOTALL)
    return re.sub(r"\s*\n>\s*", " ", m.group(1)).strip() if m else None


def clip(text: str, limit: int = 185) -> str:
    """Truncate at a word boundary. A hard slice leaves things like "confi" mid-word,
    which reads as a rendering bug rather than a summary."""
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0].rstrip(",;:·-")
    return cut + "…"


def example_block(meta: dict) -> list[str]:
    """Agent descriptions embed an <example> block — a worked scenario aimed at the
    model deciding whether to spawn it. Useful to a reader, but only as a clearly
    marked example; inline it read as garbled prose with \" artifacts."""
    d = meta.get("description", "").replace("\\n", "\n")
    if "<example>" not in d:
        return []
    body = d.split("<example>", 1)[1].split("</example>", 1)[0]
    ctx = re.search(r"Context:\s*(.+?)\n", body)
    # The description is a JSON-ish string, so its inner quotes arrive as \" — the
    # capture must exclude the backslashes or they render literally.
    user = re.search(r'user:\s*\\?"(.*?)\\?"\s*(?:\n|$)', body, re.S)
    why = re.search(r"<commentary>\s*(.+?)\s*</commentary>", body, re.S)
    out = ["", "## When it runs", ""]
    if ctx:
        out.append(f"*{ctx.group(1).strip().rstrip('.')}.*")
        out.append("")
    if user:
        q = user.group(1).strip().strip('\\').strip('"').strip('\\')
        out += [f"> {q}", ""]
    if why:
        out.append(re.sub(r"\s+", " ", why.group(1)).strip())
    return out


def returns_block(body: str) -> list[str]:
    """What the agent hands back. 25 of 26 agents document this, but under a dozen
    different headings — `Phase 4 — Return`, `Phase 5 — Return`, `Output`, `Report`.
    Only 6 document their INPUT, so that half is deliberately not attempted rather
    than shown for a quarter of the roster."""
    m = re.search(
        r"^## (?:Phase \d+ — )?(?:What you return|Return|Report|Output)\b[^\n]*\n(.*?)(?=\n## |\Z)",
        strip_comments(body), re.S | re.M | re.I)
    if not m:
        return []
    text = m.group(1).strip()
    if not text:
        return []
    return ["", "## What it returns", "", text]


# A pipeline diagram exists for some orchestrating skills; embed it on the pages of
# the agents that take part, so an agent shows where it sits in the whole run.
PIPELINE_DIAGRAMS = {
    n: f"pipeline-{n}.svg"
    for n in ("tech-blog", "pre-push-review", "capture-screenshots",
              "docs-site", "deps-upgrade", "test-gap-finder")
}

# Shown once on the index: how skills and agents relate at all.
OVERVIEW_DIAGRAM = "agents-overview.svg"


def summary(meta: dict) -> str:
    """The frontmatter description opens with trigger phrases aimed at the model
    ("Use this skill when the user asks to ..."). A reader wants what it DOES, so
    drop that clause and keep the rest."""
    # Everything from <example> on is a worked scenario for the model, not a
    # description. Rendered separately by example_block(); inline it produced
    # garbled prose full of escaped quotes.
    d = meta.get("description", "").split("<example>")[0].replace("\\n", " ")
    # Drop the trigger clause — "Use this skill when the user asks to 'x', 'y', or
    # wants z." is aimed at the model, not a reader. Cut through the first sentence
    # that ends the trigger list rather than leaving a mid-sentence fragment.
    d = re.sub(r"^Use this skill when the user asks to .*?\.\s*", "", d, flags=re.S)
    d = re.sub(r"^Use this agent (?:when the user asks to |to )", "", d, flags=re.S)
    d = d[:1].upper() + d[1:] if d else d
    # Boilerplate repeated on all 49 files — true, but noise on every single page.
    d = re.sub(r"\s*Works (?:in any|for any|with any)[^.]*\.\s*$", "", d)
    d = re.sub(r"\s*(?:Read-only;|Works on any)[^.]*\.\s*$", "", d)
    d = re.sub(r'^[^.]*?[,.]\s*(?=[A-Z])', "", d, count=1) if d.startswith('"') else d
    return d.replace("\\n", " ").strip()


def write(path: str, lines: list[str], src: Path | None = None):
    with mkdocs_gen_files.open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    if src:
        mkdocs_gen_files.set_edit_path(path, str(src.relative_to(ROOT)))


# --------------------------------------------------------------------------- build

skills, agents = load_sources()
spawns, spawned_by = derive_wiring(skills, agents)
by_class = defaultdict(list)
for name, s in skills.items():
    by_class[s["meta"].get("class", "unclassified")].append(name)

ICONS = {"review": "🔍", "authoring": "✍️", "workflow": "🔀", "pm": "📋", "social": "📣"}

# The pipeline each class runs, rendered as the chip row from the reference layout.
STAGES = {
    "review": ["snapshot", "review", "verdict"],
    "authoring": ["ingest", "draft", "propose"],
    "workflow": ["read diff", "draft", "propose"],
    "pm": ["ground", "preview", "create"],
    "social": ["fetch", "draft", "hand over"],
}


WRITE_TOOLS = {"Write", "Edit", "NotebookEdit"}


def agent_tools(m):
    """The declared allowlist, as a list. Required on every agent."""
    return [t.strip() for t in m.get("tools", "").split(",") if t.strip()]


def tools_cell(m):
    tools = agent_tools(m)
    if not tools:
        return "—"
    return " ".join(f"`{t}`" for t in tools)


def writes_note(m):
    """Say plainly whether this agent can touch the filesystem.

    Most cannot, and that is the interesting fact: 22 of 25 agents return their
    output for the SKILL to write. Someone reading an agent page should not have
    to infer that from a tool list.
    """
    if WRITE_TOOLS & set(agent_tools(m)):
        return [
            '!!! warning "Writes files"',
            "    This agent produces a file itself, rather than returning content for "
            "the skill to write — one of only two that do.",
            "",
        ]
    return [
        '!!! note "Returns content — does not write files"',
        "    Like all but two of the agents, this one returns its output to the skill "
        "that spawned it, and the **skill** writes the file. It holds no write tools, "
        "so it cannot modify the repo even if asked to.",
        "",
    ]


def card(name, s, cls, spawns_list, agents):
    """One skill as a card: icon + title, the stage-chip row, WHAT IT DOES /
    USES sections, and a footer naming the source. Mirrors the reference layout."""
    m = s["meta"]
    sub = m.get("subclass")
    stages = list(STAGES.get(cls, []))
    chips = []
    for i, st in enumerate(stages, 1):
        # A gate's final stage really can BLOCK — the one correct use of red here.
        klass = "nj-chip--block" if (sub == "gate" and i == len(stages)) else f"nj-chip--{i}"
        chips.append(f'<span class="nj-chip {klass}">{st}</span>')
    chip_row = '<span class="nj-arrow">→</span>'.join(chips)

    uses = " · ".join(f"<code>{a}</code>" for a in spawns_list) or "<em>runs inline</em>"
    cost = cost_shape(s["body"]) or "—"
    return f'''<div class="nj-card">
  <div class="nj-card__head">
    <span class="nj-card__icon">{ICONS.get(cls, "•")}</span>
    <p class="nj-card__title"><a href="../{name}/">/{name}</a></p>
  </div>
  <div class="nj-chips">{chip_row}</div>
  <p class="nj-label nj-label--does">What it does</p>
  <p class="nj-card__body">{clip(summary(m))}</p>
  <p class="nj-label nj-label--impact">Agents</p>
  <p class="nj-card__body">{uses}</p>
  <div class="nj-card__foot">{cost} · <code>v{m.get("version", "?")}</code></div>
</div>'''


def pipeline_order(skill_name, agent_list, skills_map):
    """Agents in the order the skill actually dispatches them, not alphabetically.

    A pipeline is a sequence — writer then fact-checker then reviewer — and listing
    it A-Z destroys the one piece of information that matters. Order is recovered
    from first mention in the skill body, which is where the steps are written.
    """
    body = strip_comments(skills_map[skill_name]["body"])
    return sorted(agent_list, key=lambda a: body.find(f"`{a}`"))


# Deliberately NOT guessing parallel-vs-sequential from the prose. A keyword scan
# said /tech-blog was "9 in parallel" because it mentions running two sub-steps
# concurrently — it is actually a 7-stage pipeline. A confidently wrong label is
# worse than none, and the skill's own page states the shape correctly.


nav_skills, nav_agents = [], []

# ---- one page per skill
for cls, (title, blurb) in CLASSES.items():
    members = sorted(by_class.get(cls, []))
    if not members:
        continue
    nav_skills.append(f"    * {title}")
    overview = f"skills/{cls}.md"
    cards = "\n".join(card(n, skills[n], cls, spawns[n], agents) for n in members)
    write(overview, [
        f"# {title} class",
        "",
        blurb.replace("{REPO_URL}", REPO_URL),
        "",
        f"**{len(members)} skill{'s' if len(members) != 1 else ''}**",
        "",
        '<div class="nj-grid" markdown="0">',
        cards,
        "</div>",
    ])
    nav_skills.append(f"        * [Overview]({overview})")
    for name in members:
        s = skills[name]
        m = s["meta"]
        sub = m.get("subclass")
        page = f"skills/{name}.md"
        out = [
            f"# `/{name}`",
            "",
            f"!!! abstract \"{title} class{' · ' + sub if sub else ''}\"",
            "    " + blurb.replace("{REPO_URL}", REPO_URL),
            "",
            summary(m),
            "",
            "## At a glance",
            "",
            "| | |",
            "|---|---|",
            f"| Run it | `/{name}` |",
            f"| Class | `{cls}`{' · `' + sub + '`' if sub else ''} |",
            f"| Version | `{m.get('version', '—')}` |",
            f"| Author | {m.get('author', '—')} |",
        ]
        cost = cost_shape(s["body"])
        if cost:
            out.append(f"| Cost | {cost} |")
        deps = dependencies(s["body"])
        if deps:
            out.append("| Needs | " + " · ".join(f"{t}" for t, _ in deps) + " |")
        out.append(
            f"| Source | [`skills/{name}/SKILL.md`]({REPO_URL}/skills/{name}/SKILL.md) |"
        )
        if deps:
            out += ["", "### What it needs, and what happens without it", "",
                    "Every tool is detected at runtime — none is installed for you.", "",
                    "| Tool | Without it |", "|---|---|"]
            out += [f"| {t} | {w} |" for t, w in deps]
        if name in PIPELINE_DIAGRAMS:
            out += ["", "## The pipeline", "",
                    f"![/{name} pipeline](../assets/{PIPELINE_DIAGRAMS[name]})"]
        out += ["", "## Agents it spawns", ""]
        if spawns[name]:
            out += [f"- [`{a}`](../agents/{a}.md) — {clip(summary(agents[a]['meta']), 110)}"
                    for a in spawns[name]]
        else:
            out.append("This skill spawns no subagents — it runs inline.")
        out += [
            "",
            "## The procedure",
            "",
            "The executable steps live in the skill file itself and are deliberately "
            "not reproduced here: they are instructions to the model at runtime, not "
            "documentation.",
            "",
            f"[Read `{name}/SKILL.md` →]({REPO_URL}/skills/{name}/SKILL.md)",
        ]
        write(page, out, s["path"])
        nav_skills.append(f"        * [/{name}]({page})")

pipelines = sorted(
    ((n, spawns[n]) for n in skills if len(spawns[n]) > 1),
    key=lambda kv: (-len(kv[1]), kv[0]),
)
grouped = {a for _, members in pipelines for a in members}

for skill_name, members in pipelines:
    ordered = pipeline_order(skill_name, members, skills)
    sk = skills[skill_name]

    # The orchestrator gets its OWN page. Without one the group header was a dead
    # text label — /docs-site had pages for docs-architect and docs-designer but
    # nothing for the thing that runs them. This page is the orchestrator's view, so
    # the pipeline diagram lives HERE and on no sub-agent page.
    #
    # It is a distinct page from skills/<name>.md, not a second listing of it —
    # listing the same file twice is what made mkdocs silently drop it from Skills.
    orch = f"orchestrators/{skill_name}.md"
    out = [
        f"# `/{skill_name}` — orchestrator",
        "",
        f"Runs **{len(ordered)} agents**. " + summary(sk["meta"]),
        "",
    ]
    if skill_name in PIPELINE_DIAGRAMS:
        out += ["## The pipeline", "",
                f"![/{skill_name} pipeline](../assets/{PIPELINE_DIAGRAMS[skill_name]})", ""]
    out += ["## What it runs, in order", "", "| # | Agent | What it does |", "|---|---|---|"]
    for i, a in enumerate(ordered, 1):
        out.append(f"| {i} | [`{a}`](../agents/{a}.md) | {clip(summary(agents[a]['meta']), 90)} |")
    cost = cost_shape(sk["body"])
    out += ["", "## At a glance", "", "| | |", "|---|---|",
            f"| Class | `{sk['meta'].get('class','—')}` |",
            f"| Cost | {cost or '—'} |",
            f"| Skill page | [`/{skill_name}`](../skills/{skill_name}.md) |",
            f"| Source | [`skills/{skill_name}/SKILL.md`]({REPO_URL}/skills/{skill_name}/SKILL.md) |"]
    write(orch, out, sk["path"])

    nav_agents.append(f"    * [/{skill_name}]({orch})")
    for name in ordered:
        nav_agents.append(f"        * [{name}](agents/{name}.md)")


for name in sorted(agents):
    a = agents[name]
    m = a["meta"]
    page = f"agents/{name}.md"
    out = [
        f"# `{name}`",
        "",
        summary(m),
        "",
        "## At a glance",
        "",
        "| | |",
        "|---|---|",
        f"| Model | {'`' + m['model'] + '`' if m.get('model') else "inherits the session's"} |",
        f"| Tools | {tools_cell(m)} |",
        f"| Author | {m.get('author', '—')} |",
        f"| Source | [`agents/{name}.md`]({REPO_URL}/agents/{name}.md) |",
        "",
        *writes_note(m),
        *example_block(m),
        *returns_block(a["body"]),
        "",
        "## Spawned by",
        "",
        "!!! tip \"Derived, not declared\"",
        "    No agent file records which skills call it — this list is recovered from "
        "the skill definitions at build time, so it cannot go stale.",
        "",
    ]
    out += [f"- [`/{s}`](../skills/{s}.md)" for s in sorted(spawned_by[name])]
    # No pipeline diagram here — it is the orchestrator's view, not this agent's, and
    # repeating it on 21 sub-agent pages was duplication. Link to it instead.
    for sk in sorted(spawned_by[name]):
        if sk in PIPELINE_DIAGRAMS:
            out += ["", f"See the [`/{sk}` pipeline](../orchestrators/{sk}.md) for where "
                    "this fits in the whole run."]
    out += ["", f"[Read `agents/{name}.md` →]({REPO_URL}/agents/{name}.md)"]
    write(page, out, a["path"])

# ---- architecture diagrams: copied into the VIRTUAL tree at build time, never
# onto disk. A real copy under docs_src/ would be a second file that can drift from
# docs/architecture/, which is exactly what this build is meant to prevent.
for svg in sorted((ROOT / "docs" / "architecture").glob("*.svg")):
    with mkdocs_gen_files.open(f"assets/{svg.name}", "wb") as f:
        f.write(svg.read_bytes())

# ---- assemble the nav: agents first, then skills
# ---- agents, grouped by the WORKFLOW that orchestrates them
#
# Class was the wrong axis: it says what an agent IS, not what runs together. What a
# reader needs is the workflow — /tech-blog's 9-agent pipeline is one thing, and
# seeing its members in dispatch order is the whole point.
#
# Agents never spawn agents in this repo (verified: the only agent-to-agent mentions
# are prose cross-references like "that's `dependency-reviewer`'s job"). The skill is
# always the orchestrator, so the hierarchy is exactly one level deep.
# Only skills with a REAL pipeline (2+ agents) earn a group. Grouping all 17
# orchestrators produced 17 sections, 10 of them holding a single agent — a wall of
# expandable nodes for no benefit. The rest go in one flat list.
#
# No "Workflow" child link either: that page already lives under Skills, and listing
# it twice under two labels is what made the nav feel like it jumped around. The
# agent's own page links back to its spawner.
solo = sorted(a for a in agents if a not in grouped)
if solo:
    nav_agents.append("    * Single-agent skills")
    for name in solo:
        nav_agents.append(f"        * [{name}](agents/{name}.md)")

nav = ["* [Home](index.md)", "* Agents"] + nav_agents + ["* Skills"] + nav_skills

# ---- harness section
nav.append("* Harness")
for slug, title in [("overview", "Overview"), ("checks", "What is checked"),
                    ("contracts", "Class contracts")]:
    nav.append(f"    * [{title}](harness/{slug}.md)")

# ---- index
counts = {c: len(by_class.get(c, [])) for c in CLASSES}

# Derived, not hardcoded: an agent gaining or losing a write tool changes this
# page on the next build rather than leaving a stale number behind.
writers = sorted(
    n for n, a in agents.items() if WRITE_TOOLS & set(agent_tools(a["meta"]))
)
write("index.md", [
    "# nj-agents",
    "",
    "A project-agnostic toolkit of Claude Code **skills and agents** covering the "
    "software development lifecycle. Install once; invoke with `/name` in any git "
    "repo, any stack, any language.",
    "",
    f"**{len(skills)} skills · {len(agents)} agents · {len(CLASSES)} classes**",
    "",
    "## The classes",
    "",
    "| Class | Skills | What it promises |",
    "|---|---|---|",
] + [
    f"| [{CLASSES[c][0]}](skills/{sorted(by_class[c])[0]}.md) | {counts[c]} | "
    f"{CLASSES[c][1].replace(chr(123)+'REPO_URL'+chr(125), REPO_URL).split('. ')[0]}. |"
    for c in CLASSES if counts[c]
] + [
    "",
    "## How it fits together",
    "",
    f"![How skills and agents relate](assets/{OVERVIEW_DIAGRAM})",
    "",
    "## What an agent is allowed to do",
    "",
    f"A skill orchestrates; an agent does one job and hands the result back. "
    f"**{len(agents) - len(writers)} of the {len(agents)} agents cannot write files at all** — they return "
    "their output and the *skill* writes it. That is not an accident of "
    "configuration: each agent's body says so, and its declared tools match.",
    "",
    f"Only **{len(writers)}** hold a write tool, because each genuinely produces a file "
    "itself:",
    "",
] + [
    f"- [`{w}`](agents/{w}.md)" for w in sorted(writers)
] + [
    "",
    "Every agent declares an explicit `tools:` allowlist. That is required rather "
    "than optional, and for portability rather than taste: Claude Code and Cursor "
    "read a missing key as *inherit every tool*, but Gemini CLI reads it as *no "
    "tools*, so the agent loads unable to act. An explicit list is the only "
    "spelling that means the same thing on every runner.",
    "",
    "`check.sh` enforces both halves — the key must be present, and an agent whose "
    "body claims to be read-only may not declare a write tool. The two statements "
    "of the same contract cannot drift apart.",
    "",
    "## Always current, by construction",
    "",
    "Every skill and agent here is **written and maintained by hand** — the procedures, "
    "the safety rails, the conventions each one follows. This site is the *presentation* "
    "of those files, rebuilt from them on every commit.",
    "",
    "That distinction is what makes it trustworthy:",
    "",
    "- **A page cannot disagree with the thing it documents.** It is rendered from "
    "`skills/*/SKILL.md` and `agents/*.md` at build time, so a change to a skill is a "
    "change to its page.",
    "- **The wiring is derived, not retyped.** Which agents a skill spawns — and which "
    "skills spawn a given agent — is recovered from the definitions themselves.",
    "- **A broken reference fails the build.** A skill pointing at an agent that does "
    "not exist stops the site from publishing rather than shipping a dead link.",
    "",
    "Built with the help of Claude, and verified the same way everything else here is: "
    "a validator that runs on every push, and a behavioural suite that asserts what "
    "these skills must never do.",
])

with mkdocs_gen_files.open("SUMMARY.md", "w") as f:
    f.write("\n".join(nav) + "\n")
