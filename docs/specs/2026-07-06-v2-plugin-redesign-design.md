# Spec — aa-code-review v2: plugin redesign

**Status:** Approved (2026-07-06)
**Branch:** `v2-plugin-redesign` (`main` = frozen current version)
**Supersedes:** `2026-07-02-improvements-spec.md` (its items are folded in; that doc remains the bug-audit record)

## Goal

Rebuild aa-code-review as a Claude Code **plugin** with a generic, adapter-extensible review engine that:

1. Fixes parallel dispatch **structurally** (background subagents, not single-message prose mandates).
2. Cuts token cost and noise (~⅓ input tokens: 3 reviewers instead of 6 lenses, cache-friendly prompt ordering, finding caps).
3. Collapses the drift surface (one grammar owner, one prompt template, 2 fewer session-loaded skills).
4. Opens two clean extension seams (context source, report sink) so CI adapters (GitHub Actions, GitLab CI) are one markdown file each — no engine surgery.

Out of scope: the feedback skill (dropped for good), remote adapters' implementation (contract only), any change to the 3-severity tiers / CRITICAL gate / deterministic verdict / repo-rules mechanism — those work and stay.

## Target layout

```
aa-code-review/
├── .claude-plugin/plugin.json     ← plugin manifest (replaces install.sh symlinks)
├── commands/aa-review.md          ← thin: relay args → engine skill
├── agents/aa-reviewer.md          ← dedicated READ-ONLY reviewer agent (tools: Read, Grep, Glob, Bash)
├── skills/
│   ├── aa-review-engine/          ← renamed from aa-review-orchestrator
│   │   ├── SKILL.md               ← Steps 0–6, adapter-agnostic core
│   │   └── references/
│   │       ├── report-format.md   ← THE single grammar/severity/verdict source of truth
│   │       ├── reviewer-prompt.md ← the one dispatch prompt template (one owner, one copy)
│   │       ├── bugs.md            ← reviewer ①: Correctness & Reliability (old lenses 1+3)
│   │       ├── security.md        ← reviewer ②: Security & Input Safety (old lens 2)
│   │       ├── quality.md         ← reviewer ③: Design + Perf/Testing + Readability (old 4+5+6)
│   │       └── coding-standards.md← 13 principles, editing-time reference (no longer a skill)
│   ├── aa-init-rules/             ← flow unchanged; paths de-hardcoded
│   └── aa-edit-rules/             ← flow unchanged; paths de-hardcoded
├── adapters/
│   ├── README.md                  ← adapter CONTRACT + usage guide
│   └── local.md                   ← implemented adapter (docs)
├── examples/.aa-review/rules.md
└── docs/specs/                    ← this spec + the 2026-07-02 audit
```

**Deleted:** `skills/aa-review-lenses/` (content → `report-format.md` + 3 reviewer checklists), `skills/aa-coding-standards/` (→ `references/coding-standards.md`), `install.sh` (→ plugin install). The 6 lens reference files merge pairwise into the 3 reviewer checklists with no check dropped.

## Architecture decisions

### D1 — 3 reviewers, 6 lenses folded

One subagent per charter: **bugs** (correctness + reliability), **security**, **quality** (design + perf/testing + readability). Charters are disjoint, so the 5 cross-check pairs and most dedupe work disappear; cross-check slims to systemic-clustering only (3+ findings on one module → one architectural finding). Lens Coverage table becomes a 3-row Reviewer Coverage table. IDs, tiers, verdict math unchanged.

### D2 — Background dispatch (the parallel fix)

The engine dispatches 3 `Agent` calls with `subagent_type="aa-reviewer"`, `run_in_background=true`. Background tasks run concurrently regardless of whether the calls land in one message — the single-message fragility that produced 39-minute sequential runs is removed, not re-prohibited. The engine then waits for completion notifications, collects outputs, retries a failed reviewer once, and aborts the verdict if ≥2 of 3 reviewers failed. The old "exactly 6 calls in ONE message" protocol, self-check counter, and `maxTurns=6` (unenforceable — no such Agent parameter) are all deleted; the reviewer prompt keeps in-prose guidance to minimize tool calls since code is pre-read.

### D3 — Read-only enforced by tool list

`agents/aa-reviewer.md` declares `tools: Read, Grep, Glob, Bash` (no Edit/Write/NotebookEdit/Agent). Bash guidance restricts to read-only commands (grep/rg/git read ops). The prose boundaries remain as backup, but the tool list is the enforcement.

### D4 — Prompt-cache-friendly template

