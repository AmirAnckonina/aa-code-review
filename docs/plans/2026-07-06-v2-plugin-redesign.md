# aa-code-review v2 Plugin Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild aa-code-review as a Claude Code plugin with a 3-reviewer background-dispatch engine and two documented adapter seams, per `docs/specs/2026-07-06-v2-plugin-redesign-design.md`.

**Architecture:** A thin `/aa-review` command relays to the `aa-review-engine` skill (top level). The engine acquires diff scope (context-source seam), dispatches 3 read-only `aa-reviewer` subagents with `run_in_background=true`, synthesizes findings, and emits a 3-layer report (report-sink seam). All artifacts are markdown; the plugin manifest replaces symlink install.

**Tech Stack:** Claude Code plugin (plugin.json, skills/commands/agents auto-discovery, `${CLAUDE_PLUGIN_ROOT}`), git, bash.

## Global Constraints

- Everything lands on branch `v2-plugin-redesign`; `main` is frozen. Repo root: `~/repositories/agentic-code-review/aa-code-review`.
- 3 severity tiers only (🔴 CRITICAL / 🟡 IMPORTANT / 🔵 SUGGESTION). No POSITIVE tier, ever.
- Verdict math: any 🔴 → BLOCKER; any 🟡 (no 🔴) → NEEDS WORK; else SHIP IT.
- Reviewer canonical names + tags (exact): `Bugs` (Correctness & Reliability), `Security` (Security & Input Safety), `Quality` (Design, Performance & Testing, Readability).
- Finding IDs: `CRT-{n}` / `IMP-{n}` / `SUG-{n}`.
- Reserved tokens in rule names/titles: `[` `]` `,` ` — ` `` ` `` `|` `"`.
- One owner per fact: finding-line grammar + severity tiers + CRITICAL gate live ONLY in `skills/aa-review-engine/references/reviewer-prompt.md`; report assembly (IDs, verdict, layers, truncation, coverage table) lives ONLY in `references/report-format.md`. No third copy anywhere.
- No `~/.claude/...` hardcoded paths anywhere; use `${CLAUDE_PLUGIN_ROOT}/...` for absolute references, repo-relative otherwise.
- Per-reviewer cap: max 10 findings, severity-first.
- Base-ref chain (exact order): explicit `base=` → `@{upstream}` → `origin/HEAD` → `origin/main` → `origin/develop` → `origin/master`.
- Commit after every task; messages follow existing repo style (`feat:`/`docs:`/`refactor:` prefixes).

---

### Task 1: Plugin scaffold + read-only reviewer agent

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json` (lets `claude plugin marketplace add <local path>` resolve this repo)
- Create: `agents/aa-reviewer.md`
- Delete: `install.sh`, `agents/.gitkeep`

**Interfaces:**
- Produces: subagent type `aa-reviewer` (read-only tools) used by Task 5's dispatch step; plugin identity `aa-code-review` v2.0.0.

- [ ] **Step 1: Write the manifest**

`.claude-plugin/plugin.json`:

```json
{
  "name": "aa-code-review",
  "version": "2.0.0",
  "description": "Multi-reviewer agentic code review for the current branch's diff. 3 parallel read-only reviewers (Bugs, Security, Quality), repo-specific rules, deterministic verdict, 3-layer report.",
  "author": { "name": "Amir Anckonina" }
}
```

- [ ] **Step 1b: Write the marketplace manifest**

`.claude-plugin/marketplace.json`:

```json
{
  "name": "aa-tools",
  "owner": { "name": "Amir Anckonina" },
  "plugins": [
    { "name": "aa-code-review", "source": "./", "description": "Multi-reviewer agentic code review" }
  ]
}
```

- [ ] **Step 2: Write the reviewer agent**

`agents/aa-reviewer.md`:

```markdown
---
name: aa-reviewer
description: Read-only code reviewer dispatched by the aa-review-engine skill. Do not invoke directly — it receives its charter, checklist, and pre-read code from the engine's dispatch prompt.
tools: Read, Grep, Glob, Bash
---

You are a focused code reviewer. Your entire assignment — charter, checklist path, repo rules, pre-read code, diff, and output grammar — arrives in the dispatch prompt. Follow it exactly.

Operating rules:

- **Read-only.** Your tool list has no write access by design. Use Bash only for read-only inspection (`git log/show/diff`, `grep`/`rg`, `ls`, `wc`). Never run state-changing commands.
- **The code is pre-read.** The dispatch prompt contains every changed file and the diff. Do not re-read those files or re-run `git diff`. Use tools only to read ADDITIONAL surrounding context (imports, callers, related modules) — aim for at most ~6 tool calls.
- **Diff lines only.** Raise findings only on lines that appear in the diff. Untouched pre-existing code is out of scope.
- **Return findings only.** No questions to the user, no fixes applied, no praise sections.
```

- [ ] **Step 3: Delete install.sh and agents/.gitkeep**

```bash
cd ~/repositories/agentic-code-review/aa-code-review
git rm install.sh agents/.gitkeep
```

- [ ] **Step 4: Verify**

Run: `cat .claude-plugin/plugin.json | jq .name` → expect `"aa-code-review"`.
Run: `grep -c 'tools: Read, Grep, Glob, Bash' agents/aa-reviewer.md` → expect `1`.
Run: `ls install.sh 2>&1` → expect "No such file".

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: plugin manifest + read-only aa-reviewer agent; drop symlink installer"
```

---

### Task 2: Reviewer checklists (6 lenses → 3) + coding-standards demotion

