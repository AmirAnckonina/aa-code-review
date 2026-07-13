# aa-code-review

> A Claude Code plugin that reviews the current branch's diff with three parallel, read-only reviewers and produces a deterministic, severity-ranked verdict.

`aa-code-review` is a Claude Code **plugin** — a package of skills, an agent, and a slash command. There is no application code — every file is Markdown, installed and versioned as a plugin via the `claude plugin` CLI.

**What it does.** Manual review is slow and inconsistent. This plugin dispatches three focused reviewers — **Bugs**, **Security**, **Quality** — as background subagents against the same pre-read diff, layers in optional per-repo rules, cross-checks and dedupes their findings, and prints a severity-ranked report (🔴 / 🟡 / 🔵) with a deterministic verdict in a couple of minutes.

**Scope.** Read-only and local. The reviewers read the diff and print a Markdown report; you decide what to act on. No PR/MR posting, no git lifecycle commands.

---

## The three reviewers

**Mechanism.** The engine pre-reads the diff once, then dispatches all three reviewers as **independent background subagents** against that same snapshot — no shared state, so none of them can anchor on another's conclusions. Each receives only its own charter and checklist (plus any repo-specific rules from `.aa-review/rules.md`), reviews **only the changed lines**, and returns findings that cite either code evidence or a named rule — never internal state. The engine then reconciles the three streams: a defect caught by two reviewers is **deduped** (highest severity wins, mechanisms merged), and 3+ related findings collapse into one **systemic** finding. The overlap is deliberate — it's how a bug that is *also* a security hole gets caught from both angles and reconciled, rather than slipping through a seam.

Each reviewer applies its own checklist (`skills/aa-review-engine/references/{bugs,security,quality}.md`):

| Reviewer | Charter | What it examines |
|---|---|---|
| **Bugs** | Correctness & Reliability | Logic errors, edge cases and off-by-ones, null / undefined safety, error handling and propagation, failure modes, resource and lifecycle handling, and operational concerns (retries, timeouts, idempotency). Sub-checklists: *Correctness & Logic*, *Reliability & Operations*. |
| **Security** | Security & Input Safety | Injection (SQL / command / path / template), authentication and authorization gaps, secret handling and leakage, input and boundary validation, unsafe deserialization, and trust-boundary crossings. |
| **Quality** | Design, Performance & Testing, Readability | SOLID and encapsulation, interface and API design, performance (algorithmic complexity, hot paths, allocations, N+1), test coverage and test quality, naming, comments, and consistency with repo conventions. Sub-checklists: *Design & Structure*, *Performance & Testing*, *Readability & Conventions*. |

These three group the six v1 lenses (Correctness, Reliability, Security, Design, Performance+Testing, Readability) into coherent charters — *does it break* / *is it exploitable* / *is it healthy* — which sharpens each reviewer's focus and cuts the cross-reviewer dedup surface. Every original check is preserved; nothing was dropped in the merge. Findings are capped at 10 per reviewer, severity-first (the lowest-severity items are dropped first if the cap is hit).

---

## What's in here

| Path | Purpose |
|---|---|
| `skills/aa-review-engine/` | **The engine.** Runs at top level when invoked by `/aa-review`. Loads context, resolves the base ref, pre-reads changed files, dispatches 3 `aa-reviewer` subagents in the background, synthesizes their findings, emits the report. Skill-not-agent on purpose — only top-level contexts can dispatch subagents in Claude Code. |
| `agents/aa-reviewer.md` | The reviewer subagent charter — read-only tools only (`Read`, `Grep`, `Glob`; no `Bash`). Dispatched three times per run (Bugs / Security / Quality), each with a different checklist. |
| `skills/aa-init-rules/` | `/aa-init-rules` — bootstrap `<repo>/.aa-review/rules.md` via an audit + author interview. |
| `skills/aa-edit-rules/` | `/aa-edit-rules` — natural-language add / refine of an existing `.aa-review/rules.md`. |
| `commands/aa-review.md` | `/aa-review` slash command — thin relay that invokes the engine skill. |
| `adapters/README.md` | The adapter contract — the two extension seams (context source, report sink) and how to add a new adapter. |
| `adapters/local.md` | How `/aa-review` surfaces results locally (the default and only implemented adapter). |
| `examples/.aa-review/rules.md` | A small, generic example of a repo rules file. |