`reviewer-prompt.md` orders the dispatch prompt: **shared block first** — branch/context, repo rules verbatim, intent, pre-read code, diff, output format, CRITICAL gate — byte-identical across all 3 prompts; **assignment block last** — reviewer name + checklist path. Same agent type + identical prefix ⇒ cache-eligible; combined with 3-not-6 dispatch ≈ ⅓ the input tokens of v1.

### D5 — One owner per fact (grammar split by audience)

Reviewer-facing facts — finding-line grammar (severity emoji, `<ID>` placeholder, `[<Reviewer>]` tag, optional `[⚠️ Repo rule: <name>]`, `file:line`, title `|` mechanism), reserved tokens, severity tiers, CRITICAL 3-criteria gate, the 10-finding cap — live ONLY in `reviewer-prompt.md` (the single dispatch template; reviewers never read a second file for format). Engine-facing facts — `[CRITICAL]` rule promotion, synthesis rules, ID assignment, verdict table, 3-layer report templates, truncation/ordering — live ONLY in `report-format.md`, which points at reviewer-prompt.md for the line grammar it parses. Each fact has exactly one home, so the v1 bug 1.1 (two conflicting grammars) is structurally impossible.

### D6 — Two adapter seams

The engine is adapter-agnostic except at:

1. **Context source** (Step 1) — how diff scope is acquired. `local`: merge-base vs resolved trunk + working tree + untracked. Future `github`: `gh pr diff/view`. Future `gitlab`: `glab`.
2. **Report sink** (Step 6) — where the report goes. `local`: 3-layer terminal markdown. Future: PR/MR comment, JSON/SARIF file.

`adapters/README.md` documents the contract: what an adapter must provide to each seam (scope inputs: base ref, file list w/ origin tags, diff, file contents; sink inputs: rendered report + verdict + finding set). Unknown `adapter=<name>` → one refusal message, stated once in the engine.

### D7 — Plugin packaging

`.claude-plugin/plugin.json` manifest; `commands/`, `agents/`, `skills/` auto-discovered. Internal file references use `${CLAUDE_PLUGIN_ROOT}` — no `~/.claude/...` hardcoding (v1 bug 4.1). Install via marketplace/local path; uninstall via plugin remove. `install.sh` and its settings.json permission-merge are deleted; required permissions documented in README.

## Fold-in of the 2026-07-02 audit

| Audit item | Resolution in v2 |
|---|---|
| 1.1 grammar contradiction | D5 — single owner |
| 1.2 base-ref chain drift | Step 1 chain: explicit `base=` → `@{upstream}` → `origin/HEAD` → `origin/main`/`develop`/`master`; resolution-source enum matches exactly these five values; docs aligned |
| 1.3 "positives" fossil | deleted with lenses SKILL.md; report-format.md carries the 3-tier-only rule |
| 1.4 dead halt clause | gone — coding-standards is a reference doc, relationship stated in CLAUDE.md |
| 1.5 phantom multi-cite | dropped; `,` stays reserved in rule names (cheap insurance, stated in report-format.md) |
| 1.6 doc path drift | all paths repo-relative or `${CLAUDE_PLUGIN_ROOT}` |
| 2.1 read-only agent | D3 |
| 2.2 maxTurns | deleted (D2) |
| 3.1 workflow-narrating descriptions | engine/init-rules descriptions cut to trigger conditions only |
| 3.2 coding-standards trigger breadth | demoted from skill to reference |
| 3.3 cache ordering | D4 |
| 4.1–4.3 portability | D7 |

Additional v1 bugs found 2026-07-06, also fixed: command's "append `adapter=local`" mandate (dropped — engine defaults internally); false "lenses SKILL.md is loaded by lens subagents" claim (moot); adapter-refusal text duplicated in Steps 0 and 7 (stated once).

## Noise & runtime budget

- Per-reviewer cap: **max 10 findings**, severity-first; overflow noted as a count in the reviewer's summary.
- Layer-1 report ≤30 lines for a 10-finding review; >20 findings → 🔴/🟡 in full, 🔵 truncated with `+M more`.
- Wall-time target: moderate diff (≤15 files) under ~8 min with Sonnet reviewers (the confirmed-parallel pilot benchmark); `--deep` flips reviewers to Opus.

## Verification

1. **Scratch-repo run:** plant one violation per reviewer charter (a logic bug, an injection, a naming/test gap) → `/aa-review` → confirm 3 background dispatches ran concurrently, finding lines parse, verdict = BLOCKER only if the planted 🔴 passes the gate, Layer-1 within budget.
2. **Plugin smoke:** install from local path, `/aa-review` resolves in a target repo, `claude plugin` uninstall leaves no residue.
3. **Regression grep:** no `aa-review-lenses`, `aa-coding-standards` (as skill), `install.sh`, `~/.claude/skills/aa-` references remain anywhere in the repo.
