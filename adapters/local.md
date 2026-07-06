# Local Invocation Adapter

How to run `/aa-review` on a local branch. No GitHub/GitLab interaction, no CI — just `/aa-review` against the current branch's diff.

> **Scope:** local only. Future adapters (`github`, `gitlab`) will document remote/CI invocation — see `adapters/README.md`. Today, `local` is the only implemented adapter (default).

---

## Prerequisites

Before first use, in this order:

| # | Requirement | How to verify |
|---|---|---|
| 1 | Claude Code installed | `claude --version` |
| 2 | `aa-code-review` plugin installed | `claude plugin list` shows `aa-code-review` |
| 3 | Target repo is a git repo with a defined trunk | `git symbolic-ref refs/remotes/origin/HEAD` resolves cleanly |
| 4 | Current branch has commits ahead of trunk | `git log --oneline $(git merge-base HEAD @{upstream})..HEAD` shows ≥1 commit |
| 5 | Repo has a `CLAUDE.md` at root (recommended, not required) | `cat CLAUDE.md` |
| 6 | Repo has `.aa-review/rules.md` (recommended — repo-specific rules) | `cat .aa-review/rules.md` — bootstrap with `/aa-init-rules` if missing |

If #5 or #6 are missing, `/aa-review` skips them silently — they're optional context, not gates. But the review will be lower-fidelity without them (no repo-specific rules means findings come from base coding standards + reviewer judgment only).

---

## Install (one-time)

```bash
# from a local clone (development)
claude plugin marketplace add ~/repositories/agentic-code-review/aa-code-review
claude plugin install aa-code-review

# or once published, from the marketplace entry for AmirAnckonina/aa-code-review
```

Uninstall: `claude plugin uninstall aa-code-review`.

The plugin provides:
- the **`aa-review-engine`** skill — orchestrates Steps 0–6, dispatches the 3 reviewers
- the **`aa-reviewer`** agent type — the read-only subagent charter dispatched in background
- the **`aa-init-rules`** / **`aa-edit-rules`** skills — bootstrap and maintain `.aa-review/rules.md`
- the **`/aa-review`** slash command — thin relay into the engine skill