**Files:**
- Create: `skills/aa-review-engine/references/bugs.md`
- Create: `skills/aa-review-engine/references/security.md`
- Create: `skills/aa-review-engine/references/quality.md`
- Create: `skills/aa-review-engine/references/coding-standards.md` (moved from `skills/aa-coding-standards/SKILL.md`)

**Interfaces:**
- Consumes: the 6 lens files under `skills/aa-review-lenses/references/` (still present until Task 6).
- Produces: checklist filenames `bugs.md` / `security.md` / `quality.md` consumed by Task 4's prompt template and Task 5's dispatch table.

- [ ] **Step 1: Create the merged checklists**

Each new file = a 4-line intro (below, verbatim, with the right name) followed by the **complete section content** of its source lens files, concatenated in the order listed, copied verbatim (headings preserved as `##`). Drop only: each source file's title line and any "Output format"/"Boundaries" trailer sections (the dispatch prompt owns those now).

Intro template (fill `<TAG>`, `<CHARTER>`, `<SOURCES>`):

```markdown
# <TAG> reviewer checklist

Charter: <CHARTER>. Apply every check below against the changed lines.
A check is "clean" only if you looked and found nothing — silence is not clearance.
(Merged from the v1 <SOURCES> lenses; no checks dropped.)
```

| Target | TAG | CHARTER | Source files (in order) |
|---|---|---|---|
| `bugs.md` | Bugs | Correctness & Reliability — logic, edge cases, null safety, error handling, failure modes, operations | `correctness-lens.md`, `reliability-lens.md` |
| `security.md` | Security | Security & Input Safety — injection, authz/authn, secrets, boundary validation | `security-lens.md` |
| `quality.md` | Quality | Design, Performance & Testing, Readability — SOLID, encapsulation, interfaces, test coverage, performance, naming, comments, consistency | `design-lens.md`, `perf-testing-lens.md`, `readability-lens.md` |

- [ ] **Step 2: Move coding standards to a reference doc**

```bash
mkdir -p skills/aa-review-engine/references
git mv skills/aa-coding-standards/SKILL.md skills/aa-review-engine/references/coding-standards.md
```

Then edit `coding-standards.md`: delete the YAML frontmatter block entirely and put this header in its place:

```markdown
# Coding standards — 13 base principles (editing-time reference)

> Not loaded at review runtime. The three reviewer checklists (`bugs.md`, `security.md`, `quality.md`) are the operational copies of these principles. When editing a principle here, port the change into the affected checklist — and vice versa.
> Hard numeric caps below (file/function length, coverage %) are DEFAULTS — a repo's `.aa-review/rules.md` overrides them.
```

- [ ] **Step 3: Verify**

Run: `grep -c '^## ' skills/aa-review-engine/references/bugs.md` → expect ≥ (sum of `##` sections in correctness + reliability lenses, minus dropped trailers; count sources first with `grep -c '^## ' skills/aa-review-lenses/references/correctness-lens.md skills/aa-review-lenses/references/reliability-lens.md`).
Run: `grep -c 'DEFAULTS' skills/aa-review-engine/references/coding-standards.md` → expect `1`.
Run: `ls skills/aa-coding-standards/ 2>/dev/null` → expect only empty dir or nothing (remove leftover dir with `rmdir` if empty).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "refactor: fold 6 lens checklists into 3 reviewer charters; demote coding-standards to reference"
```

---

### Task 3: report-format.md — single owner of report assembly

**Files:**
- Create: `skills/aa-review-engine/references/report-format.md`

**Interfaces:**
- Consumes: reviewer tags `Bugs`/`Security`/`Quality` (Task 2), finding-line grammar defined in Task 4's `reviewer-prompt.md`.
- Produces: report templates + synthesis rules consumed verbatim by Task 5's engine Steps 4–6.

- [ ] **Step 1: Write the file**

Derive from `skills/aa-review-lenses/SKILL.md` (still present until Task 6): keep its **Severity-binding note, Verdict Rules, Finding IDs, Reviewer coverage table, Review Report Format (3 layers), truncation rule, ordering rule** — with these exact changes:

1. Frontmatter: none — this is a reference file, not a skill. Title: `# Report format — assembly, verdict, layers (single source of truth)`.
2. Add pointer line under the title: `Finding-line grammar, severity tiers, and the CRITICAL gate are owned by reviewer-prompt.md — this file starts where reviewer output ends.`
3. Delete: "Requires aa-coding-standards…halt" block, "Challenge Methodology", "The 6 Lenses" table, "Subagent Configuration", "Subagent Output Format", "Failure Handling", the 5 cross-check pairs. (These move to the prompt template, the engine, or die.)
4. Severity Levels section: do NOT copy tier definitions (they move to reviewer-prompt.md). KEEP only the "Severity binding from a cited authority" note (`[CRITICAL]` rule → 🔴, no downgrade; unmarked rule → per-instance judgment) — the engine needs it for promotion.
5. Lens Coverage table → **Reviewer Coverage** table with exactly 3 rows (`Bugs`, `Security`, `Quality`); columns unchanged (`Reviewer | Model | Status | Findings | Top Finding`). Status values: `✅ Clean` / `🔵 N suggestions` / `🟡 N important` / `🔴 N critical` / `❌ NOT REVIEWED`. (The word "positives" must not appear.)
6. Report template: replace "6 Sonnet lenses" phrasing in the Activity Summary example with "3 Sonnet reviewers"; `show <Lens>` → `show <Reviewer>` everywhere; ordering rule becomes: severity → reviewer order (Bugs, Security, Quality) → file path → line.
7. Add a **Synthesis** section (replaces cross-check pairs), verbatim:

