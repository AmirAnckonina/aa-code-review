# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A package of Claude-Code-facing prompt artifacts (agents, skills, slash commands) for running code reviews from inside a target service repo. **There is no application code** — every artifact is markdown. The repo distributes itself by symlinking its contents into `~/.claude/`.

## Install / contributor loop

```bash
./install.sh             # symlinks agents/ skills/ commands/ into ~/.claude/; idempotent
CLAUDE_HOME=/tmp/x ./install.sh   # dry-run target
```

Because the install is symlinks, **edits to files in this repo go live in any active Claude Code session immediately — no re-install**. To exercise a change: `cd <target service repo> && claude` then `/aa-review`. There is no build, lint, or test suite.

## Runtime architecture (when `/aa-review` fires in a target repo)

1. `commands/aa-review.md` (~25-line thin slash command) parses args and invokes the **`aa-review-orchestrator` skill** via the Skill tool. Default `adapter=local` if not specified.
2. The skill runs at the **TOP LEVEL** of the user's session (not as a subagent). This is what makes the architecture work — only top-level contexts have access to the `Agent` tool, which is required to dispatch lens subagents in parallel. (An agent-via-Task indirection would fail because subagents cannot spawn other subagents per Claude Code's runtime.)
3. The skill executes Steps 0–7: reads target repo's `CLAUDE.md`, `.claude/context.md`, `.aa-review/rules.md` (the last is repo-specific rules layered on top of base standards).
4. Resolves base ref (explicit `base=<ref>` → upstream → `origin/HEAD` → `main`/`develop`/`master` fallbacks), computes merge-base, pre-reads every changed file ONCE.
5. Launches the 6 lenses (Correctness / Security / Reliability / Design / Perf+Testing / Readability) in a **single Agent message** for parallel execution. Pre-read content is injected into each lens prompt — lenses MUST NOT re-read or re-diff.
6. Cross-checks pairs, dedupes, assigns `CRT-/IMP-/SUG-` IDs, applies `[CRITICAL]` rule promotion, emits the 3-layer report per the active adapter. Verdict is deterministic from highest severity.

## Source-of-truth map (drift hazards)

These pairs are explicitly coupled — change one without updating the other and the system breaks:

| Concern | Authority | Consumers |
|---|---|---|
| Report grammar, severity tiers, verdict math, lens list | `skills/aa-review-lenses/SKILL.md` | `skills/aa-review-orchestrator/SKILL.md`, `adapters/local.md` |
| 13 base coding principles | `skills/aa-coding-standards/SKILL.md` | the 6 lens reference files under `skills/aa-review-lenses/references/` |
| `.aa-review/rules.md` on-disk shape | `skills/aa-init-rules/references/rule-shape.md` | `aa-init-rules` and `aa-edit-rules` SKILL.md files; lens-prompt injection in `skills/aa-review-orchestrator/SKILL.md` |
| Slash-command → skill invocation contract | `commands/aa-review.md` | `skills/aa-review-orchestrator/SKILL.md` |

`rule-shape.md` declares its own drift contract at the bottom — read it before touching either rules skill.

## Conventions specific to this repo

- **`aa-` prefix on every artifact** — agents, skills, commands all live in a shared `~/.claude/` namespace; the prefix prevents collision with personal/global skills (`coding-standards` vs `aa-coding-standards`).
- **3 severity tiers only** (🔴 / 🟡 / 🔵). No POSITIVE / ✅ Positive / POS-{n} category — do not reintroduce praise sections.
- **`[CRITICAL]` is the only severity marker** in `.aa-review/rules.md` rule headings. Rules without it are unmarked — the reviewer infers severity per finding.
- **Reserved tokens** in the report grammar — rule names and titles must avoid `[`, `]`, `,`, ` — ` (em-dash with spaces), `` ` ``, `|`, `"`. The `|` separator between title and mechanism is single-use per finding line.
- **Scope = read-only + local.** No git lifecycle commands, no MR/PR posting from the agent. Future remote adapters are deferred (`adapters/github-actions.md`, `adapters/gitlab-ci.md` placeholders).
- **No agent memory.** Persistent learning lives in `<target>/.aa-review/rules.md`. Findings cite either code evidence or a named rule — never internal agent state.

## Docs

`README.md` at the repo root is the canonical project overview (install, the three slash commands, how a review runs). Start there for usage context.