Edits to a local clone take effect immediately in any active Claude Code session that has the plugin installed from that path — no reinstall for content changes. Reinstall only if the plugin's manifest (commands/agents/skills list) changes.

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
/aa-review --deep                              # Opus for all 3 reviewers (default: Sonnet)
/aa-review base=main                           # Override base ref
/aa-review adapter=local                       # Output adapter (default: local — only implemented one)
/aa-review focus on the auth changes           # Free-form focus areas
/aa-review --deep base=main focus on race conditions    # Combine
```

The slash command invokes the **`aa-review-engine`** skill (which runs at the top level of your session — that's what lets it dispatch 3 reviewer subagents in the background via the `Agent` tool). The engine:

1. Reads `CLAUDE.md`, `.claude/context.md`, `.aa-review/rules.md` if present; parses args.
2. Resolves the base ref, first that succeeds: explicit `base=<ref>` → `@{upstream}` → `origin/HEAD` → `origin/main` / `origin/develop` / `origin/master` fallbacks.
3. Computes the merge-base, collects committed + working-tree + untracked changes (binary and hidden-dir filtered), pre-reads every surviving file ONCE.
4. Prints a brief intent summary.
5. Dispatches 3 `aa-reviewer` subagents (Bugs / Security / Quality) in the background, on Sonnet by default or Opus with `--deep`; retries a failed reviewer once, aborts if ≥2 of 3 still fail.
6. Synthesizes: clusters, dedupes, applies `[CRITICAL]`-rule promotion, assigns IDs, computes the verdict.
7. Prints the 3-layer markdown report.

### Empty diff handling

If the current branch == trunk (no commits ahead), the engine stops and tells you. Switch branches and retry.

### Long branches (warning)

The engine reads **every changed file** at HEAD (or working tree, for uncommitted/untracked changes) before dispatching reviewers. On a branch with ≥50 changed files or ≥3K diff lines, expect a longer pre-read before dispatch. Acceptable for local scale; optimization deferred.

---

## Reading the report

> **Definitive contract:** `skills/aa-review-engine/references/report-format.md`. This section is a reading guide for terminal output — for the exact grammar, severity binding, and drill-down protocol, read that file.

The report renders in **three layers** (progressive disclosure). Layer 1 is the default. Layers 2 and 3 surface on demand.

### Layer 1 (what prints by default)

| Section | What it tells you |
|---|---|
| **Verdict + TL;DR** | BLOCKER / NEEDS WORK / SHIP IT + 1-2 sentence rationale |
| **Findings Summary** | Counts per severity (🔴 / 🟡 / 🔵) + repo-rule citation count |
| **Reviewer Coverage table** | Per-reviewer status: clean, N findings, or ❌ NOT REVIEWED. Top finding ID per reviewer |
| **Findings** | One line per finding: `<emoji> <ID> [<Reviewer>] [⚠️ Repo rule]? — file:line — <title>`. No mechanism prose, no fix sketch — those are Layer 2 |
| **Drill-down hint** | A single line under the Findings header: *"`expand <ID>` for detail · `show <Reviewer>` for full reviewer output"* |
| **Activity Summary** | Diagnostics: files pre-read, reviewer models, dedupe count, any reviewer that failed and was retried. |

**Top-N truncation.** If total findings >20, all 🔴 and 🟡 print in full; 🔵 print until 20 total; the remainder collapse into a single `+M more — expand to see` line. Suppressed findings remain expandable by ID.

### Verdict

Verdict math: any 🔴 → **BLOCKER**; any 🟡 (no criticals) → **NEEDS WORK**; only 🔵 or no findings → **SHIP IT**. Deterministic — if it surprises you, look at the highest-severity finding.

### Severity calibration

Per the 3-criteria gate (see `skills/aa-review-engine/references/reviewer-prompt.md`), 🔴 CRITICAL findings must articulate reachability, named invariant, and no-mitigation in their mechanism's first sentence. If you see a 🔴 with a vague articulation, that's a reviewer cargo-culting the gate — tighten the reviewer checklist or repo rules accordingly.

---

## Drill-down (Layers 2 & 3)

After Layer 1 prints, ask follow-ups in the same session:

| Ask | Layer | What you get |
|---|---|---|
| `expand CRT-1` | 2 | Title, mechanism prose (what's wrong, why, impact, suggested fix), full repo-rule body if cited, surrounding code context (≥5 lines before/after) |
| `expand SUG-5` | 2 | Same as above. Works on truncated findings too (the ones hidden by `+M more`) |
| `expand suggestions` | 2 | Layer 2 for every suppressed 🔵 finding in the truncated tail |
| `show Security` | 3 | Full rationale the Security reviewer returned, its checklist headers, and any items it skipped |

The engine has the diff + file contents in memory from the run, so drill-down is fast (no re-read).

---

## Troubleshooting

### "Cannot determine base ref"

The engine resolves, in order: explicit `base=<ref>` → `@{upstream}` → `origin/HEAD` → `origin/main` / `origin/develop` / `origin/master`. If none resolve, the review aborts. Fix:

```bash
# Explicitly set origin/HEAD to your trunk branch
git remote set-head origin --auto
# or
git remote set-head origin main
```

Or pass `base=<ref>` explicitly.

### "Reviewer X failed after retry — NOT REVIEWED"

Subagent failure. Common causes: rate limiting, timeout, model error. Re-run `/aa-review`. If it persists, run with `--deep` (Opus is more reliable for complex diffs but slower/costlier). If ≥2 of 3 reviewers fail, the engine aborts the report (verdict can't be trusted on near-empty coverage).

### Reviewers ran inline / took 15+ min

Verify the plugin is installed so the `aa-reviewer` agent type exists, and that `/aa-review` was invoked at top level, not from a subagent.

### Report missing the Reviewer Coverage table

The slash command should relay the engine's output **verbatim**. If a section is missing, the relay is broken — re-run and watch for the engine's raw output. Open an issue against `aa-code-review`.

### Findings reference a path that doesn't match my checkout

The engine reviews HEAD + working-tree changes as they exist locally. If you've made local uncommitted changes since starting the review, the file:line references may drift. Commit or stash before invoking if you want deterministic refs.

### "I want to feed it a specific PR description / spec"

Pass it via the focus arg:

```
/aa-review focus: implements PROJ-12345; spec at docs/specs/payment-flow.md
```

The engine will incorporate this as the primary review focus during intent reconstruction.

---

## Limits — what the local adapter does NOT do

| Capability | Status | Notes |
|---|---|---|
| Post comments to GitHub PR | ❌ | Not implemented. Planned `github` adapter — see `adapters/README.md`. |
| Post comments to GitLab MR | ❌ | Not implemented. Planned `gitlab` adapter — see `adapters/README.md`. |
| Run on a remote PR you didn't check out | ❌ | Local adapter requires the branch checked out. |
| Block merge / mark as required reviewer | ❌ | Read-only by design. |
| Persist findings across sessions | ❌ | Each invocation is fresh. |
| Suppress known false positives automatically | ❌ | No suppression mechanism. |
| Auto-fix issues | ❌ | Read-only. Suggestions are inline in findings; you apply them manually. |
| Pin the engine to Opus regardless of session | ❌ | The engine inherits the user's session model. Use an Opus session for max synthesis quality. Reviewers pin Sonnet by default; `--deep` flips them to Opus per call. |

If you need any of the above, you're outside the local adapter's scope — use a different tool or wait for the next adapter.