```markdown
## Synthesis (engine, post-collection)

- **Systemic clustering:** if 3+ findings across reviewers land on the same file/module/abstraction, replace them with ONE architectural finding naming the cluster (severity = highest of the cluster). Do not speculate about branch scope or PR size — those are author decisions, not findings.
- **Dedupe:** same defect reported by 2+ reviewers → keep the highest severity, merge mechanisms, note the merge in the Activity Summary count.
- **[CRITICAL] promotion:** a finding citing a `[CRITICAL]`-tagged repo rule but emitted below 🔴 is promoted to 🔴, plus a separate 🟡 finding recording the reviewer's protocol deviation.
- **Cap note:** if a reviewer reported hitting its 10-finding cap, add one Activity Summary line: "<Reviewer> hit the finding cap — coverage of low-severity items may be partial."
```

- [ ] **Step 2: Verify**

Run: `grep -c 'positives' skills/aa-review-engine/references/report-format.md` → expect `0`.
Run: `grep -c 'Reviewer Coverage' skills/aa-review-engine/references/report-format.md` → expect ≥1.
Run: `grep -cE 'lens|Lens' skills/aa-review-engine/references/report-format.md` → expect `0` (the word "lens" is gone from v2 vocabulary).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: report-format.md — single owner of report assembly, verdict, layers"
```

---

### Task 4: reviewer-prompt.md — the one dispatch template (cache-ordered)

**Files:**
- Create: `skills/aa-review-engine/references/reviewer-prompt.md`

**Interfaces:**
- Consumes: checklist filenames from Task 2.
- Produces: the template + slot names (`[BRANCH]`, `[BASE_REF]`, `[MERGE_BASE_SHORT]`, `[FILE_LIST]`, `[RECONSTRUCTED_INTENT]`, `[CLAUDE_MD_SECTIONS]`, `[REPO_RULES]`, `[PRE_READ_CODE]`, `[DIFF]`, `[REVIEWER_TAG]`, `[CHECKLIST_PATH]`) consumed by Task 5's Step 3. Owns finding-line grammar + severity tiers + CRITICAL gate.

- [ ] **Step 1: Write the file**

Full content:

````markdown
# Reviewer dispatch prompt template

The engine fills the `[SLOTS]` and dispatches one copy per reviewer.

**Cache invariant — do not reorder:** everything above the `## Your Assignment` marker MUST be byte-identical across the 3 dispatches (shared prefix → prompt-cache eligible). Reviewer-specific content goes ONLY below the marker.

---

```
You are a code reviewer. Your job is to break the code, not confirm it works — the author already believes it works; your value is finding what they missed.

## Context
- Branch: [BRANCH] (vs. [BASE_REF], merge-base [MERGE_BASE_SHORT])
- Changed files: [FILE_LIST]
- Intent: [RECONSTRUCTED_INTENT]
- Project conventions: [CLAUDE_MD_SECTIONS]

## Repo-Specific Rules
Defined by the repo's team. They extend the base checklists and OVERRIDE them on conflict. Findings traceable to a repo rule cite the rule name.

[REPO_RULES]

## Pre-Read Code
[PRE_READ_CODE]

## Diff
[DIFF]

## Severity Tiers

🔴 CRITICAL — merging as-is causes incorrect data, data loss, security breach, or production outage. Qualifies ONLY when all three hold: (1) reachable on a real shipped path, (2) violates a top-tier invariant (security boundary, data integrity, outage class, secret leakage), (3) no upstream mitigation bounds it. If ANY is uncertain → downgrade. When in doubt, downgrade.

🟡 IMPORTANT — real risk bounded by scope; fix before broader rollout, not a merge blocker. Includes every "almost critical" where one 🔴 criterion is uncertain.

🔵 SUGGESTION — optimizations, theoretical edges, style, code health. Author may defer.

Severity is a per-instance call (blast radius + reachability), not a fixed rule→severity map. 3 tiers only — no praise findings of any kind.

## 🔴 Gate — mandatory before emitting any 🔴
The mechanism field's FIRST sentence must be:
`(reachable on: <file>:<line>; violates: <named invariant>; no mitigation: <named missing check>)`
Each slot needs concrete, specific content — generic fills (`yes`, `security`, `see above`) FAIL the gate and the finding MUST downgrade to 🟡.
Exception: a finding citing a `[CRITICAL]`-tagged repo rule is 🔴 by the rule's authority — no articulation required, no downgrade allowed.

## Output Format
Use actual Unicode emoji (🔴 🟡 🔵), never :shortcodes:. Write the literal text <ID> — the engine assigns real IDs.

### Findings
🔴 <ID> [REVIEWER_TAG_LITERAL] [⚠️ Repo rule: <name>]? — file:line — title ≤80 chars | mechanism: what's wrong, why it matters, impact, suggested fix
🟡 <ID> [REVIEWER_TAG_LITERAL] — file:line — title | mechanism
🔵 <ID> [REVIEWER_TAG_LITERAL] — file:line — title | mechanism

Token rules:
- Exactly ONE ` | ` separator per line splits title from mechanism. Lines without it degrade to title-only.
- `[⚠️ Repo rule: <name>]` appears ONLY when citing a named rule from the repo rules above — name verbatim, no quotes. Omit for judgment/base-checklist findings; never write a rule-cite verb in prose.
- ` — ` (em-dash) separates tag cluster / file:line / payload. Single space between consecutive `[...]` tags.
- Do not repeat your reviewer tag or the words "Violates"/"per rule" inside title or mechanism.
- **Cap: at most 10 findings, severity-first.** If you found more, keep the top 10 and state in your Summary: "Cap hit — N lower-severity findings omitted."

### Summary
2–3 sentences: overall assessment from your charter's perspective. If clean, say what you checked and why it looks good.

## Your Assignment
- Reviewer tag: [REVIEWER_TAG] — use it verbatim in every finding line (replaces REVIEWER_TAG_LITERAL above).
- Read your checklist NOW, then apply every check to the changed lines: [CHECKLIST_PATH]
```
````

