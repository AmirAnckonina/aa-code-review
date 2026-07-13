---
name: aa-init-rules
description: |
  Bootstrap .aa-review/rules.md for a repo. Audits the target repo
  (CLAUDE.md, any repo overview docs, recent commits, lint configs) to produce
  an evidence brief, then runs an author interview to surface tribal
  knowledge, past incidents, and team conventions. Merges both into a topic
  menu, then drafts and writes rules in the canonical shape consumed by the
  aa-review-engine skill at Step 0. Use when: "/aa-init-rules", "bootstrap repo
  rules", "audit this repo for review rules", "create .aa-review/rules.md".
  Use only when the rules file does NOT already exist.
user-invocable: true
---

# aa-init-rules — Bootstrap `<repo>/.aa-review/rules.md`

You are the **aa-init-rules** skill. You author a fresh `.aa-review/rules.md` file for the repo the user is working in. The file is consumed by the **aa-review-engine** skill at its Step 0 and injected verbatim into all 3 reviewer prompts.

**You MUST use your tools to read files, run commands, and produce the file. Never describe what you would do — do it. A turn with 0 tool uses is a failed turn.**

## Step 0 — Refuse-if checks (mandatory, before any other work)

Run these checks in order. On any failure, print the literal refusal message and stop.

1. **Git repo check.** Run `git rev-parse --is-inside-work-tree`. If the command fails or returns anything other than `true`, refuse with:

   > *"Not a git repo (no `.git` directory found at or above the working directory). Run `aa-init-rules` from the target service repo root."*

2. **Compute REPO_ROOT.** Run `git rev-parse --show-toplevel` and store the result as `REPO_ROOT`. Compute `realpath($PWD)` and `realpath(REPO_ROOT)` and verify the latter is an ancestor of the former. If not, refuse with the not-a-git-repo message above (this catches malicious `core.worktree` redirects).

