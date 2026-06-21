---
description: "Parallel multi-lens code review of the current branch's diff vs. trunk"
argument-hint: "[focus areas or notes] [base=<ref>] [--deep] [adapter=<name>]"
---

# Code Review

Run a parallel multi-lens code review of the current branch's diff vs. trunk.

## Arguments

**Raw input:** $ARGUMENTS

Argument parsing is handled by the orchestrator skill (Step 0), not here. Recognized tokens:

- **`--deep` flag** (optional) — if present, lens subagents use Opus instead of Sonnet.
- **`base=<ref>` token** (optional) — explicit base ref for the diff (default: `origin/develop`).
- **`adapter=<name>` token** (optional) — output adapter. Default: `local` (markdown to terminal). For now, only `local` is supported.

**Scope is fixed:** every run reviews committed changes + working-tree mods (staged + unstaged) + untracked, non-gitignored files. Binaries are filtered. Files under hidden directories (any path segment starting with `.`, e.g. `.claude/`, `.aa-review/`, `.github/`) are filtered too — they inform the reviewer as context but are not themselves review targets. Top-level dot-files (e.g. `.gitignore`, `.editorconfig`) remain in scope. This matches "what's on your branch right now" — the natural local-reviewer model. There is no flag to narrow the scope; if you want to exclude uncommitted work, commit or stash it before running.
- **Remaining tokens** — focus areas, notes, or context.

## Workflow

Use the **Skill** tool to invoke the **aa-review-orchestrator** skill. Pass `$ARGUMENTS` verbatim. If the user did not include `adapter=<name>`, append `adapter=local` so the skill receives an explicit value.

The skill runs at the **TOP LEVEL** of this conversation (not as a subagent). This is architecturally critical: the skill inherits the `Agent` tool from this top-level context, which lets it dispatch 6 lens subagents in parallel. An agent-via-Task pattern would not — subagents cannot spawn other subagents in Claude Code's runtime.

After the skill completes, relay its output **verbatim** to the user. Do NOT summarize, do NOT modify, do NOT convert tables to narrative.

If the skill's Activity Summary contains a line starting with `⚠️ Parallel dispatch failed`, surface that line prominently — it is empirical evidence that the skill orchestrator pattern is not working in this environment and the maintainer must be notified.