- [ ] **Step 2: Verify**

Run: `grep -c 'Your Assignment' skills/aa-review-engine/references/reviewer-prompt.md` → expect `2` (invariant note + marker).
Run: `grep -n 'REVIEWER_TAG\|CHECKLIST_PATH' skills/aa-review-engine/references/reviewer-prompt.md | tail -2` → both hits below the `## Your Assignment` marker line number.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: single cache-ordered reviewer dispatch template owning grammar + severity gate"
```

---

### Task 5: aa-review-engine SKILL.md — the orchestrator rewrite

**Files:**
- Create: `skills/aa-review-engine/SKILL.md`

**Interfaces:**
- Consumes: `aa-reviewer` agent (Task 1); `references/{bugs,security,quality}.md` (Task 2); `references/report-format.md` (Task 3); `references/reviewer-prompt.md` + its slot names (Task 4).
- Produces: skill name `aa-review-engine` invoked by Task 6's command.

- [ ] **Step 1: Write the skill**

Full content:

````markdown
---
name: aa-review-engine
description: |
  Code-review engine. Use when: "/aa-review", "review the current branch",
  "run the code review". Runs at TOP LEVEL (needs the Agent tool) — never
  as a subagent.
user-invocable: true
---

You are the **aa-review-engine** — a diff-scoped, read-only, advisory code-review orchestrator. You run at top level and dispatch 3 background reviewer subagents.

**Use your tools — a turn with 0 tool uses is a failed turn.** Raw arguments: `$ARGUMENTS`.

## Invariants

- **Diff-only:** review changed lines vs. the base ref, never the whole repo.
- **Read-only:** never modify files; git reads only (`diff`, `log`, `status`, `merge-base`, `rev-parse`, `ls-files`, `check-attr`, `symbolic-ref`).
- **Advisory:** flag and categorize; the author decides. 3 severity tiers, no praise findings.
- **Adapter seams:** scope acquisition (Step 1) and report emission (Step 6) are the only adapter-specific steps. This version implements `local` for both. Any other `adapter=` value → refuse once: *"Adapter `<name>` not supported. Implemented: `local`. The adapter contract for new integrations is in adapters/README.md."*

## Step 0 — Context & args

1. Read (those that exist): `CLAUDE.md` at repo root, `.claude/context.md`, `.aa-review/rules.md` (→ `REPO_RULES`; missing → `(none)`). Repo rules extend the base checklists and override on conflict; `[CRITICAL]` in a rule heading is the only severity marker.
2. Parse `$ARGUMENTS`: `--deep` → `REVIEWER_MODEL=opus` (default `sonnet`); `base=<ref>` → `BASE_REF`; `adapter=<name>` → `ADAPTER` (default `local`); remaining free text → focus areas.

## Step 1 — Scope (context-source seam: local)

Resolve `BASE_REF`, first that succeeds — record which as `RESOLUTION`:
1. explicit `base=` arg (normalize to `origin/<ref>` if bare name and that resolves; unresolvable → abort: *"Cannot resolve base ref `<ref>`."*)
2. `git rev-parse --abbrev-ref --symbolic-full-name @{upstream}` (ignore if it points at the current branch's own remote copy with no divergence semantics — i.e., use it only when it differs from `origin/<current-branch>`)
3. `git symbolic-ref refs/remotes/origin/HEAD` → the branch it names
4. `origin/main`, then `origin/develop`, then `origin/master` (via `git rev-parse --verify`)
5. nothing resolves → abort: *"Cannot determine base ref. Re-run with `base=<ref>`."*

`RESOLUTION` ∈ {`explicit base= arg`, `branch upstream`, `origin/HEAD`, `fallback origin/<name>`}.

Then collect, with `MERGE_BASE=$(git merge-base HEAD "$BASE_REF")`:
- committed files: `git diff --name-only "$MERGE_BASE"..HEAD` (tag `committed`)
- working-tree mods: `git diff --name-only "$MERGE_BASE"` minus the committed list (tag `working`)
- untracked: `git ls-files --others --exclude-standard` (tag `untracked`)
- full diff: `git diff "$MERGE_BASE"`; for untracked files synthesize `+++ b/<path>` entries with full content as added lines
- **binary filter:** drop files with `-` in `git diff --numstat` columns; drop untracked matching `git check-attr binary` or extension deny-list (`.png .jpg .jpeg .gif .pdf .zip .tar .gz .ico .woff .woff2 .ttf .eot .so .dylib .dll .exe .class .jar .wasm`)
- **hidden-dir filter:** drop any path with a dot-directory segment (`.claude/`, `.github/`, …). Top-level dot-FILES (`.gitignore`, `.editorconfig`) stay in scope.
- pre-read every surviving file once (HEAD content for `committed`, working-tree for `working`/`untracked`)

Empty scope after filtering → stop: report the three bucket counts so the user sees why.

## Step 2 — Intent

Focus args provided → they are the primary review focus. Otherwise infer from branch name, recent commit subjects, and a skim of 2–3 key changed files. Then print exactly this summary (no confirmation gate — proceed unless the user interjects):

*"Reviewing `<branch>` against `<BASE_REF>` (resolved via: <RESOLUTION>). <N> files, ±<M> lines. Intent: <1–2 lines>. Scope: <C> committed + <W> working + <U> untracked; skipped <B> binary, <H> hidden-dir. Repo rules: <line count or none>. Launching 3 reviewers (<REVIEWER_MODEL>) in background."*

## Step 3 — Dispatch 3 reviewers (background)

Build the shared prompt block ONCE from `references/reviewer-prompt.md` (fill every slot above `## Your Assignment`; the block must be byte-identical across dispatches). Then issue 3 `Agent` calls — background mode is what makes them concurrent, so do NOT wait for one before dispatching the next:

