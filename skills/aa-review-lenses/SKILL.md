---
name: aa-review-lenses
description: "Review orchestration: 6 parallel lenses, severity levels, enforcement protocol, verdict rules, and report format. The single source of truth for how reviews are scored and reported. Loaded by the aa-review-orchestrator skill and the lens subagents it dispatches."
user-invocable: false
---

## Review Lenses

This skill defines the **review scoring system** and the **6 parallel review lenses**.

**Loaded by:** the `aa-review-orchestrator` skill and the lens subagents it dispatches. Not user-invocable — orchestration is handled by the orchestrator skill.

> **Requires `aa-coding-standards` to be loaded.** Lens checklists reference the 13 coding-standards principles by number. If aa-coding-standards is unavailable, respond with:
> `"aa-review-lenses requires the aa-coding-standards skill. Please load it and retry."` — then halt.

---

## Challenge Methodology

Your job is to break the code, not confirm it works. The author already believes it works. Your value is finding what they missed.

- **Trace, don't skim.** Walk through code paths with concrete boundary values. Challenge every conditional — what happens in the else?
- **Challenge state & side effects.** Can it reach an inconsistent state? Are resources properly closed on error paths? Shared mutable state?
- **Challenge the tests.** Are assertions verifying behavior? Missing negative/boundary tests? Test independence?
- **Challenge the API contract.** Cross-reference swagger/OpenAPI against code paths. Trace upstream responses through the call chain.

---

## Severity Levels

**🔴 CRITICAL** — Reserve for findings where merging as-is causes **incorrect data, data loss, security breach, or production outage**. A finding qualifies as 🔴 CRITICAL **only when ALL THREE of the following hold**:

1. **Reachable.** The bug fires on a real code path that ships in this branch — not theoretical, not dead code, not an edge case already gated upstream. You can point at the line(s) the user will hit.
2. **Violates a top-tier invariant.** Security boundary breach, data-integrity loss, deploy failure, persistent outage class, secret leakage, regulatory violation, or equivalent. "Could be slow" or "could be confusing" does not qualify.
3. **No upstream mitigation.** No existing auth check, input validation, configuration gate, downstream safety net, or framework guarantee bounds the impact. If a layer above this code already prevents the bad input or contains the blast radius, the finding is bounded — not critical.

If ANY of the three is uncertain, downgrade to 🟡 IMPORTANT. **When in doubt, downgrade.** A finding that "could be critical under some conditions" is 🟡, not 🔴. Reviewers consistently overshoot on this tier — the cost of an over-flagged 🔴 is that authors learn to ignore the label, which destroys the signal of the one finding per review that genuinely is a merge blocker.

Examples that DO qualify: SQL injection on a reachable endpoint with no upstream sanitization; missing auth check on a privileged endpoint exposed publicly; a Kafka consumer NPE that crashes the partition with no DLQ; an unbounded `findAll` shipped against a known multi-million-row production table; a cache-invalidation bug that returns one tenant's data to another.

Examples that do NOT qualify (downgrade to 🟡 or 🔵): theoretical race on an approximate counter; missing null-check on a path where the upstream validator already rejects null; an N+1 query in code reachable only by an admin role; a TOCTOU on a value that's only used for logging.

**🟡 IMPORTANT** — Real risk bounded by scope. Should be fixed before broader rollout but is **not a single-PR merge blocker**. Examples: auth-scoped risk (a flaw the user must already be authenticated to reach), consistency issue with a simple fix, missing error handling on a recoverable path, test gap on a non-critical branch, performance regression that degrades but doesn't fail, behavior-changing refactor without a covering test, a 🔴-shaped finding where one of the three criteria above is uncertain.

**🔵 SUGGESTION** — Optimization concerns, theoretical edge cases, style improvements, code-health observations. Author may defer. Examples: theoretical races on approximate counts, edge cases already handled by an upstream check, readability, naming, logging hygiene, scope creep, feature-flag bookkeeping, convention violations, micro-optimizations.

