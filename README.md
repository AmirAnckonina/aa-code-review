# aa-code-review

> An opinionated, multi-lens code reviewer for Claude Code — a set of skills and slash commands that review the current branch's diff and produce severity-ranked findings.

`aa-code-review` is a package of Claude-Code-facing **prompt artifacts** (skills, a slash command, an output adapter). There is no application code — every file is Markdown. The repo distributes itself by symlinking its contents into `~/.claude/`, so you can run `/aa-review` against any git repo on your machine with no other install step.

**What it does.** Manual review is slow and inconsistent. This package gives you a repeatable 6-lens reviewer (Correctness / Security / Reliability / Design / Performance+Testing / Readability), layered with optional per-repo rules, producing severity-ranked findings (🔴 / 🟡 / 🔵) in a couple of minutes.

**Scope.** Read-only and local. The agent reads the diff and prints a Markdown report; you decide what to act on. No PR/MR posting, no git lifecycle commands.

---

## What's in here

| Path | Purpose |
|---|---|
| `skills/aa-review-orchestrator/` | **The orchestrator.** Runs at top level when invoked by `/aa-review`. Loads context, resolves the diff, pre-reads files, dispatches 6 lens subagents in parallel, cross-checks/dedupes, emits the report. Skill-not-agent on purpose — only top-level contexts can spawn subagents in Claude Code. |
| `skills/aa-coding-standards/` | 13 language-agnostic base standards (error handling, security, null safety, etc.). |
| `skills/aa-review-lenses/` | The review scoring system: 6 lenses, severity rules, verdict math, report format. Read by lens subagents at dispatch time. |
| `skills/aa-init-rules/` | `/aa-init-rules` — bootstrap `<repo>/.aa-review/rules.md` via an audit + author interview. |
| `skills/aa-edit-rules/` | `/aa-edit-rules` — natural-language add / refine of an existing `.aa-review/rules.md`. |
| `commands/aa-review.md` | `/aa-review` slash command — thin wrapper that invokes the orchestrator skill. |
| `adapters/local.md` | How `/aa-review` surfaces results locally (the default and only implemented adapter). |
| `examples/.aa-review/rules.md` | A small, generic example of a repo rules file. |
| `install.sh` | Idempotent symlink installer. |

All artifacts use the `aa-` prefix to avoid collision with personal/global skills (e.g. `coding-standards` vs `aa-coding-standards`).

---

## Getting started

### Prerequisites

- **Claude Code CLI** — `claude` available on PATH (`claude --version`).
- **Git** — the reviewer computes the diff vs trunk.
- **`jq`** — optional; the installer uses it to merge permission rules into `~/.claude/settings.json`. Without it, the installer prints the rules to add manually.
- No language runtimes, no build step, no test suite — everything is Markdown.

### Install

```bash
git clone <your-fork-url> ~/repositories/aa-code-review
cd ~/repositories/aa-code-review
./install.sh
```

The installer symlinks every entry under `skills/` / `commands/` / `agents/` into `~/.claude/`, and merges the package's required `Read(...)` allow-rules into `~/.claude/settings.json`. It is idempotent — re-running is safe.

Override the target for a dry run:

```bash
CLAUDE_HOME=/tmp/x ./install.sh
```

Because everything lands as a symlink, edits in this repo go live in any **active** Claude Code session immediately — re-run `install.sh` only when a new skill/command is added or the required permissions change.

### Uninstall

```bash
for kind in agents skills commands; do
  find ~/.claude/$kind -maxdepth 1 -type l -lname '*/aa-code-review/*' -delete
done
```

Permission rules merged into `~/.claude/settings.json` are not auto-removed.

---

## Usage

Run these inside a target git repo.

### 1. First-time setup per repo (optional, ~5 min)

```
/aa-init-rules
```

Interactively bootstraps `<repo>/.aa-review/rules.md` — repo-specific rules layered on top of the 13 base standards. It audits the repo (CLAUDE.md, overview docs, recent commits, lint configs), runs a short author interview (recurring feedback, hard "never" rules, past incidents), and drafts rules in the canonical shape. Run once per repo. Skip it and the reviewer still works from base standards + lens judgment.

To refine later — *"the X rule is too strict"*, *"mark Y as critical"*:

```
/aa-edit-rules
```

### 2. Run a review

```
/aa-review [base=<ref>] [--deep] [adapter=<name>] [focus text]
```

- `base=<ref>` — explicit base ref (default: `origin/develop`, falling back to `origin/main` / `origin/master`).
- `--deep` — run all 6 lens subagents on Opus instead of Sonnet.
- `adapter=<name>` — output adapter (default and only implemented: `local`).
- free-form text — focus areas / notes / a spec link.

The slash command invokes the **`aa-review-orchestrator` skill** at the top level of your session (skills run in the parent context, which gives the orchestrator the `Agent` tool to dispatch lens subagents in parallel). The orchestrator:

1. Reads target-repo context — `CLAUDE.md`, `.claude/context.md`, `.aa-review/rules.md` (all optional).
2. Resolves the base ref and computes the merge-base.
3. Pre-reads every changed file once; injects content into all 6 lens prompts (lenses never re-read or re-diff).
4. Launches the 6 lenses in parallel.
5. Cross-checks pairs, dedupes, assigns IDs (`CRT-N` / `IMP-N` / `SUG-N`), applies `[CRITICAL]`-rule promotion.
6. Emits a 3-layer report: verdict + TL;DR + lens-coverage table + finding list, with drill-down (`expand <ID>` / `show <Lens>`).

Verdict is deterministic from the highest severity: `🔴 BLOCKER` / `🟡 NEEDS WORK` / `🔵 SHIP IT` (`✅` if no findings).

See [`adapters/local.md`](adapters/local.md) for the full local flow, drill-down protocol, and troubleshooting.

---

## How it works (architecture)

See [`CLAUDE.md`](CLAUDE.md) for the runtime architecture and the source-of-truth / drift-hazard map. Key conventions:

- **`aa-` prefix** on every artifact (collision avoidance with personal skills).
- **3 severity tiers only** (🔴 / 🟡 / 🔵). No praise/positive category.
- **`[CRITICAL]`** is the only severity marker in `.aa-review/rules.md` rule headings.
- **No agent memory.** Persistent learning lives in `<target>/.aa-review/rules.md` — human-curated, diffable, citeable by name.
- **Read-only + local.** No git lifecycle commands, no MR/PR posting. Remote adapters (`github-actions`, `gitlab-ci`) are placeholders for future work.

---

## Development

There is no build, lint, or test suite. Iteration is read → edit → re-run the slash command. To add a new skill/command, drop it under `skills/<name>/` (or `commands/<name>.md`), follow the sibling-skill conventions, and re-run `./install.sh` once to create the symlink.

---

## License

MIT — see [LICENSE](LICENSE).
