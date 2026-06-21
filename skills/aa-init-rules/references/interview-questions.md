# Author Interview — Strategic Q-set

Used by `aa-init-rules` in Phase 2 (after Phase 1 audit completes). The interview is **one question at a time** with explicit submit-and-pause between questions. No batching, no firehose.

## Flow

```
Phase 1 audit completes → evidence brief printed
   │
   ▼
Q0 (asked here)         — Any other file/doc to reference?
   │
   ▼
Q1 → submit → "Ready for Q2? [enter / back]" → Q2 → submit → ... → Q3
   │
   ▼
"Continue with optional Q4–Q5, or stop here and pick from candidates?"
   │
   ▼  (if yes)
Q4 → submit → ... → Q5
   │
   ▼
Merge with audit candidates → present topic menu
```

**After each answer**, the agent emits exactly one of these confirmation lines:

- `Got it. Ready for Q<N>? [enter to continue, 'back' to revise this answer, or 'skip' to drop this topic]`
- `Got it. That's the last core question — continue with optional Q4–Q5, or stop here? [Q4 / stop]`

`back` lets the dev revise the most recent answer. `skip` records no candidate for that Q and moves on.

## Stack-tailored examples

The agent detects the stack from Phase 1 audit signals (`pom.xml`, `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, etc.) and substitutes the matching example set into each Q's prompt. Stack groups:

| Group | Detected via |
|---|---|
| `jvm` | `pom.xml`, `build.gradle`, `*.java`, `*.kt` |
| `node` | `package.json`, `*.ts`, `*.tsx`, `*.js` |
| `python` | `pyproject.toml`, `requirements.txt`, `*.py` |
| `go` | `go.mod`, `*.go` |
| `other` | anything else — use the `generic` examples |

If the audit detects multiple stacks (monorepo), pick the dominant one by file count. If two are within 10% of each other, use the `generic` examples and note both stacks in the question prefix.

---

## Q0 — Additional reference docs

**Asked first, immediately after Phase 1 audit and the evidence brief is printed.**

**Ask:**
> *"I read CLAUDE.md, your repo overview docs, and lint configs. Any other file or doc I should reference before we draft rules? Examples: a style guide, an incident runbook, a Confluence export, a draft PR-template. Path or paste — enter to skip."*

**Behavior:**
- If a path is given → verify it's inside `REPO_ROOT` (read-scope guard from Phase 1 applies), read it, add to the evidence brief.
- If pasted text is given → treat as inline context, add to the brief.
- If empty → continue to Q1.

**Output mapping:** any new topics surfaced get added to the audit-derived candidates pool; they merge with author candidates at the end.

---

## Q1 — Recurring review feedback (CORE)

**Ask:**
> *"What do you find yourself flagging in code review for this repo that the standard reviewer keeps missing? Up to 3.*
> 
> *Examples in your stack (`<stack>`):*
> *<stack examples>"*

**Stack examples — substitute the matching group:**

| Group | Examples |
|---|---|
| `jvm` | *"missing `@Transactional` on service methods that mutate state", "raw `Map<String, Object>` returned from controllers", "lombok `@Data` on JPA entities"* |
| `node` | *"`any` types creeping into shared interfaces", "missing `await` inside `.map()` loops", "axios calls without timeout configured"* |
| `python` | *"bare `except:` catching everything", "mutable default args in function signatures", "`requests.get` without `timeout=`"* |
| `go` | *"goroutines without `context.Context`", "ignoring `err` returns from `defer Close()`", "`http.Get` without a custom client + timeout"* |
| `generic` | *"missing input validation at API boundaries", "log statements that include request bodies", "magic numbers in business logic"* |

**Probes (if author engages):**
- *"Is this tribal knowledge or documented somewhere?"*
- *"Does it apply repo-wide or to specific directories?"*

**Output mapping:** up to 3 topic one-liners, each tagged `tribal:` if not documented elsewhere.

**Confirmation line after submit:** `Got it. Ready for Q2 (hard "never" rules)? [enter / back / skip]`

---

## Q2 — Hard "never" rules (CORE)

**Ask:**
> *"Anything that must NEVER happen in this repo — non-negotiables that, if they slipped through, would block production?*
> 
> *Examples in your stack (`<stack>`):*
> *<stack examples>"*

**Stack examples:**

| Group | Examples |
|---|---|
| `jvm` | *"never log decrypted credentials or PAN data", "never `@SuppressWarnings` without a Jira link", "no `System.exit()` outside of `main`"* |
| `node` | *"never log raw request bodies for `/auth/*` routes", "no `eval` or `Function(string)` anywhere", "never disable TLS verification in prod paths"* |
| `python` | *"never `pickle.loads` untrusted data", "no `subprocess` with `shell=True` on user input", "never log full exception with secrets"* |
| `go` | *"never log full `http.Request` (carries Authorization header)", "no `panic()` in request handlers", "never disable cert verification"* |
| `generic` | *"never log secrets or tokens", "no `SELECT *` in migrations", "no commented-out code committed to main"* |

**Probes:**
- *"What's the worst-case impact if it does happen?"*
- *"Is the prohibition driven by an incident, regulation, or team convention?"*

**Output mapping:** one topic one-liner per prohibition. These are **always-`[CRITICAL]` territory** — Phase 3 proposes `[CRITICAL]` by default ("yes" to the production-blocking question).

**Confirmation line:** `Got it. Ready for Q3 (past incidents)? [enter / back / skip]`

---

## Q3 — Past incidents / near-misses (CORE)

**Ask:**
> *"Recall a recent production incident, late-stage bug, or near-miss in this repo. Could a reviewer have caught it on the diff? Brief — what was the pattern?*
> 
> *Examples (any stack):*
> *"PROJ-12345 — probe handler swallowed exception, masked Kafka backpressure for hours"*
> *"PROJ-67890 — migration script forgot WHERE clause, wiped a column in prod"*
> *"near-miss — staging caught a missing tenant filter that would have leaked data"*
> 
> *Skip if none come to mind."*

**Probes (if author engages):**
- *"Was the root cause in the changed code, or downstream?"*
- *"Was there a code pattern that, if flagged on review, would have prevented it?"*
- *"Is there a Jira ticket? (Helps anchor the **Why:** field with `PROJ-NNNNN`.)"*

**Output mapping:** each distinct incident yields one topic one-liner of the form `<pattern> — anchored to PROJ-NNNNN` when an ID is available, otherwise `<pattern> — incident-anchored`.

**Confirmation line:** `Got it. That's the last core question. Continue with optional Q4 (hot zones) + Q5 (stack idioms), or stop here and pick from candidates so far? [continue / stop]`

---

## Q4 — Hot zones / critical paths (OPTIONAL)

**Ask (only if author confirms "continue"):**
> *"Are there directories or modules where review must be stricter than the rest of the repo? Why?*
> 
> *Examples:*
> *"`auth/` — any change here ships with a security review tag"*
> *"`billing/` — financial impact, never approved single-reviewer"*
> *"`db/migrations/` — irreversible, separate deployment window"*"*

Asked even when repo overview docs already declare critical paths — the author's judgment over structural metadata.

**Output mapping:** one topic one-liner per zone, e.g., `Stricter review in **/billing/** — financial impact`.

**Confirmation line:** `Got it. Ready for Q5 (stack idioms)? [enter / back / skip]`

---

## Q5 — Stack-rejected idioms (OPTIONAL)

**Ask:**
> *"Anything your team rejects in review even though the code compiles and tests pass? These are taste / convention rules — the code works, but the team chooses a different shape.*
> 
> *Examples in your stack (`<stack>`):*
> *<stack examples>"*

**Stack examples:**

| Group | Examples |
|---|---|
| `jvm` | *"no raw `Map<String, Object>` for DTOs — define a record or class", "no manual getters / setters — Lombok `@Data` or `@Getter`", "no `Optional` as parameter types — only as returns"* |
| `node` | *"no `any` — use `unknown` or be explicit", "arrow functions over `function` keyword everywhere", "no `await` inside `.map()` — use `Promise.all`"* |
| `python` | *"f-strings over `.format()` everywhere", "type hints on all public functions", "no `pandas.read_csv` without `dtype=` on prod paths"* |
| `go` | *"no naked returns in functions > 5 lines", "errors wrapped with `%w` not `%v`", "no `interface{}` — use generics or specific types"* |
| `generic` | *"no commented-out alternatives — git remembers", "no abbreviations in public APIs", "no inline SQL — use the query builder"* |

**Skip-if:** `CLAUDE.md` has a documented style section AND the author confirms it's complete. The agent should ask: *"CLAUDE.md already has a style section. Want to add idioms NOT covered there, or skip Q5?"*

**Output mapping:** one topic one-liner per idiom.

**Confirmation line after Q5:** `Got it. Building topic menu from your answers + audit signals...`

---

## Merge and dedupe

After all asked questions return, combine:

1. **Audit-derived candidates** (from Phase 1 evidence brief — e.g., commits matching `fix|incident|PROJ-` produce candidates like `PROJ-37412 probe leak — incident-anchored`).
2. **Q0 additions** (any extra docs surfaced new topics).
3. **Author-derived candidates** (Q1–Q5 outputs).

**Dedup rule:** fuzzy-match by topic title. If two candidates describe the same pattern (e.g., audit found `PROJ-37412 probe leak`, Q3 produced `probe handlers swallowing exceptions`), merge into one topic line with both anchors mentioned.

Present the merged menu as a numbered list. The author picks any subset (zero allowed). Selected topics flow to Phase 3 per-rule drafting.

## Tag conventions

Topic one-liners use these prefixes / suffixes to carry intent forward:

- `<pattern> — anchored to PROJ-NNNNN` (em-dash + `anchored to <ticket>`) — Q3 incident-anchored topics with a Jira ID. Phase 3 proposes `[CRITICAL]` by default.
- `<pattern> — incident-anchored` (no ticket ID) — Q3 topics without a Jira ID.
- `tribal: <pattern>` — Q1 topics that capture undocumented team conventions.
- Plain `<pattern>` (no prefix/suffix) — all other questions.

A topic may carry at most one tag. If two questions surface the same pattern (e.g., Q3 incident + Q1 tribal), the merge step picks the strongest anchor (incident > tribal > plain).

## Output contract per question

Every answered question maps to one of:

- `(no candidate)` — author had no relevant input or used `skip`.
- One or more topic one-liners. Each is ≤80 characters. Title Case. Each captures the *kind* of rule, not the rule itself — full rule drafting happens in Phase 3.

Example topic one-liners:

- `Probe handler exception swallowing — anchored to PROJ-37412`
- `Token logging in HTTP layer`
- `tribal: Branch naming for Jira linkage`
- `Migration script idempotency — incident-anchored`

## What was dropped from earlier versions

- **Old Q6 (override base coding standards)** — rarely produced actionable rules; team-level overrides belong in CLAUDE.md, not per-repo rules.
- **Old Q7 (onboarding pain)** — fuzzy answers; topics surfaced were already covered by Q1 (recurring review feedback).

Both retired in this revision. If evidence shows missed coverage that maps back to Q6/Q7 territory, re-introduce as optionals.