---

## Install

```bash
# from a local clone (development)
claude plugin marketplace add ~/repositories/agentic-code-review/aa-code-review
claude plugin install aa-code-review@aa-tools

# or once published, from the marketplace entry for AmirAnckonina/aa-code-review
```

Uninstall: `claude plugin uninstall aa-code-review`.

No language runtimes, no build step, no test suite — everything is Markdown.

---

## Usage

Run these inside a target git repo, in a Claude Code session with the plugin installed.

### 1. First-time setup per repo (optional, ~5 min)

```
/aa-init-rules
```

(Still skill-invoked — no dedicated slash command.) Interactively bootstraps `<repo>/.aa-review/rules.md` — repo-specific rules layered on top of the base coding standards. It audits the repo (CLAUDE.md, overview docs, recent commits, lint configs), runs a short author interview (recurring feedback, hard "never" rules, past incidents), and drafts rules in the canonical shape. Run once per repo. Skip it and the reviewers still work from base standards + judgment.

To refine later — *"the X rule is too strict"*, *"mark Y as critical"*:

```
/aa-edit-rules
```

(Also skill-invoked.)

### 2. Run a review

```
/aa-review [base=<ref>] [--deep] [adapter=<name>] [focus text]
```

- `base=<ref>` — explicit base ref. Resolution chain: explicit `base=` → `@{upstream}` → `origin/HEAD` → `origin/main` / `origin/develop` / `origin/master`.
- `--deep` — run all 3 reviewer subagents on Opus instead of Sonnet.
- `adapter=<name>` — output adapter (default and only implemented: `local`).
- free-form text — focus areas / notes / a spec link.

### How a review runs

`/aa-review` relays into the **`aa-review-engine`** skill at the top level of your session (skills run in the parent context, which gives the engine the `Agent` tool needed to dispatch subagents). The engine runs Steps 0–6: it reads target-repo context and args (Step 0), resolves the base ref and collects the scoped diff — committed, working-tree, and untracked changes, pre-read once (Step 1) — prints an intent summary (Step 2), dispatches the three `aa-reviewer` subagents (Bugs / Security / Quality) in the background with a retry-once policy and an abort if ≥2 of 3 fail (Step 3), collects their findings (Step 4), synthesizes — clustering, dedupe, `[CRITICAL]`-rule promotion, ID assignment, and verdict computation (Step 5) — and emits the 3-layer report (Step 6). Verdict is deterministic from the highest severity: `🔴 BLOCKER` / `🟡 NEEDS WORK` / `🔵 SHIP IT`.

See [`adapters/local.md`](adapters/local.md) for the full local flow, drill-down protocol (`expand <ID>` / `show <Reviewer>`), and troubleshooting.

### Extending with a new adapter

The engine touches only two seams: context source (Step 1) and report sink (Step 6). See [`adapters/README.md`](adapters/README.md) for the contract — adding an adapter (e.g. `github`, `gitlab`) requires no engine changes.

---

## Permissions (least privilege)

The plugin never touches your settings files. Enforcement is structural: the `aa-reviewer` agent is granted only read-only tools (`Read`, `Grep`, `Glob` — no `Bash`, no `Edit`/`Write`), so it physically cannot run shell commands or mutate the repo; the engine forbids git lifecycle commands; and gitignored files (e.g. `.env`) never enter review scope.

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

---

## How it works (architecture)

See [`CLAUDE.md`](CLAUDE.md) for the runtime architecture and the ownership map. Key conventions:

- **3 severity tiers only** (🔴 / 🟡 / 🔵). No praise/positive category.
- **`[CRITICAL]`** is the only severity marker in `.aa-review/rules.md` rule headings.
- **No agent memory.** Persistent learning lives in `<target>/.aa-review/rules.md` — human-curated, diffable, citeable by name.
- **Read-only + local.** No git lifecycle commands, no MR/PR posting. Remote adapters (`github`, `gitlab`) are planned — see `adapters/README.md`.

---

## Development

There is no build, lint, or test suite. Iteration is read → edit → re-run the slash command against a target repo with the plugin installed from your local clone. To add a new skill/command, drop it under `skills/<name>/` (or `commands/<name>.md`), follow the sibling-skill conventions, and update `.claude-plugin/plugin.json` if the manifest needs it.

---

## License

MIT — see [LICENSE](LICENSE).