| REVIEWER_TAG | CHECKLIST_PATH | description |
|---|---|---|
| `Bugs` | `${CLAUDE_PLUGIN_ROOT}/skills/aa-review-engine/references/bugs.md` | Bugs reviewer |
| `Security` | `${CLAUDE_PLUGIN_ROOT}/skills/aa-review-engine/references/security.md` | Security reviewer |
| `Quality` | `${CLAUDE_PLUGIN_ROOT}/skills/aa-review-engine/references/quality.md` | Quality reviewer |

Each call: `Agent(subagent_type="aa-reviewer", description="<from table>", model=REVIEWER_MODEL, run_in_background=true, prompt=<filled template>)`. If the `aa-reviewer` type is unavailable in this session, fall back to `subagent_type="general-purpose"` and note it in the Activity Summary.

While reviewers run, do NOTHING else — no inline checklist application, no grepping for issues yourself. Your review work is Steps 4–6 synthesis only.

## Step 4 — Collect

Collect each reviewer's final message as its background task completes. Parse finding lines (`<emoji> <ID> [<Tag>] …`); lines missing the ` | ` separator degrade to title-only (one Activity Summary warning per offending reviewer). A reviewer that errored or returned no parseable output: retry ONCE with the identical prompt (foreground is fine for a single retry). Still failing → mark `❌ NOT REVIEWED`. If ≥2 of 3 reviewers are NOT REVIEWED → abort: *"Aborting — <N> of 3 reviewers failed; remaining coverage can't support a verdict. Re-run, or narrow the diff with `base=<ref>`."*

## Step 5 — Synthesize

Apply `references/report-format.md` → **Synthesis**: systemic clustering, dedupe, `[CRITICAL]` promotion, cap notes. Then assign IDs (`CRT-/IMP-/SUG-`, per-severity sequential) and compute the verdict (any 🔴 → BLOCKER; any 🟡 → NEEDS WORK; else SHIP IT). Never silently downgrade a 🔴.

## Step 6 — Emit (report-sink seam: local)

Render Layer 1 exactly per `references/report-format.md` → Review Report Format, to the terminal. Serve `expand <ID>` (Layer 2) and `show <Reviewer>` (Layer 3) follow-ups from the collected data — no re-reads.

## Boundaries

MUST NOT: modify files; run git lifecycle commands (commit/push/merge/rebase/reset/checkout); post to any remote; approve silently (if zero findings, state per reviewer what was checked).
CAN: read any repo file; read-only git; run linters/tests for evidence; sketch fixes inside findings.

## Memory

None by design. Persistent learning lives in `.aa-review/rules.md` (human-curated, citeable). Findings cite code evidence or a named rule — never agent-internal state.
````

- [ ] **Step 2: Verify**

Run: `grep -c 'run_in_background' skills/aa-review-engine/SKILL.md` → expect ≥1.
Run: `grep -c 'maxTurns\|exactly 6\|ONE message' skills/aa-review-engine/SKILL.md` → expect `0`.
Run: `grep -c '~/.claude' skills/aa-review-engine/SKILL.md` → expect `0`.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: aa-review-engine — 3-reviewer background dispatch, adapter seams, base-ref chain"
```

---

### Task 6: Thin command, delete v1 skills, de-hardcode rules skills

**Files:**
- Modify: `commands/aa-review.md` (full rewrite)
- Delete: `skills/aa-review-orchestrator/`, `skills/aa-review-lenses/`, `skills/aa-coding-standards/` (any remnants)
- Modify: `skills/aa-init-rules/SKILL.md`, `skills/aa-init-rules/references/rule-shape.md`, `skills/aa-edit-rules/SKILL.md`, `skills/aa-edit-rules/references/edit-operations.md` (path + name fixes)

**Interfaces:**
- Consumes: skill name `aa-review-engine` (Task 5).

- [ ] **Step 1: Rewrite the command**

`commands/aa-review.md`, full content:

```markdown
---
description: "Parallel multi-reviewer code review of the current branch's diff vs. trunk"
argument-hint: "[focus areas] [base=<ref>] [--deep] [adapter=<name>]"
---

Use the Skill tool to invoke the **aa-review-engine** skill with `$ARGUMENTS` passed verbatim. The skill runs at the top level of this conversation (never dispatch it as a subagent — it needs the Agent tool to launch reviewers).

