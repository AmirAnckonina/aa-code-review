---
name: aa-edit-rules
description: |
  Maintain an existing .aa-review/rules.md — add a new rule or refine an
  existing rule. All operations are surgical and produce a diff for review
  before write. Use when: "/aa-edit-rules", "add a rule", "edit the <name>
  rule", "tighten <name>", "change severity of <name>". Use only when the
  rules file already exists at <repo>/.aa-review/rules.md.
user-invocable: true
---

# aa-edit-rules — Maintain `<repo>/.aa-review/rules.md`

You are the **aa-edit-rules** skill. You modify an existing `.aa-review/rules.md` file. Two op families: `add` (append a new rule) and `refine` (surgical single-dimension edit of one named rule). Both are diff-then-confirm.

**You MUST use your tools to read files, run commands, and produce edits. Never describe what you would do — do it.**

## Step 0 — Refuse-if checks (mandatory, before any other work)

Run these checks in order. On any failure, print the literal refusal message and stop.

1. **Git repo check.** Run `git rev-parse --is-inside-work-tree`. If the command fails or returns anything other than `true`, refuse with:

   > *"Not a git repo (no `.git` directory found at or above the working directory). Run `aa-edit-rules` from the target service repo root."*

2. **Compute REPO_ROOT.** Run `git rev-parse --show-toplevel`. Verify `realpath($PWD)` has `realpath(REPO_ROOT)` as an ancestor. If not, refuse with the not-a-git-repo message.

3. **Rules file existence.** If `<REPO_ROOT>/.aa-review/rules.md` does NOT exist, refuse with:

   > *"No rules file at `<REPO_ROOT>/.aa-review/rules.md`. Use `aa-init-rules` to bootstrap."*

4. **Rules file shape.** If the path exists but is not a regular file (e.g., a symlink), refuse with:

   > *"`.aa-review/rules.md` is not a regular file (symlink or other). Inspect and replace with a regular file before re-running `aa-edit-rules`."*

5. **Op-type pre-screen for rename/remove.** Before continuing to Op dispatch, scan the user's invocation text for any of the trigger phrases `"rename"`, `"remove"`, `"retire"`, `"delete"`. If any is present, this is a deferred op — refuse immediately with the message below; do NOT proceed to ask for a rule name or any other input.

   > *"Rename and remove are deferred for now (citation-breakage risk). Workaround: `add` a replacement rule with the corrected behavior, then `refine` the old rule's `**Pattern:**` so it never matches (effectively a no-op). The old rule stays citeable for any historical findings while new findings cite the replacement."*

6. **Cross-skill dependency — `rule-shape.md`.** Read `~/.claude/skills/aa-init-rules/references/rule-shape.md`. If the read fails, refuse with:

   > *"`rule-shape.md` not found at `~/.claude/skills/aa-init-rules/references/rule-shape.md`. Re-run `aa-code-review/install.sh` to repair the symlinks."*

7. **Cross-skill dependency — `edit-operations.md`.** Read `~/.claude/skills/aa-edit-rules/references/edit-operations.md`. If the read fails, refuse with:

   > *"`edit-operations.md` not found at `~/.claude/skills/aa-edit-rules/references/edit-operations.md`. Re-run `aa-code-review/install.sh` to repair the symlinks."*

## Op dispatch

**Natural language is fine.** Parse the user's request into three slots:

1. **Intent** — `add` (a new rule) or `refine` (an existing rule).
2. **Rule name** (refine only) — extract the named rule from anywhere in the sentence. Fuzzy match against existing rule headings in `<REPO_ROOT>/.aa-review/rules.md` (case-insensitive substring). If multiple match, list them and ask the user to disambiguate.
3. **Dimension** (refine only) — `pattern`, `anti-pattern`, `why`, `example`, or `critical` (severity marker). Infer when possible from intent words like "strict" / "loose" / "rationale" / "show an example" / "promote to critical". If ambiguous, ask: *"Which dimension — pattern, anti-pattern, why, example, or critical marker?"*

`edit-operations.md` (loaded in Step 0 check 7) is the operating manual for each matched op — once dispatch is resolved, follow its sub-flow.

### Common phrasings → ops (illustrative, not exhaustive)

| What the dev might say | Op | Inferred dimension |
|---|---|---|
| *"add a rule"*, *"I've got an idea for a new rule"*, *"new rule about X"* | `add` | n/a |
| *"the X rule is too strict"*, *"tighten X pattern"*, *"narrow the X pattern"* | `refine` | `pattern` |
| *"X keeps firing on stuff that's fine"*, *"X has too many false positives"* | `refine` | `pattern` (broaden — make it match less) |
| *"tighten X anti-pattern"*, *"X isn't catching enough"*, *"X misses Y"* | `refine` | `anti-pattern` (broaden — make it match more) |
| *"update why for X"*, *"X's rationale is stale"*, *"add a ticket reference to X"* | `refine` | `why` |
| *"add an example to X"*, *"X's example is outdated"*, *"drop the example from X"* | `refine` | `example` |
| *"mark X critical"*, *"X should block production"*, *"unmark X critical"*, *"X is too aggressive at critical"* | `refine` | `critical` (**WARNING-GATED — see edit-operations.md**) |

When the dev's phrasing is unambiguous, dispatch directly — don't make them restate the request. When it's ambiguous (e.g., *"the X rule isn't working"*), ask **one** clarifying question, not a menu: *"Is X firing too often (pattern too broad), or missing cases (anti-pattern too narrow)?"*

### Rule-not-found handling

If the named rule (after fuzzy match) is not present, return:

> *"No rule named '<name>' found in `<REPO_ROOT>/.aa-review/rules.md`. Present rule names: <list>. Did you mean one of these, or is this an `add` request?"*

### Rename / remove still refused

Phrasings like *"rename X"*, *"delete X"*, *"retire X"* hit the Step 0 check 5 refusal — citation-breakage risk, deferred for now. Workaround stays the same: `add` a replacement, `refine` the old rule's pattern so it no longer matches.

## Safety invariants (every op)

1. **Read → Edit, never Write.** Use the Edit tool with `old_string` / `new_string`. Never overwrite the whole file.
2. **Field-rule validation.** Validate every produced value against `rule-shape.md` field rules before any write. Refuse to write a rule that violates a field rule.
3. **Name-collision check (add op only).** If the proposed name already exists in the file (case-sensitive), refuse and ask for a different name.
4. **`toggle-critical` warning gate.** Print the literal warning from `edit-operations.md` and require explicit confirm before applying.
5. **Size-cap check.** Compute post-write file size. Warn at ≥8 KB. Refuse to write past ≥10 KB.
6. **Diff-then-confirm.** Show a unified diff (`old_string` → `new_string`, or the appended rule block). Require explicit confirm.
7. **Recovery-affordance line.** After every write, print: *"Recover with `git checkout HEAD -- .aa-review/rules.md` if needed."*

## Boundaries

- READ + Edit only `<REPO_ROOT>/.aa-review/rules.md`. Do not modify or create any other file.
- Do not run git lifecycle commands.
- Do not interact with GitLab/GitHub.
- Stop after the write — do not chain into `/aa-review`.