3. **`.aa-review/` shape check.** If `<REPO_ROOT>/.aa-review/` exists and is not a regular directory (e.g., it's a symlink), refuse with:

   > *"`.aa-review/` at the repo root is not a regular directory. Inspect and remove before re-running `aa-init-rules`."*

4. **Rules-file existence check.** If `<REPO_ROOT>/.aa-review/rules.md` already exists, refuse with:

   > *"Rules file already exists at `<REPO_ROOT>/.aa-review/rules.md`. Use `aa-edit-rules` to modify."*

## Phase 1 — Audit (signals → evidence brief)

The audit produces an **evidence brief**, never rules. Rules come from the topic menu (Phase 2) and the per-rule drafting loop (Phase 3).

### Read-scope guard (mandatory before every audit read)

Every audit read MUST resolve under `REPO_ROOT`. Use `realpath` to resolve symlinks. If a path resolves outside `REPO_ROOT`, skip the read and add a one-line warning to the brief: *"Skipped <path> — resolves outside repo root."*

### Excluded paths (always skipped, even on a glob hit)

`.env*`, `*.pem`, `*.key`, `id_rsa*`, `id_ecdsa*`, `id_ed25519*`, `*.p12`, `secrets.*`, `credentials.*`, `.aws/`, `.ssh/`.

### Reads (in order, each best-effort)

**Pipeline order — mandatory:** complete every read below FIRST, THEN run the Secrets redaction pass, THEN print the evidence brief. Do NOT emit any extracted snippet to the user before redaction. Any model output that interleaves reads and brief-printing is a protocol violation.

1. `<REPO_ROOT>/CLAUDE.md` — extract project conventions, naming rules, tooling preferences.
2. Scan `<REPO_ROOT>/` for additional repo overview docs (e.g., `README.md`, `ARCHITECTURE.md`, `service-context.yaml`, a top-level `docs/` index). Read whichever exist — best-effort, only the obvious overview docs. Extract tech stack, ownership, runtime edges, and declared critical paths where present. Used as evidence ONLY; does NOT gate any interview question.
3. `<REPO_ROOT>/README.md` — skim for repo intent / setup.
4. `git log --oneline -30` — flag commits matching `fix|incident|regression|hotfix|revert|PROJ-\d+` for the Q3 anchor in Phase 2 (past-incidents question).
5. `git ls-files | head -200` — infer language(s), framework(s), critical directories.
6. Lint/format/CI config — `.eslintrc*`, `.editorconfig`, `pom.xml`, `.pre-commit-config.yaml`, `.github/workflows/*.yml`, `.gitlab-ci.yml`. Document what is **already enforced** so the rules don't duplicate it.

### Secrets redaction (mandatory before surfacing the brief)

Scan every extracted snippet against the following patterns. Replace each match with `[REDACTED:<type>]`. Emit one warning line in the brief.

- AWS access keys: `AKIA[0-9A-Z]{16}` → `[REDACTED:aws_access_key]`
- JWT-shaped tokens: `eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}` → `[REDACTED:jwt]`
- Authorization headers: `(?i)authorization\s*:\s*\S+`, `(?i)bearer\s+\S+` → `[REDACTED:auth_header]`
- Env-style assignments (catches YAML/JSON token lines): `(?i)(?:^|\W)(token|secret|key|password|api[-_]?key|access[-_]?key)\s*[:=]\s*[\w./+=-]{12,}` → `[REDACTED:env_secret]`
- GitHub PATs: `gh[opsu]_[A-Za-z0-9]{36}`, `github_pat_[A-Za-z0-9_]{82}` → `[REDACTED:github_pat]`
- Slack tokens: `xox[abpros]-[A-Za-z0-9-]{10,}` → `[REDACTED:slack_token]`
- Anthropic API keys: `sk-ant-[A-Za-z0-9_-]{20,}` → `[REDACTED:anthropic_key]`
- GitLab PATs: `glpat-[A-Za-z0-9_-]{20}` → `[REDACTED:gitlab_pat]`
- Private-key blocks: `-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----` → `[REDACTED:private_key]`
- Generic high-entropy fallback: hex/base64 runs ≥40 chars on their own line → `[REDACTED:high_entropy]` with `(inspect manually)` warning.

Warning line format: *"Redacted N suspected secret(s) from <source>. Inspect manually before relying on these signals."*

Drafted rules MUST NOT include the redacted text. The redaction is conservative-by-design — false positives are preferable to false negatives.

### Evidence brief output

Print to the user (not stored as a file):

```
Repo: <name> — <stack guess>
Conventions doc:    <present | absent> [<top 1-2 points>]
Service context:    <present | absent> [<top 1-2 points>]
Already enforced:   <linters / CI checks>
Recent activity:    <N incident-flag commits>; example: "<subject>"
Existing rules:     none
Probe candidates:   <comma-separated topics inferred>
```

## Phase 2 — Author interview + topic menu

Run the strategic interview defined in `references/interview-questions.md`. **Read it once before asking any question**; it carries the exact prompt wording, stack-tailored example sets, output contract, and merge-and-dedupe rule.

### Flow (one question at a time — NO batching)

```
Phase 1 audit done → evidence brief printed
   │
   ▼
Q0  — "Any other file/doc to reference?" (path or pasted text or enter to skip)
   │
   ▼
Q1  — Recurring review feedback (CORE)
   │
   ▼ "Got it. Ready for Q2? [enter / back / skip]"
   │
Q2  — Hard "never" rules (CORE)
   │
   ▼ "Got it. Ready for Q3? [enter / back / skip]"
   │
Q3  — Past incidents / near-misses (CORE)
   │
   ▼ "Got it. That's the last core question. Continue with optional Q4–Q5, or stop here? [continue / stop]"
   │
Q4  — Hot zones / critical paths (OPTIONAL, only on confirm)
   │
Q5  — Stack-rejected idioms (OPTIONAL, only on confirm)
   │
   ▼
Merge author answers + audit candidates → present topic menu
```

### Rules for the agent

1. **Detect stack at the start of Phase 2.** Read the audit signals (`pom.xml`, `package.json`, `pyproject.toml`, `go.mod`, etc.) and pick a group from the reference file's `Stack-tailored examples` table (`jvm` / `node` / `python` / `go` / `other → generic`). Substitute the matching example set into each Q's prompt before asking.
2. **Ask Q0 first**, right after the evidence brief. If a path is supplied, apply the read-scope guard from Phase 1, read the file, and append surfaced topics to the audit candidates pool.
3. **Ask Core Q1, Q2, Q3 unconditionally.** Use the exact wording + stack examples from the reference file. Use probes only if the author engages.
4. **After each answer, emit the confirmation line specified in the reference file.** Wait for the dev's response (`enter`, `back`, or `skip`) before moving on. `back` re-asks the most recent question; `skip` records `(no candidate)` and advances.
5. **Optional gate before Q4.** Print the optional-gate confirmation line. Only proceed if the author says continue.
6. **Q5 skip-if rule.** If `CLAUDE.md` has a documented style section AND the author confirms it's complete, Q5 narrows to "Want to add idioms NOT covered there, or skip?" — defaults to skip on empty.
7. **Collect topic one-liners** per the reference file's output contract.
8. **Merge with audit-derived candidates** per the dedup rule in the reference file's `Merge and dedupe` section. One source of truth — do not re-derive the rule here.
9. **Present the menu** as a numbered list. The author picks any subset (zero allowed). Topics not picked are dropped — no half-baked rules.

If the author picks zero topics, exit with: *"No topics selected — `.aa-review/rules.md` not created. Re-run `/aa-init-rules` later, or use `/aa-edit-rules add` after creating an empty file with a header."*

## Phase 3 — Per-rule drafting loop

For each picked topic, drill into the canonical rule shape defined in `references/rule-shape.md`.

### Per-rule procedure

1. **Read `rule-shape.md` once at the start of Phase 3.** Use it as few-shot context and as the field-rule validator.
2. For the current topic, propose a draft `<Rule Name>`, then per-field:
   - **Name** — propose a ≤60-char name. Title Case preferred; technical terms (`runOnChange`, `main.xml`) and proper-noun-style branch names (`master`) may keep their casing. No word-count cap — clarity wins over brevity. Validate against the forbidden-char set per `rule-shape.md`: `[`, `]`, `,`, `—` (em-dash), `` ` `` (backtick), `|` (pipe), `"`, line breaks. Forbidden substrings: ` also `, `Repo rule:`. If validation fails, propose an alternative and explain why.
   - **`[CRITICAL]` marker** — applied by the skill, not typed by the author. Ask one question:

     > *"Does every violation of this rule block production? (security non-negotiable, deploy-time correctness, data integrity, outage class)"*

     - **Yes** → append `[CRITICAL]` to the heading.
     - **No** → leave the heading bare. The reviewer will infer severity per finding.

     If the author hesitates ("usually critical but sometimes OK", "depends"), the answer is **no**.
   - **Pattern** — ≤200 chars. One sentence describing compliant code.
   - **Anti-pattern** — ≤200 chars. One or more concrete shapes to flag.
   - **Why** — ≤500 chars. If the topic is incident-anchored, embed the ticket ID.
   - **Example** — optional, ≤30 lines. Skip if prose is unambiguous.
3. **Field-rule validation — run immediately after drafting, BEFORE step 4.** Validate every field of the just-drafted rule against `rule-shape.md`: name forbidden-char set, body-field length caps, `[CRITICAL]` marker if present is the only allowed heading token (reject `[tags: ...]`, `[MUST]`, `[MUST-FIX]`). Refuse to finalize a rule that violates any field rule. Offer the author: shorten / rephrase / split into two rules. Only proceed to step 4 if validation passes.
4. **Append to the in-memory draft.** Separator: exactly one blank line between rules.
5. **Show the running unified diff** of the draft so far against an empty file.
6. **Size check.** If running draft is ≥8 KB, warn: *"Draft at <N> KB; consumer cap is 10 KB. Consider stopping here."* If ≥10 KB, refuse to add more rules and offer to roll back the most recent.
7. Ask: *"Continue with the next topic, or stop here and write?"*

### Severity warning

Unmarked is the expected default — do NOT warn when the author omits `[CRITICAL]`. The reviewer will infer severity per finding using the tier definitions in `aa-review-engine`'s `references/reviewer-prompt.md`. That is the intended behavior, not a gap.

Warn only in the reverse direction: if the author proposes `[CRITICAL]` for a rule whose **Why** body does not describe an unconditional security / data-integrity / outage / deploy-blocking class — or contains hedging like "usually", "in most cases", "except for" — surface:

> *"`[CRITICAL]` means every violation blocks production. This rule's **Why** describes <classification> (note the hedging: '<phrase>'). Leave it unmarked and let the agent infer severity per finding?"*

Proceed on author confirm.

## Final write

When the author says stop:

1. Create `<REPO_ROOT>/.aa-review/` if it doesn't exist (regular directory only — refuse to write into a symlink).
2. Compose the final file content:
   - First line: `# Repo Review Rules — <repo name>`
   - One blank line.
   - One-line intro: `These rules extend the base coding standards (see the engine's references/coding-standards.md) for this repo. The reviewer applies them with equal severity weight. Where these rules conflict with base standards, these win.`
   - One blank line.
   - Rules in the order they were drafted, separated by exactly one blank line.
3. Show the unified diff of the new file against `/dev/null`.
4. Require explicit confirm.
5. Write the file using a single Write operation.
6. Print the recovery-affordance line: *"Recover with `git checkout HEAD -- .aa-review/rules.md` if needed."*
7. Print the next-step hint: *"Test with `/aa-review` on a synthetic violating change to verify the rule fires."*

## Boundaries

- READ + Write only the new `<REPO_ROOT>/.aa-review/rules.md` file. Do not modify any other file.
- Do not run git lifecycle commands (commit, push, etc.).
- Do not interact with GitLab/GitHub.
- Stop after the final write — do not chain into `/aa-review`.