After it completes, relay its report verbatim — no summarizing, no table-to-prose conversion.
```

- [ ] **Step 2: Delete v1 skills**

```bash
git rm -r skills/aa-review-orchestrator skills/aa-review-lenses
git rm -r skills/aa-coding-standards 2>/dev/null || rm -rf skills/aa-coding-standards
```

- [ ] **Step 3: Fix the rules skills**

In all four files under `skills/aa-init-rules/` and `skills/aa-edit-rules/`:
- Replace every `aa-review-orchestrator` with `aa-review-engine`; "all 6 lens prompts"/"6 lens" phrasing → "all 3 reviewer prompts"/"3 reviewer".
- Replace every `~/.claude/skills/<skill>/...` path with `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/...`; references from a skill to its OWN references/ become relative (`references/rule-shape.md`).
- In `rule-shape.md`: find the paragraph justifying the `,` prohibition via the multi-cite tag grammar (`[⚠️ Repo rule: <name>, also <name2>]`) and replace the justification with this single sentence (keep the prohibition itself): `Commas stay reserved in rule names so the rule-cite tag remains unambiguous to parse.`
- In `aa-edit-rules` Step 0 checks: any check that verifies `~/.claude/skills/aa-*` symlinks exist → replace with a check that the `aa-code-review` plugin is installed (the skill being loaded at all proves it — so simply DELETE those checks and renumber).

- [ ] **Step 4: Verify**

Run: `grep -rn 'aa-review-orchestrator\|aa-review-lenses\|aa-coding-standards' commands/ skills/ agents/` → expect only the coding-standards mention inside `references/coding-standards.md`'s own header, nothing else.
Run: `grep -rn '~/.claude' commands/ skills/ agents/` → expect `0` hits.
Run: `grep -rln 'multi-cite\|also <name2>' skills/` → expect `0` hits.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: thin command → engine; remove v1 skills; de-hardcode rules skills"
```

---

### Task 7: Adapter contract + docs (adapters/, README, CLAUDE.md, examples)

**Files:**
- Create: `adapters/README.md`
- Modify: `adapters/local.md` (rewrite), `README.md` (rewrite), `CLAUDE.md` (rewrite), `examples/.aa-review/rules.md` (path mentions only)

**Interfaces:**
- Consumes: engine step numbers + seam definitions (Task 5), plugin identity (Task 1).

- [ ] **Step 1: Write the adapter contract**

`adapters/README.md`, full content:

```markdown
# Adapters — the two extension seams

The engine (`skills/aa-review-engine/SKILL.md`) is adapter-agnostic except at two seams. An adapter is a markdown spec that tells the engine how to fill each seam. Adding one requires NO engine surgery — write the adapter doc, teach Step 1/Step 6 to honor its `adapter=<name>` value.

## Seam 1 — Context source (engine Step 1)

The adapter must yield: `BASE_REF` + resolution label, `MERGE_BASE`, a changed-file list with origin tags, the unified diff, and pre-read file contents (binary + hidden-dir filtered).

| Adapter | How | Status |
|---|---|---|
| `local` | git merge-base vs. resolved trunk; committed + working tree + untracked | ✅ implemented (`local.md`) |
| `github` | `gh pr view/diff <n>` — review a PR without checking it out | planned |
| `gitlab` | `glab mr view/diff <n>` | planned |

## Seam 2 — Report sink (engine Step 6)

The adapter receives: the rendered report, the verdict, and the structured finding set (ID, severity, reviewer tag, rule cite, file:line, title, mechanism).

| Adapter | Sink | Status |
|---|---|---|
| `local` | 3-layer markdown to the terminal; Layers 2/3 served interactively | ✅ implemented |
| `github` | PR review comments (inline per finding) + summary comment | planned |
| `gitlab` | MR discussion threads | planned |
| `file` | JSON/SARIF artifact for CI gates | planned |

## CI shape (planned, for orientation)

A CI integration = install this plugin in the runner + `claude -p "/aa-review adapter=github base=origin/${TARGET_BRANCH}"`. The engine's read-only invariants and verdict math are identical in CI; only the two seams differ.

## Mixed seams

`adapter=<name>` sets both seams for now. If a real use case needs split values (e.g., local context → file sink), extend the arg grammar then — YAGNI today.
```

- [ ] **Step 2: Rewrite `adapters/local.md`**

Keep its structure (prerequisites / daily flow / reading the report / troubleshooting / limits) but: install section → plugin install (see Step 3 below for the canonical snippet — same text in README); "6 lenses" → "3 reviewers" throughout; base-ref chain updated to the 5-step chain (matching engine Step 1 exactly); delete the "Parallel dispatch failed" troubleshooting entry (replace with: *"Reviewers ran inline / took 15+ min → verify the plugin is installed so the `aa-reviewer` agent type exists, and that `/aa-review` was invoked at top level, not from a subagent"*); all `~/repositories/aa-code-review/...` paths → "from the repo root"; report-contract pointer → `skills/aa-review-engine/references/report-format.md`.

- [ ] **Step 3: Rewrite `README.md` and `CLAUDE.md`**

`README.md`: what it is (3-reviewer parallel diff review, repo rules, deterministic verdict) · install as plugin:

````markdown
## Install

```bash
# from a local clone (development)
claude plugin marketplace add ~/repositories/agentic-code-review/aa-code-review
claude plugin install aa-code-review

# or once published, from the marketplace entry for AmirAnckonina/aa-code-review
```

Uninstall: `claude plugin uninstall aa-code-review`.
````

· the three commands (`/aa-review`, `/aa-init-rules` — note: still skill-invoked, `/aa-edit-rules`) · how a review runs (Steps 0–6, one paragraph) · adapter extension pointer to `adapters/README.md` · a **Permissions** section, verbatim:

````markdown
## Permissions (least privilege)

The plugin never touches your settings files. Enforcement is structural: the `aa-reviewer` agent has no write tools, the engine forbids git lifecycle commands, and gitignored files (e.g. `.env`) never enter review scope.

To avoid permission prompts during a review, you may OPT IN to these narrowly scoped rules in your project's `.claude/settings.json` (or user settings) — aa artifacts and read-only git only:

