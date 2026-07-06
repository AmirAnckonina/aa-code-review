# Report format — assembly, verdict, layers (single source of truth)

Finding-line grammar, severity tiers, and the CRITICAL gate are owned by reviewer-prompt.md — this file starts where reviewer output ends.

---

## Severity Levels

> **Severity binding from a cited authority.** When a finding cites a repo rule (`[⚠️ Repo rule: <name>]`):
> - If the rule heading carries `[CRITICAL]`, the finding is 🔴 CRT. You MUST NOT downgrade. The rule's `[CRITICAL]` marker is the team-lead's pre-declared judgment that violations are unconditional merge blockers — it substitutes for the 3-criteria gate in `reviewer-prompt.md`. (Reviewer-judgment 🔴 findings still owe the 3-criteria articulation; rule-cited 🔴 inherits the rule's authority.)
> - If the rule is unmarked, infer severity for the *specific* finding using the tier definitions in `reviewer-prompt.md`. The rule's prose is one input among many; the diff context, the codebase scale, the reachability, and the blast radius all factor in. Same rule + different instance = potentially different severity.
> See `${CLAUDE_PLUGIN_ROOT}/skills/aa-init-rules/references/rule-shape.md` for the rule-file grammar.

---

## Verdict Rules

Driven by highest finding severity — simple and deterministic.

| Highest Severity Found | Verdict |
|----------------------|---------|
| Any 🔴 CRITICAL | **BLOCKER** |
| Any 🟡 IMPORTANT (no criticals) | **NEEDS WORK** |
| Only 🔵 SUGGESTION (or no findings) | **SHIP IT** |

---

## Finding IDs

The parent assigns prefixed IDs after collecting all reviewer results:
- `CRT-{n}` — Critical
- `IMP-{n}` — Important
- `SUG-{n}` — Suggestion

These IDs enable drill-down: user can ask "expand CRT-1" or "show Security details".

---

## Reviewer Coverage Table

The primary review output table. Replaces the 13-principle scorecard — findings are reported per reviewer, not remapped to individual principles.

```
### Reviewer Coverage
| Reviewer | Model | Status | Findings | Top Finding |
|----------|-------|--------|----------|-------------|
| Bugs | {REVIEWER_MODEL} | ✅ Clean / 🔵 / 🟡 / 🔴 / ❌ NOT REVIEWED | N🔴 N🟡 N🔵 | [ID or —] |
| Security | {REVIEWER_MODEL} | ... | ... | ... |
| Quality | {REVIEWER_MODEL} | ... | ... | ... |
```

**Status values:**
- `✅ Clean` — no findings
- `🔵 N suggestions` — only suggestions
- `🟡 N important` — important findings, no criticals
- `🔴 N critical` — critical findings present
- `❌ NOT REVIEWED` — reviewer failed after retry

---

## Review Report Format

**IMPORTANT — Emoji rendering:** Always use actual Unicode emoji characters (🔴 🟡 🔵 ✅ ⚠️ ❌), NEVER markdown shortcodes.

The report is rendered in three layers. **Layer 1 is the default output.** Layers 2 and 3 are produced on demand when the user types `expand <ID>` or `show <Reviewer>`.

### Layer 1 (default) — one line per finding

```
## Review Report

**Verdict: {BLOCKER | NEEDS WORK | SHIP IT}**
**TL;DR:** [1-2 sentences: biggest concern + scope. Do NOT enumerate findings.]
**Scope:** [N files, ±M lines vs. <BASE_REF> (merge-base <short-sha>), reviewer model: {Sonnet/Opus}]

### Findings Summary
- 🔴 Critical: [count]
- 🟡 Important: [count]
- 🔵 Suggestion: [count]
- Repo rules cited: <X> of <N> findings

### Reviewer Coverage
[Insert Reviewer Coverage Table above]

### Findings
> `expand <ID>` for detail · `show <Reviewer>` for full reviewer output

🔴 **CRT-1** [Reviewer] [⚠️ Repo rule: <name>]? — file:line — title (≤80 chars)
🟡 **IMP-1** [Reviewer] — file:line — title
🔵 SUG-1 [Reviewer] — file:line — title
...
+M more — expand to see  (only when total findings > 20)

### Activity Summary
> [one-line summary of what the run did]
```

**Layer 1 weight target:** ≤30 lines for a 10-finding review.

**Top-N truncation rule.** If total findings > 20:
- All 🔴 CRT and 🟡 IMP findings are shown in full (never truncated).
- 🔵 SUG findings are shown until the total reaches 20.
- Append a single line: `+M more — expand to see` where M is the count of suppressed SUG findings. The user can request specific suppressed findings by ID (`expand SUG-N`) or by the literal `expand suggestions`.

Ordering: by severity (🔴 → 🟡 → 🔵), then by reviewer order (Bugs, Security, Quality), then by file path then line.

### Layer 2 (drill-down by finding) — produced on `expand <ID>`

When the user issues `expand <ID>` (e.g., `expand CRT-3`), emit:

- **Title** — the same title shown in Layer 1.
- **Mechanism** — the reviewer's mechanism prose (what's wrong, why it matters, impact, suggested fix).
- **Rule citation** — if the finding carries `[⚠️ Repo rule: <name>]`, include the full rule body (`Pattern`, `Anti-pattern`, `Why`) verbatim from the loaded rules file.
- **Code context** — surrounding code lines (≥5 before/after the flagged line range).

Unknown ID → *"No finding with ID '<ID>' in current report. Present IDs: <comma-separated list>."*

### Layer 3 (drill-down by reviewer) — produced on `show <Reviewer>`

When the user issues `show <Reviewer>` (case-insensitive prefix or substring match on a canonical reviewer name), emit:

- The reviewer's full rationale as the subagent returned it.
- What the reviewer checked (the reviewer's checklist headers).
- What the reviewer skipped, if anything.

Ambiguous match → *"Reviewer '<query>' is ambiguous. Candidates: <list>. Use the full canonical name."*

### Activity Summary
> [e.g., "Pre-read 12 changed files. Launched 3 Sonnet reviewers. Collected 14 findings, deduplicated to 11."]
```

---

## Synthesis (engine, post-collection)

- **Systemic clustering:** if 3+ findings across reviewers land on the same file/module/abstraction, replace them with ONE architectural finding naming the cluster (severity = highest of the cluster). Do not speculate about branch scope or PR size — those are author decisions, not findings.
- **Dedupe:** same defect reported by 2+ reviewers → keep the highest severity, merge mechanisms, note the merge in the Activity Summary count.
- **[CRITICAL] promotion:** a finding citing a `[CRITICAL]`-tagged repo rule but emitted below 🔴 is promoted to 🔴, plus a separate 🟡 finding recording the reviewer's protocol deviation.
- **Cap note:** if a reviewer reported hitting its 10-finding cap, add one Activity Summary line: "<Reviewer> hit the finding cap — coverage of low-severity items may be partial."
