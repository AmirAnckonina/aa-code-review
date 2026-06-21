# Canonical Rule Shape — `.aa-review/rules.md`

This is the on-disk format for repo review rules. Both `aa-init-rules` (when drafting new rules) and `aa-edit-rules` (when modifying existing rules) MUST conform every authored rule to this shape.

## Heading template

```
## <Rule Name>  [CRITICAL]?
**Pattern:** <what compliant code looks like>
**Anti-pattern:** <what should be flagged>
**Why:** <rationale — incident, regulation, convention; cite ticket IDs if available>
**Example:** <minimal code snippet — optional>
```

`[CRITICAL]` is the only optional heading token. The body has four fields; `**Example:**` is the only optional one.

## Severity — one optional marker, applied by the skill

The author never types `[CRITICAL]` directly. `aa-init-rules` and `aa-edit-rules` ask the author one question:

> *"Does every violation of this rule block production?"*

- **Yes** → skill appends `[CRITICAL]` to the heading. Every future violation is 🔴 CRT regardless of context.
- **No** → skill leaves the heading bare. The reviewer infers severity per finding using the tier definitions in `aa-review-lenses/SKILL.md`:

| Tier | When the lens declares it |
|---|---|
| 🔴 CRITICAL | Pinned by the rule's `[CRITICAL]` marker, OR the lens determines the specific violation causes data loss / breach / outage / wrong data. |
| 🟡 IMPORTANT | Lens determines the specific violation is real risk but recoverable pre-merge. |
| 🔵 SUGGESTION | Lens determines the specific violation is convention / style / hygiene. |

If the author hesitates on the question — *"usually critical but sometimes OK"*, *"depends"* — the answer is **no**, leave it unmarked.

`[CRITICAL]` is the only severity grammar. The skill rejects all retired forms (`[MUST]`, `[MUST-FIX]`, `[tags: severity: …]`, `Treat as …`).

## Field rules

### `<Rule Name>` — REQUIRED

- ≤60 characters. Title Case preferred — technical terms (`runOnChange`, `main.xml`) and proper-noun-style branch names (`master`) may keep their original casing. No word-count cap; clarity wins.
- **Forbidden characters:** `[`, `]`, `,`, `—` (em-dash), `` ` `` (backtick), `|` (pipe), `"`, line breaks.
- **Forbidden substrings:** ` also `, `Repo rule:`.
- **Case-sensitive.** The reviewer cites the name verbatim in `[⚠️ Repo rule: <name>]` finding tags; any case drift breaks citation matching.
- **Renames are deferred** (see `aa-edit-rules` Out of scope) — pick the name carefully on first authorship.

**Why these characters are forbidden:** the reviewer's report grammar in `skills/aa-review-orchestrator/SKILL.md` (subagent prompt template + report-format token rules) uses `[` and `]` as citation-tag delimiters; `,` as the multi-cite separator (`[⚠️ Repo rule: <name>, also <name2>]`); ` — ` (em-dash with spaces) as the metadata/location/prose separator; backtick and pipe break Markdown rendering of the report.

### `[CRITICAL]` — OPTIONAL

A single literal token, case-sensitive. Append after the rule name with at least one space. Applied by the skill after the hard question — authors do not type this directly.

The reviewer binds severity per `skills/aa-review-orchestrator/SKILL.md` (report emission):

> *"A finding citing a `[CRITICAL]`-tagged rule is 🔴 CRT. For a finding citing an unmarked rule, infer severity per finding from the tier definitions in `aa-review-lenses/SKILL.md`."*

### `**Pattern:**` — REQUIRED

One sentence describing compliant code. **≤200 characters.**

### `**Anti-pattern:**` — REQUIRED

One or more shapes to flag. Concrete > abstract. **≤200 characters.**

### `**Why:**` — REQUIRED

Rationale. Cite incident IDs (`PROJ-NNNNN`) when available — most powerful justification. **≤500 characters.**