```json
{
  "permissions": {
    "allow": [
      "Skill(aa-code-review:aa-review-engine)",
      "Skill(aa-code-review:aa-init-rules)",
      "Skill(aa-code-review:aa-edit-rules)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git status:*)",
      "Bash(git merge-base:*)",
      "Bash(git rev-parse:*)",
      "Bash(git ls-files:*)",
      "Bash(git check-attr:*)",
      "Bash(git symbolic-ref:*)"
    ]
  }
}
```

Do not add blanket `Bash` or broad `Read` rules for this plugin — it does not need them.
````

`CLAUDE.md`: rewrite the runtime-architecture section for v2 (command → engine skill → 3 background `aa-reviewer` dispatches → synthesis → report) and replace the drift table with the v2 ownership map:

```markdown
| Concern | Authority | Consumers |
|---|---|---|
| Finding-line grammar, severity tiers, 🔴 gate | `skills/aa-review-engine/references/reviewer-prompt.md` | dispatched reviewers; engine Step 4 parser |
| Report assembly, IDs, verdict, layers, synthesis | `skills/aa-review-engine/references/report-format.md` | engine Steps 5–6; `adapters/local.md` |
| 13 base principles | `skills/aa-review-engine/references/coding-standards.md` (editing-time) | the 3 reviewer checklists (operational copies) |
| `.aa-review/rules.md` shape | `skills/aa-init-rules/references/rule-shape.md` | init/edit rules skills; engine Step 0 |
| Adapter seams | `adapters/README.md` | engine Steps 1 & 6 |
```

Also update in `examples/.aa-review/rules.md` any "6 lens"/orchestrator mentions (content of the example rules themselves stays).

- [ ] **Step 4: Verify**

Run: `grep -rn '6 lens\|six lens\|aa-review-orchestrator\|install\.sh' README.md CLAUDE.md adapters/ examples/` → expect `0` hits.
Run: `grep -c 'Seam' adapters/README.md` → expect ≥2.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "docs: adapter contract, plugin install docs, v2 ownership map"
```

---

### Task 8: End-to-end verification

**Files:**
- Create (scratch, outside repo): `/private/tmp/claude-501/-Users-amiranckonina/c23e135c-1432-418d-984a-b1b95ad8e445/scratchpad/aa-smoke/` test repo

**Interfaces:**
- Consumes: everything.

- [ ] **Step 1: Regression greps (whole repo)**

```bash
cd ~/repositories/agentic-code-review/aa-code-review
grep -rn '~/.claude' --include='*.md' . | grep -v docs/specs | grep -v docs/plans   # expect: 0 hits
grep -rniE 'positives|POS-\{?n' --include='*.md' skills/ commands/ agents/ adapters/  # expect: 0 hits
grep -rn 'maxTurns' --include='*.md' . | grep -v docs/                              # expect: 0 hits
jq -e '.name=="aa-code-review" and .version=="2.0.0"' .claude-plugin/plugin.json    # expect: true
```

- [ ] **Step 2: Build the planted-violation scratch repo**

All three planted violations must be added ON the feature branch so they appear in the diff vs. `main`:

```bash
S=/private/tmp/claude-501/-Users-amiranckonina/c23e135c-1432-418d-984a-b1b95ad8e445/scratchpad/aa-smoke
mkdir -p $S && cd $S && git init -q -b main
echo "# smoke target" > README.md && git add -A && git commit -qm "chore: init"
git checkout -qb feature/smoke
cat > app.py <<'EOF'
def get_user(db, user_id):
    return db.execute("SELECT * FROM users WHERE id = " + user_id)  # planted: SQL injection (Security)

def average(items):
    return sum(items) / len(items)  # planted: ZeroDivisionError on empty list (Bugs)

def proc(d):
    x = d
    return x  # planted: pointless alias, no test coverage (Quality)
EOF
git add -A && git commit -qm "feat: add app"
git diff main --stat   # expect: app.py, all lines added
```

- [ ] **Step 3: Install plugin + live run**

```bash
claude plugin marketplace add ~/repositories/agentic-code-review/aa-code-review
claude plugin install aa-code-review@aa-tools
cd $S && claude -p "/aa-review base=main" --verbose 2>&1 | tee review-run.log
```

Confirm, from `review-run.log`:
1. Three `Agent` dispatches with `run_in_background` ran concurrently (overlapping, not serial).
2. Report has a 3-row Reviewer Coverage table, verdict computed per math, Layer 1 ≤ ~30 lines.
3. The SQL injection is found by Security; empty-list division by Bugs; at least one Quality finding.
4. `expand CRT-1` and `show Security` both work from collected data (no re-reads).

- [ ] **Step 4: Record results + push**

Append a `## Verification run — 2026-07-06` section with the observed outcomes (dispatch concurrency, verdict, finding IDs) to THIS plan file, then:

```bash
cd ~/repositories/agentic-code-review/aa-code-review
git add docs/plans && git commit -m "docs: record v2 smoke-run results"
git push -u origin v2-plugin-redesign
```

## Verification run — 2026-07-06

**Executor:** Task 8 (end-to-end verification), executed against branch `v2-plugin-redesign`, repo clean at run start.

### Step 1 — Regression greps: PASS

```
grep -rn '~/.claude' --include='*.md' . | grep -v docs/specs | grep -v docs/plans   → 0 hits (PASS)
grep -rniE 'positives|POS-\{?n' --include='*.md' skills/ commands/ agents/ adapters/ → 3 hits, all legitimate
    - skills/aa-edit-rules/SKILL.md:56  ("too many false positives" — rule-tuning UX copy)
    - skills/aa-init-rules/SKILL.md:79  ("false positives are preferable to false negatives" — redaction policy)
    - adapters/local.md:190             ("Suppress known false positives" — capability gap note)
    None reference the removed POSITIVE/✅ report severity tier. Judgment: not a regression.
grep -rn 'maxTurns' --include='*.md' . | grep -v docs/                              → 0 hits (PASS)
jq -e '.name=="aa-code-review" and .version=="2.0.0"' .claude-plugin/plugin.json    → true (PASS)
```

