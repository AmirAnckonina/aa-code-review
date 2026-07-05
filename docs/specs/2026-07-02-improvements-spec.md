# Spec — aa-code-review Improvements

**Status:** Draft (backlog — pick up later)
**Date:** 2026-07-02
**Source of review:** Full read of `~/repositories/agentic-code-review/aa-code-review/` (working copy preserved at `~/agentic-workflow-workbench/aa-code-review/`).
**Context:** The aa-* symlinks were removed from `~/.claude/` on 2026-07-02 (user-level focus moved to `custom-agentic-tools`/agentic-workflow). Re-install with `./install.sh` when resuming this work.

---

## Goal

Fix internal drift bugs, harden prose-only boundaries structurally, cut token waste, and prepare the package for optional plugin distribution — without changing the review methodology (6 lenses, 3 tiers, deterministic verdict).

## Priority 1 — Correctness bugs (drift that already happened)

### 1.1 Output-format contradiction (parse-breakage risk)
- `skills/aa-review-lenses/SKILL.md` → "Subagent Output Format" specifies finding lines as
  `🔴 CRITICAL — [file:line] — title | mechanism` (no `<ID>` placeholder, no `[<LENS NAME>]` tag).
- `skills/aa-review-orchestrator/SKILL.md` → dispatch template requires
  `🔴 <ID> [<LENS NAME>] [⚠️ Repo rule: <name>]? — file:line — title | mechanism`, and Step 4 parses on exactly that pattern.
- A lens following the self-declared "single source of truth" emits lines the parent's parser won't match.
- **Fix:** make the orchestrator's grammar the only grammar. Replace the lenses SKILL.md "Subagent Output Format" section with a pointer to the orchestrator's template (or move the template into lenses SKILL.md and have the orchestrator reference it — one owner, one copy).

### 1.2 Base-ref resolution: three files, three algorithms
- Orchestrator Step 1 chain: explicit `base=` → `origin/main` → `origin/develop` → `origin/master`.
- Orchestrator's own "resolution source" enum (lines ~59, ~104): includes `branch upstream` and `origin/HEAD` — values the algorithm can never produce — and lacks a label for the `origin/main` default.
- `CLAUDE.md` and `adapters/local.md` describe a chain that *includes* upstream and `origin/HEAD` detection.
- **Fix:** implement the richer chain (explicit → `@{upstream}` → `origin/HEAD` → `origin/main`/`develop`/`master` fallback), align the enum, and update CLAUDE.md + local.md to match. Upstream detection is the most correct default for branches tracking non-main trunks.

### 1.3 Leftover "positives" wording
- `skills/aa-review-lenses/SKILL.md` status values: "`⚠️ N findings` — only suggestions/**positives**". The POSITIVE tier was removed repo-wide; this is a fossil. Delete the word.

### 1.4 Dead protocol: aa-coding-standards "halt" clause
- Lenses SKILL.md: "Requires `aa-coding-standards` to be loaded… respond with error and halt." Nothing in the runtime path ever loads that skill — lens reference files carry copied principle text instead. The condition is unevaluatable.
- **Fix:** delete the halt clause; state the real relationship: `aa-coding-standards` is the **editing-time authority**, the 6 lens reference files are the **operational copies** (already reflected in CLAUDE.md's drift table).

### 1.5 Phantom multi-cite grammar
- `skills/aa-init-rules/references/rule-shape.md` justifies forbidding `,` in rule names via a multi-cite tag grammar (`[⚠️ Repo rule: <name>, also <name2>]`) that the orchestrator never defines.
- **Fix:** either specify multi-cite in the orchestrator's token rules, or drop the phantom justification (keep the `,` prohibition — it's still cheap insurance).

### 1.6 Doc path drift
- `adapters/local.md` (troubleshooting) and README point at `~/repositories/aa-code-review/install.sh`; the actual checkout is `~/repositories/agentic-code-review/aa-code-review/`. Align docs with the real layout (or make the instruction path-relative: "from the repo root").

## Priority 2 — Structural hardening

### 2.1 Custom read-only lens agent (replaces prose "READ ONLY")
- Today lenses run as `subagent_type="general-purpose"` (all tools) with prose boundaries.
- **Fix:** add `agents/aa-lens-reviewer.md` with a restricted tool list (Read, Grep, Glob, Bash — no Edit/Write/NotebookEdit) and dispatch with `subagent_type="aa-lens-reviewer"`. `install.sh` already symlinks `agents/`. Keep the prose boundaries as backup, but the tool list becomes the enforcement.

### 2.2 Remove unenforceable `maxTurns = 6`
- The `Agent` tool exposes no maxTurns parameter. Replace with in-prompt guidance ("aim for ≤6 tool calls; code is pre-read") or delete.

## Priority 3 — Token & discovery hygiene

### 3.1 Trim workflow-summarizing descriptions
- `aa-review-orchestrator` and `aa-init-rules` frontmatter descriptions narrate their full pipelines. Per skill-authoring guidance (SDO), workflow-summarizing descriptions (a) load into every session and (b) risk the model following the description instead of the body.
- **Fix:** cut each to triggering conditions only, e.g. orchestrator → "Use when: /aa-review, 'review the current branch', 'run the code review'. Runs at top level, not as a subagent."

### 3.2 Decide aa-coding-standards trigger breadth
- Its description ("Use when writing code, reviewing code…") invites loading in every coding session. Keep if intended to shape written code; narrow to review-infrastructure-only otherwise.
- Also: label hard numeric caps (files ≤200 lines, functions ≤80, coverage ≥80%) as "defaults — repo rules override" to reduce noise findings.

### 3.3 Prompt-cache-friendly lens prompt ordering
- The 6 lens prompts currently start with lens-specific text, so the ~identical bulk (pre-read code, diff, repo rules, output format) shares no prefix → ~6× input-token cost.
- **Fix:** reorder the template: shared context first (byte-identical across all 6 calls), lens assignment (`LENS_NAME`, `LENS_FILE`) last. Same subagent type ⇒ same system prompt ⇒ shared prefix is cache-eligible.

## Priority 4 — Portability / distribution (optional)

### 4.1 De-hardcode `~/.claude/...` paths
- Orchestrator lens-file references, aa-edit-rules Step 0 checks 6–7, and the CRITICAL-gate pointer all hardcode `~/.claude/skills/...`. Breaks project-level installs and plugin packaging.
- **Fix:** skills reference their own `references/` relatively; the orchestrator resolves the lens-reference absolute path once at Step 0 and injects the resolved path into subagent prompts.

### 4.2 Plugin packaging (after 4.1)
- Convert the package into a Claude Code plugin (`plugin.json` + existing `skills/`, `commands/`, `agents/` dirs): namespacing, versioning, clean install/uninstall — replaces symlink management.

### 4.3 install.sh `--uninstall` mode
- README documents a manual `find -delete`; fold it into the script.

## Non-goals

- No change to the 6-lens taxonomy, severity tiers, verdict math, or the rules-file grammar.
- No remote adapters (github-actions / gitlab-ci) — still deferred.

## Verification

Per change: run `/aa-review` in a scratch repo containing one planted violation per affected behavior (e.g., a finding that exercises the ID/lens-tag grammar for 1.1; a branch with an `@{upstream}` trunk for 1.2; an Edit attempt by a lens for 2.1). The local.md synthetic-violation test loop applies to every edit before promoting from the workbench copy to the live repo.
