# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code **plugin** (`aa-code-review`, marketplace `aa-tools`) — a package of Claude-Code-facing prompt artifacts (an agent, skills, a slash command) for running code reviews from inside a target service repo. **There is no application code** — every artifact is markdown. The repo distributes itself as a plugin: `claude plugin marketplace add` + `claude plugin install`, not symlinks.

## Install / contributor loop

```bash
claude plugin marketplace add ~/repositories/agentic-code-review/aa-code-review
claude plugin install aa-code-review@aa-tools
```

Edits to files in a locally-added marketplace path go live in any active Claude Code session with the plugin installed from that path — no reinstall for content changes. Reinstall only if `.claude-plugin/plugin.json`'s manifest (commands/agents/skills list) changes. To exercise a change: `cd <target service repo> && claude` then `/aa-review`. There is no build, lint, or test suite.

## Runtime architecture (when `/aa-review` fires in a target repo)

1. `commands/aa-review.md` (thin slash command) parses `$ARGUMENTS` and invokes the **`aa-review-engine` skill** via the Skill tool, passed verbatim.
2. The skill runs at the **TOP LEVEL** of the user's session (not as a subagent). This is what makes the architecture work — only top-level contexts have access to the `Agent` tool, which is required to dispatch reviewer subagents in the background. (An agent-via-Task indirection would fail because subagents cannot spawn other subagents per Claude Code's runtime.)
3. The skill executes Steps 0–6: Step 0 reads target repo's `CLAUDE.md`, `.claude/context.md`, `.aa-review/rules.md` (the last is repo-specific rules layered on top of base standards) and parses args (`--deep`, `base=`, `adapter=`, focus text).
4. Step 1 resolves the base ref — first that succeeds: explicit `base=<ref>` → `@{upstream}` → `origin/HEAD` → `origin/main`/`develop`/`master` fallbacks — computes the merge-base, collects committed + working-tree + untracked changes (binary and hidden-dir filtered), and pre-reads every surviving file ONCE.
5. Step 2 prints an intent summary. Step 3 dispatches 3 `aa-reviewer` subagents (Bugs / Security / Quality) via `Agent(..., run_in_background=true)` — concurrent by construction, not a single blocking message. A reviewer that errors or returns no parseable output is retried once; if ≥2 of 3 are still `NOT REVIEWED`, the engine aborts.
6. Step 4 collects reviewer output. Step 5 synthesizes: systemic clustering, dedupe, `[CRITICAL]`-rule promotion, assigns `CRT-/IMP-/SUG-` IDs, computes the verdict (any 🔴 → BLOCKER; any 🟡 → NEEDS WORK; else SHIP IT). Step 6 emits the 3-layer report per the active adapter (`local` is the only one implemented).

## Ownership map

| Concern | Authority | Consumers |
|---|---|---|
| Finding-line grammar, severity tiers, 🔴 gate | `skills/aa-review-engine/references/reviewer-prompt.md` | dispatched reviewers; engine Step 4 parser |
| Report assembly, IDs, verdict, layers, synthesis | `skills/aa-review-engine/references/report-format.md` | engine Steps 5–6; `adapters/local.md` |
| 13 base principles | `skills/aa-review-engine/references/coding-standards.md` (editing-time) | the 3 reviewer checklists (operational copies) |
| `.aa-review/rules.md` shape | `skills/aa-init-rules/references/rule-shape.md` | init/edit rules skills; engine Step 0 |
| Adapter seams | `adapters/README.md` | engine Steps 1 & 6 |

`rule-shape.md` declares its own drift contract at the bottom — read it before touching either rules skill.

## Conventions specific to this repo

- **`aa-` prefix on every artifact** — the plugin's commands/agents/skills share a marketplace namespace; the prefix prevents collision with other plugins and personal/global skills.
- **3 severity tiers only** (🔴 / 🟡 / 🔵). No POSITIVE / ✅ Positive / POS-{n} category — do not reintroduce praise sections.
- **`[CRITICAL]` is the only severity marker** in `.aa-review/rules.md` rule headings. Rules without it are unmarked — the reviewer infers severity per finding.
- **Reserved tokens** in the report grammar — rule names and titles must avoid `[`, `]`, `,`, ` — ` (em-dash with spaces), `` ` ``, `|`, `"`. The `|` separator between title and mechanism is single-use per finding line.
- **Scope = read-only + local.** No git lifecycle commands, no MR/PR posting from the agent. Future remote adapters are planned (`github`, `gitlab` — see `adapters/README.md`).
- **No agent memory.** Persistent learning lives in `<target>/.aa-review/rules.md`. Findings cite either code evidence or a named rule — never internal agent state.

## Docs

`README.md` at the repo root is the canonical project overview (install, the slash command and skill-invoked commands, how a review runs). Start there for usage context.