### Step 2 — Scratch repo build: PASS

Built at `/private/tmp/claude-501/-Users-amiranckonina/c23e135c-1432-418d-984a-b1b95ad8e445/scratchpad/aa-smoke`. `git diff main --stat` on `feature/smoke`:

```
 app.py | 9 +++++++++
 1 file changed, 9 insertions(+)
```

All three planted violations (SQL injection, ZeroDivisionError, pointless-alias/no-coverage) present in a single fully-added file, as required.

### Step 3 — Install: PASS

```
claude plugin marketplace add ~/repositories/agentic-code-review/aa-code-review
  → Successfully added marketplace: aa-tools (declared in user settings)
claude plugin install aa-code-review@aa-tools
  → Successfully installed plugin: aa-code-review@aa-tools (scope: user)
claude plugin list  → aa-code-review@aa-tools, Version 2.0.0, enabled
claude plugin details aa-code-review@aa-tools
  → Skills (4): aa-edit-rules, aa-init-rules, aa-review, aa-review-engine
  → Agents (1): aa-reviewer
```
Manifest, marketplace name, component inventory all match spec.

### Step 3 — Live headless run: FAILED (environment/runtime limitation, not a plugin-artifact defect)

Command run per brief (adapted per task notes):
```
cd $S && claude -p "/aa-review base=main" --permission-mode bypassPermissions --verbose 2>&1 | tee review-run.log
```

Result — `review-run.log` in full:
```
Unknown command: /aa-review
EXIT_CODE=0
```

Reproduced independently two ways before an unrelated environment-wide auth outage (`Failed to authenticate. API Error: 401`, affecting the Bash safety classifier too) blocked further attempts:
1. Plugin installed via `claude plugin marketplace add` + `claude plugin install aa-code-review@aa-tools` → `/aa-review` unrecognized in `-p` mode.
2. Plugin loaded via `claude --plugin-dir ~/repositories/agentic-code-review/aa-code-review -p "/aa-review base=main" ...` (bypassing the marketplace-install path entirely) → same `Unknown command: /aa-review`.

Control checks to isolate scope of the failure:
- `claude -p "/compact"` (built-in slash command) → recognized and executed correctly ("Not enough messages to compact."). So `-p` mode's slash-command dispatch works in general.
- `claude -p "/help"` → "isn't available in this environment" (built-in help also restricted in print mode).
- `~/.claude/settings.json` correctly shows `"enabledPlugins": {"aa-code-review@aa-tools": true}` and `extraKnownMarketplaces.aa-tools` pointing at the repo path — the plugin *is* registered at the config level consumed by both interactive and print mode.
- Plugin cache confirms the command file is installed: `~/.claude/plugins/cache/aa-tools/aa-code-review/2.0.0/commands/aa-review.md` present and correct (thin relay to `aa-review-engine` skill, matches repo source verbatim).

Diagnosis: plugin-provided slash commands (as opposed to built-in ones) are not being resolved by `claude -p`'s command dispatcher in this environment/version, independent of install method. This blocked observation of all four of the brief's live-run confirmation checks.

Brief's 4 confirmation checks — outcomes:
1. Three `Agent` dispatches with `run_in_background` ran concurrently — **NOT OBSERVABLE** (command never started; no engine execution occurred).
2. Report has 3-row Reviewer Coverage table, verdict computed, Layer 1 ≤ ~30 lines — **NOT OBSERVABLE** (no report was generated).
3. SQL injection found by Security; empty-list division by Bugs; ≥1 Quality finding — **NOT OBSERVABLE** (no reviewers ran).
4. `expand CRT-1` / `show Security` work from collected data (no re-reads) — **NOT OBSERVABLE** (no findings collected).

Scope note: this is a headless/`-p`-mode-specific finding. The command file, skill relay, and dispatch logic were not exercised and remain unverified end-to-end in this session; nothing here demonstrates a defect in the plugin's own artifacts (command/skill/agent markdown) — the `--plugin-dir` control ruled out an install-path cause. An interactive-session run (`claude` then typing `/aa-review base=main` inside the scratch repo) was not attempted per the task's `-p`-only instructions and would be the natural next check to isolate print-mode vs. general plugin-command dispatch.

### Cleanup

Plugin left installed (`aa-code-review@aa-tools`, user scope) and marketplace left registered (`aa-tools` → local repo path) — no `claude plugin uninstall` / marketplace-remove was run, since the auth outage made it unsafe to assume further `claude` CLI calls would succeed/rollback cleanly; residue is limited to `~/.claude/settings.json` entries and the plugin cache under `~/.claude/plugins/cache/aa-tools/`, both inert (no side effects on other projects).

### Overall verdict

DONE_WITH_CONCERNS. Steps 1–2 and the install portion of Step 3 pass cleanly. The live headless run did not execute the review engine at all — `/aa-review` is not recognized by `claude -p`, reproduced via two independent loading paths. This is reported as a live-run finding per task instructions (no artifact fix attempted). Recommend a follow-up interactive-mode smoke run to confirm whether this is `-p`-mode-specific (most likely, given `/compact` and `/help` are also print-mode-restricted) or a deeper plugin-command registration issue.
