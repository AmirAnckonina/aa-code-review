# Local Invocation Adapter

How to run `/aa-review` on a local branch. No GitHub/GitLab interaction, no CI — just `/aa-review` against the current branch's diff.

> **Scope:** local only. Future adapters (`github-actions.md`, `gitlab-ci.md`) will document remote/CI invocation. Today, `local` is the only implemented adapter (default).

---

## Prerequisites

Before first use, in this order:

| # | Requirement | How to verify |
|---|---|---|
| 1 | Claude Code installed | `claude --version` |
| 2 | `aa-code-review/install.sh` has been run successfully | `ls ~/.claude/skills/aa-review-orchestrator` returns a symlink |
| 3 | Target repo is a git repo with a defined trunk | `git symbolic-ref refs/remotes/origin/HEAD` resolves cleanly |
| 4 | Current branch has commits ahead of trunk | `git log --oneline $(git merge-base HEAD @{upstream})..HEAD` shows ≥1 commit |
| 5 | Repo has a `CLAUDE.md` at root (recommended, not required) | `cat CLAUDE.md` |
| 6 | Repo has `.aa-review/rules.md` (recommended — repo-specific rules) | `cat .aa-review/rules.md` — bootstrap with `/aa-init-rules` if missing |

If #5 or #6 are missing, `/aa-review` skips them silently — they're optional context, not gates. But the review will be lower-fidelity without them (no repo-specific rules means findings come from base coding standards + lens judgment only).

---

## Install (one-time)

From the `agentic-code-review` repo root:

```bash
./aa-code-review/install.sh
```

Creates symlinks under `~/.claude/` for every skill / command in this package:
- `~/.claude/skills/aa-review-orchestrator` → orchestration (Steps 0–7, dispatches the 6 lenses)
- `~/.claude/skills/aa-coding-standards` → Tier 1 base principles
- `~/.claude/skills/aa-review-lenses` → 6-lens orchestration spec + severity rules
- `~/.claude/skills/aa-init-rules` → bootstrap `.aa-review/rules.md`
- `~/.claude/skills/aa-edit-rules` → maintain `.aa-review/rules.md`
- `~/.claude/commands/aa-review.md` → `/aa-review` slash command

Edits to files in this repo take effect immediately in any active Claude Code session — no re-install for content changes. Re-run `install.sh` only when a new skill/command is added or required-permissions change. Idempotent.

To **uninstall**, manually delete the symlinks. (No uninstall mode yet.)

---

## Daily flow

### Reviewing a branch

```bash
cd <target-repo>
git checkout <feature-branch>
claude  # start Claude Code session
```

Then in the session:

```
/aa-review
```

Optional args:

```
/aa-review --deep                              # Use Opus for all 6 lens subagents (default: Sonnet)
/aa-review base=main                           # Override base ref (default: origin/main)
/aa-review adapter=local                       # Output adapter (default: local — only implemented one)
/aa-review focus on the auth changes           # Free-form focus areas
/aa-review --deep base=main focus on race conditions    # Combine
```