### `**Example:**` — OPTIONAL

Minimal code snippet showing compliant and/or anti-pattern. **≤30 lines.** Omit if the prose is unambiguous.

## Length caps — enforced at draft time

The skill refuses to finalize a rule that violates any cap. The author is offered: shorten, or split into two related rules.

Caps exist for two reasons:

1. **Consumer file cap.** The reviewer truncates `.aa-review/rules.md` at 10 KB (`r6-customization-design.md` Failure Modes). Per-field caps keep the cumulative size in check.
2. **Prompt-injection blast radius.** The whole file is injected verbatim into all 6 lens prompts. Tighter bodies = smaller surface for adversarial Markdown.

## Worked examples

### Example 1 — Reliability

```
## Probe Handlers Must Not Swallow Exceptions  [CRITICAL]
**Pattern:** Any class implementing `*Probe` or method named `probe(...)`/`runProbe(...)` lets exceptions propagate or wraps them in a domain `ProbeFailure` with cause attached.
**Anti-pattern:** `try { ... } catch (Exception e) { log.warn(...); return; }` inside a probe.
**Why:** A swallowed probe exception masks a dead integration as "healthy." Production incident PROJ-37412.
```

### Example 2 — Convention (unmarked, agent infers per finding)

```
## Branch Naming
**Pattern:** Branch names follow `feature/PROJ-XXXXX-short-description`.
**Anti-pattern:** `Feature/PROJ-...` (capitalized prefix), `fix-bug`, `alice/test`.
**Why:** Jira automation hooks key off the exact prefix. Capitalized or missing ticket ID breaks linkage.
```

### Example 3 — Test quality (unmarked)

```
## Unit Test Coverage Floor
**Pattern:** Branch coverage on changed lines ≥ 80%.
**Anti-pattern:** PR adds production code paths with no corresponding test changes.
**Why:** Coverage below 80% correlates with regressions in this service. Agent escalates per-instance when coverage drop is on a critical path.
```

### Example 4 — Security (unconditional `[CRITICAL]`)

```
## No Raw Request Body Logging  [CRITICAL]
**Pattern:** HTTP layer logs request method, path, status, latency — never the body.
**Anti-pattern:** `log.info("request: " + request.body())` or `log.debug(request)` in controllers/filters.
**Why:** Bodies contain auth tokens, PII, and customer secrets. Incident PROJ-38001. No exceptions — every violation blocks.
```

### Example 5 — Scale-sensitive (`[CRITICAL]`, outage class)

```
## Bounded Queries  [CRITICAL]
**Pattern:** Per-tenant table reads carry an explicit `Limit`, pagination, or batched iteration.
**Anti-pattern:** `Find(&results)` with no `Where` predicate beyond org scope.
**Why:** Discovery tenants reach millions of devices; an unbounded query that fits one tenant breaks production for another.
```

## Deprecated forms

The pre-2026 severity-declaration forms are **no longer recognized**:

- `Treat as CRITICAL/IMPORTANT/WARN` prose suffix on `**Why:**` bodies.
- `[MUST]` and `[MUST-FIX]` shorthand markers (interim grammar, retired).
- `[tags: severity: CRITICAL]` / `[tags: severity: IMPORTANT]` canonical tag form (interim grammar, retired).

For each deprecated form found, the loader emits one warning per offending rule at review time:

> *"Rule '<name>' uses deprecated severity declaration ('<form>'). Migrate to `[CRITICAL]` (for unconditional rules) or remove the marker (let the agent infer per finding)."*

The rule still loads; deprecated markers are ignored and severity falls back to agent inference. `aa-init-rules` and `aa-edit-rules` block all deprecated forms at draft time.

## Used by

- `aa-init-rules` — when drafting any new rule (Phase 3 per-rule loop).
- `aa-edit-rules` — when adding (`add` op) or modifying (`refine` sub-ops) any rule.

Drift between this file and either skill is a contract violation. Update this file first, then both skills.