> **Declaration discipline.** Severity is a per-finding call by the lens, not a fixed mapping from "rule type → severity." A logging hygiene rule violated in a hot Kafka loop is still SUG. A `findAll` query that happens to be on a tiny config table is still SUG. The tier is determined by the **specific instance's blast radius and reachability**, not the rule's name.
>
> **3 tiers only.** No 4th tier. No per-MR cap. No auto-downgrade based on context. No POSITIVE / ✅ Positive / POS-{n} category — do not include praise sections.
>
> **Severity binding from a cited authority.** When a finding cites a repo rule (`[⚠️ Repo rule: <name>]`):
> - If the rule heading carries `[CRITICAL]`, the finding is 🔴 CRT. You MUST NOT downgrade. The rule's `[CRITICAL]` marker is the team-lead's pre-declared judgment that violations are unconditional merge blockers — it substitutes for the 3-criteria gate above. (Lens-judgment 🔴 findings still owe the 3-criteria articulation; rule-cited 🔴 inherits the rule's authority.)
> - If the rule is unmarked, infer severity for the *specific* finding using the tier definitions above. The rule's prose is one input among many; the diff context, the codebase scale, the reachability, and the blast radius all factor in. Same rule + different instance = potentially different severity.
> See `~/.claude/skills/aa-init-rules/references/rule-shape.md` for the rule-file grammar.

---

## Enforcement Protocol

- For each principle covered by a lens, **actively search** for violations using tool-assisted scans (grep for magic numbers, `@SuppressWarnings`/`noinspection`, bare catch blocks, raw `Map`/`Object` types where DTOs should exist).
- A lens is **Clean only if you have evidence** — you checked and found nothing. "I didn't look closely" means findings were missed.

---

## The 6 Lenses

| # | Lens | Reference File | Principles Covered |
|---|------|---------------|-------------------|
| 1 | Correctness & Logic | `references/correctness-lens.md` | #2 Edge Cases, #3 Null Safety (logic paths) |
| 2 | Security & Input Safety | `references/security-lens.md` | #9 Security, #3 Null Safety (boundary validation) |
| 3 | Reliability & Operations | `references/reliability-lens.md` | #4 Error Handling, #11 Logging, #2 Edge Cases (failure) |
| 4 | Design & Structure | `references/design-lens.md` | #6 SOLID, #7 Encapsulation, #8 Interface Design |
| 5 | Performance & Testing | `references/perf-testing-lens.md` | #1 Test Coverage, #10 Performance |
| 6 | Readability & Conventions | `references/readability-lens.md` | #5 Naming, #12 Comments, #13 Consistency |

---

## Subagent Configuration

- **subagent_type:** `general-purpose` (needs Read, Grep, Glob, Bash for code analysis)
- **model:** Sonnet by default. Opus if `--deep` flag was passed.
- **maxTurns:** 6 per subagent (parent pre-reads files and diff — lenses only need tools for surrounding context)
- **Pre-read optimization:** The parent orchestrator reads all changed files and the diff ONCE, then injects relevant content into each lens prompt. Lenses should NOT re-read these files or re-run `git diff`. They may read additional files (imports, callers, related modules) for surrounding context.
- **Boundaries:** READ ONLY. No file modifications. No git lifecycle commands. No glab commands. No user interaction.

---

## Subagent Output Format

Subagents return natural findings within their lens focus. No principle numbers, no scorecard mapping.

**IMPORTANT — Emoji rendering:** Always use actual Unicode emoji characters (🔴 🟡 🔵 ✅ ⚠️ ❌), NEVER markdown shortcodes like `:red_circle:` or `:yellow_circle:`. Shortcodes do not render in the terminal.

```
### Findings

🔴 CRITICAL — [file:line] — [title ≤80 chars] | [mechanism: what's wrong, why it matters, impact, suggested fix]
🟡 IMPORTANT — [file:line] — [title ≤80 chars] | [mechanism]
🔵 SUGGESTION — [file:line] — [title ≤80 chars] | [mechanism]

### Summary
[2-3 sentences: overall assessment from this lens's perspective]
```

**Title / mechanism split.** Each finding line MUST contain a single `|` separator between a short title (≤80 chars, no line break, no Markdown) and the mechanism prose. The parent renderer reads the title for Layer 1 (default) and the mechanism for Layer 2 (`expand <ID>` drill-down). If a lens omits the `|`, its full prose is treated as title and Layer 2 will be empty for that finding — the parent emits one activity-summary warning per such lens.

---

## Failure Handling

If a subagent fails or returns empty:
1. Retry once with the same prompt
2. If still fails → mark `❌ NOT REVIEWED` in Lens Coverage table
3. Flag that lens's principles as coverage gaps
4. Never silently skip — the user must know what wasn't reviewed

---

## Cross-Check Rules (Parent, Post-Collection)

After all 6 lenses return, the parent checks:
- **Security ↔ Reliability:** Error responses leaking internal info?
- **Correctness ↔ Testing:** Logic bugs found — are they covered by tests?
- **Security ↔ Design:** Public API surface exposing internal implementation?
- **Performance ↔ Reliability:** Performance optimization introducing failure modes?
- **Design ↔ Readability:** Structural decisions hurting readability? Good naming masking bad design?
- **Deduplication:** Same finding from multiple lenses → keep highest severity, merge notes.

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

The parent assigns prefixed IDs after collecting all lens results:
- `CRT-{n}` — Critical
- `IMP-{n}` — Important
- `SUG-{n}` — Suggestion

These IDs enable drill-down: user can ask "expand CRT-1" or "show Reliability details".

---

## Lens Summary Table

The primary review output table. Replaces the 13-principle scorecard — findings are reported per lens, not remapped to individual principles.

```
### Lens Coverage
| Lens | Model | Status | Findings | Top Finding |
|------|-------|--------|----------|-------------|
| Correctness & Logic | {LENS_MODEL} | ✅ Clean / ⚠️ / 🔴 / ❌ NOT REVIEWED | N🔴 N🟡 N🔵 | [ID or —] |
| Security & Input Safety | {LENS_MODEL} | ... | ... | ... |
| Reliability & Operations | {LENS_MODEL} | ... | ... | ... |
| Design & Structure | {LENS_MODEL} | ... | ... | ... |
| Performance & Testing | {LENS_MODEL} | ... | ... | ... |
| Readability & Conventions | {LENS_MODEL} | ... | ... | ... |
```

**Status values:**
- `✅ Clean` — no findings
- `⚠️ N findings` — only suggestions/positives
- `🟡 N important` — important findings, no criticals
- `🔴 N critical` — critical findings present
- `❌ NOT REVIEWED` — lens failed after retry

---

## Review Report Format

**IMPORTANT — Emoji rendering:** Always use actual Unicode emoji characters (🔴 🟡 🔵 ✅ ⚠️ ❌), NEVER markdown shortcodes.

The report is rendered in three layers. **Layer 1 is the default output.** Layers 2 and 3 are produced on demand when the user types `expand <ID>` or `show <Lens>`.

### Layer 1 (default) — one line per finding

```
## Review Report

**Verdict: {BLOCKER | NEEDS WORK | SHIP IT}**
**TL;DR:** [1-2 sentences: biggest concern + scope. Do NOT enumerate findings.]
**Scope:** [N files, ±M lines vs. <BASE_REF> (merge-base <short-sha>), lens model: {Sonnet/Opus}]

### Findings Summary
- 🔴 Critical: [count]
- 🟡 Important: [count]
- 🔵 Suggestion: [count]
- Repo rules cited: <X> of <N> findings

### Lens Coverage
[Insert Lens Summary Table above]

### Findings
> `expand <ID>` for detail · `show <Lens>` for full lens output

🔴 **CRT-1** [Lens] [⚠️ Repo rule: <name>]? — file:line — title (≤80 chars)
🟡 **IMP-1** [Lens] — file:line — title
🔵 SUG-1 [Lens] — file:line — title
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

Ordering: by severity (🔴 → 🟡 → 🔵), then by lens index (1=Correctness, 2=Security, 3=Reliability, 4=Design, 5=Performance, 6=Readability), then by file path then line.

### Layer 2 (drill-down by finding) — produced on `expand <ID>`

When the user issues `expand <ID>` (e.g., `expand CRT-3`), emit:

- **Title** — the same title shown in Layer 1.
- **Mechanism** — the lens's mechanism prose (what's wrong, why it matters, impact, suggested fix).
- **Rule citation** — if the finding carries `[⚠️ Repo rule: <name>]`, include the full rule body (`Pattern`, `Anti-pattern`, `Why`) verbatim from the loaded rules file.
- **Code context** — surrounding code lines (≥5 before/after the flagged line range).

Unknown ID → *"No finding with ID '<ID>' in current report. Present IDs: <comma-separated list>."*

### Layer 3 (drill-down by lens) — produced on `show <Lens>`

When the user issues `show <Lens>` (case-insensitive prefix or substring match on a canonical lens name), emit:

- The lens's full rationale as the subagent returned it.
- What the lens checked (the lens's checklist headers).
- What the lens skipped, if anything.

Ambiguous match → *"Lens '<query>' is ambiguous. Candidates: <list>. Use the full canonical name."*

### Activity Summary
> [e.g., "Pre-read 12 changed files. Launched 6 Sonnet lenses. Collected 14 findings, deduplicated to 11. Cross-checked 5 pairs."]
```