The slash command invokes the **`aa-review-orchestrator`** skill (which runs at the top level of your session — that's what lets it dispatch 6 lens subagents in parallel via the `Agent` tool). The orchestrator:

1. Reads `CLAUDE.md`, `.claude/context.md`, `.aa-review/rules.md` if present.
2. Resolves trunk (`base=<ref>` → `origin/main` default → `origin/develop` / `origin/master` fallbacks).
3. Computes merge-base, runs `git diff $merge_base..HEAD`, pre-reads every changed file ONCE.
4. Prints a brief intent summary.
5. Launches 6 lens subagents in parallel (Sonnet by default, Opus if `--deep`).
6. Cross-checks pairs, dedupes, assigns IDs, applies `[CRITICAL]`-rule promotion.
7. Prints the 3-layer markdown report.

### Empty diff handling

If the current branch == trunk (no commits ahead), the orchestrator stops and tells you. Switch branches and retry.

### Long branches (warning)

The orchestrator reads **every changed file** at HEAD before launching lenses. On a branch with ≥50 changed files or ≥3K diff lines, expect 30–60s of pre-read before lens dispatch. Acceptable for local scale; optimization deferred.

---

## Reading the report

> **Definitive contract:** `skills/aa-review-lenses/SKILL.md` → **Review Report Format** + **Severity Levels**. This section is a reading guide for terminal output — for the exact grammar, severity binding, and drill-down protocol, read the skill.

The report renders in **three layers** (progressive disclosure). Layer 1 is the default. Layers 2 and 3 surface on demand.

### Layer 1 (what prints by default)

| Section | What it tells you |
|---|---|
| **Verdict + TL;DR** | BLOCKER / NEEDS WORK / SHIP IT + 1-2 sentence rationale |
| **Findings Summary** | Counts per severity (🔴 / 🟡 / 🔵) + repo-rule citation count |
| **Lens Coverage table** | Per-lens status: clean, N findings, or ❌ NOT REVIEWED. Top finding ID per lens |
| **Findings** | One line per finding: `<emoji> <ID> [<Lens>] [⚠️ Repo rule]? — file:line — <title>`. No mechanism prose, no fix sketch — those are Layer 2 |
| **Drill-down hint** | A single line under the Findings header: *"`expand <ID>` for detail · `show <Lens>` for full lens output"* |
| **Activity Summary** | Diagnostics: files pre-read, lens models, dedupe count, cross-checks. **`⚠️ Parallel dispatch failed` here means lenses ran inline — flag it** (see Troubleshooting). |

**Top-N truncation.** If total findings >20, all 🔴 and 🟡 print in full; 🔵 print until 20 total; the remainder collapse into a single `+M more — expand to see` line. Suppressed findings remain expandable by ID.

### Verdict

Verdict math: see `skills/aa-review-lenses/SKILL.md` → **Verdict Rules**. Deterministic — if it surprises you, look at the highest-severity finding.

### Severity calibration

Per the 3-criteria gate (see `skills/aa-review-lenses/SKILL.md` → **Severity Levels**), 🔴 CRITICAL findings must articulate reachability, named invariant, and no-mitigation in their mechanism's first sentence. If you see a 🔴 with a vague articulation (e.g., `(reachable on: yes; violates: security; no mitigation: see above)`), that's a lens cargo-culting the gate — tighten the lens prompt or repo rules accordingly.

---

## Drill-down (Layers 2 & 3)

After Layer 1 prints, ask follow-ups in the same session:

| Ask | Layer | What you get |
|---|---|---|
| `expand CRT-1` | 2 | Title, mechanism prose (what's wrong, why, impact, suggested fix), full repo-rule body if cited, surrounding code context (≥5 lines before/after) |
| `expand SUG-5` | 2 | Same as above. Works on truncated findings too (the ones hidden by `+M more`) |
| `expand suggestions` | 2 | Layer 2 for every suppressed 🔵 finding in the truncated tail |
| `show Reliability` | 3 | Full rationale the Reliability lens returned, its checklist headers, and any items it skipped |

The orchestrator has the diff + file contents in memory from the run, so drill-down is fast (no re-read).

---

## Troubleshooting

### "Trunk could not be resolved"

The orchestrator resolves `base=<ref>` → `origin/main` (default) → `origin/develop` / `origin/master` fallbacks. If none resolve, the review aborts. Fix:

```bash
# Explicitly set origin/HEAD to your trunk branch
git remote set-head origin --auto
# or
git remote set-head origin main
```

Or pass `base=<ref>` explicitly.

### "Lens X failed after retry — NOT REVIEWED"

Subagent failure. Common causes: rate limiting, timeout, model error. Re-run `/aa-review`. If it persists, run with `--deep` (Opus is more reliable for complex diffs but slower/costlier). If ≥4 of 6 lenses fail, the orchestrator aborts the report (verdict can't be trusted on near-empty coverage).

### `⚠️ Parallel dispatch failed` in Activity Summary

The orchestrator's self-check fired — fewer than 6 `Agent()` calls were issued in a single response, meaning lens dispatch silently fell back to sequential / inline execution. Symptoms: long runtime (15+ min on moderate diffs), uneven token spend (one big context, not 6 distributed).

Fix attempts in order:
1. Run `~/repositories/aa-code-review/install.sh` to ensure the latest skill is symlinked.
2. Re-run `/aa-review` in a fresh Claude Code session.
3. If it persists, capture the Activity Summary line — it's empirical evidence needed to diagnose runtime behavior.

### Report missing the Lens Coverage table

The slash command should relay the orchestrator's output **verbatim**. If a section is missing, the relay is broken — re-run and watch for the orchestrator's raw output. Open an issue against `aa-code-review`.

### Findings reference a path that doesn't match my checkout

The orchestrator reviews HEAD + working-tree changes as they exist locally. If you've made local uncommitted changes since starting the review, the file:line references may drift. Commit or stash before invoking if you want deterministic refs.

### "I want to feed it a specific PR description / spec"

Pass it via the focus arg:

```
/aa-review focus: implements PROJ-12345; spec at docs/specs/payment-flow.md
```

The orchestrator will incorporate this as the primary review lens during intent reconstruction.

---

## Limits — what the local adapter does NOT do

| Capability | Status | Notes |
|---|---|---|
| Post comments to GitHub PR | ❌ | Not implemented. Future `github-actions.md` adapter. |
| Post comments to GitLab MR | ❌ | Not implemented. Future `gitlab-ci.md` adapter. |
| Run on a remote PR you didn't check out | ❌ | Local adapter requires the branch checked out. |
| Block merge / mark as required reviewer | ❌ | Read-only by design. |
| Persist findings across sessions | ❌ | Each invocation is fresh. |
| Suppress known false positives automatically | ❌ | No suppression mechanism. |
| Auto-fix issues | ❌ | Read-only. Suggestions are inline in findings; you apply them manually. |
| Pin orchestrator to Opus regardless of session | ❌ | Orchestrator inherits the user's session model. Use an Opus session for max synthesis quality. Lenses pin Sonnet by default; `--deep` flips them to Opus per call. |

If you need any of the above, you're outside the local adapter's scope — use a different tool or wait for the next adapter.
