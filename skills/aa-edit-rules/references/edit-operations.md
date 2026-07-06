# Edit Operations — `aa-edit-rules`

Used by `aa-edit-rules` to dispatch the user's request to one of the supported ops. **Scope: `add` and 6 `refine` sub-ops only.** `rename` and `remove` are deferred — refuse those requests with the literal message from the spec's Refuse-if conditions.

All ops share these invariants:

- **Read → Edit, never Write.** Preserve every untouched byte of the file.
- **Show a unified diff before any write.** Require explicit confirm.
- **After write, print the recovery-affordance line:** *"Recover with `git checkout HEAD -- .aa-review/rules.md` if needed."*
- **Conform to `rule-shape.md`.** Load the canonical shape from `${CLAUDE_PLUGIN_ROOT}/skills/aa-init-rules/references/rule-shape.md` and enforce every field rule on the produced output.

## Op: `add`

**Trigger phrases:** `"add a rule"`, `"I have an idea for a rule"`, `"/aa-edit-rules add"`.

**Audit:** Mini-pass. Re-read `<repo>/.aa-review/rules.md` to extract existing rule names. Optionally, scan the last 30 commits (subject to the read-scope guard) for new incident anchors not yet reflected in existing rules.

**Interview:** Single anchor probe — *"Is this rule anchored to an incident, a team convention, or a new pattern you've started flagging?"* Then proceed to per-rule drilldown (Pattern → Anti-pattern → Why → `[CRITICAL]` question → optional Example) per `rule-shape.md`. For the marker, ask one question: *"Does every violation of this rule block production?"* Yes → skill appends `[CRITICAL]`. No → unmarked (agent infers severity per finding).

**Name-collision check:** Compute the set of existing rule names (case-sensitive). If the proposed name already exists, refuse with: *"Rule name '<name>' already exists in `<repo>/.aa-review/rules.md`. Refine the existing rule (`/aa-edit-rules refine <name>`) or pick a different name."* List the present names for context.

**Write:** Append the new rule to the end of the file, separated by exactly one blank line from the prior rule. Show unified diff. Confirm. Write. Print recovery line.

## Op family: `refine`

The user names both the **rule** and the **dimension** being changed. The skill loads only that named rule, drills only into that dimension, and edits only the corresponding bytes.

**Dispatch by dimension:**

- `tighten-pattern` — modifies `**Pattern:**` line of the named rule.
- `tighten-anti-pattern` — modifies `**Anti-pattern:**` line.
- `update-why` — modifies `**Why:**` line.
- `update-example` — modifies the `**Example:**` block (may add or remove the field).
- `toggle-critical` — adds or removes the `[CRITICAL]` marker on the rule heading. The marker is the only optional heading token in the simplified grammar.

**Ambiguous trigger handling.** If the user says `"tighten <name>"` without specifying pattern vs anti-pattern, ask: *"Which dimension — pattern or anti-pattern?"* Do not assume.

### Common refine flow

1. Read the rules file. Parse rule headings (`^## ` prefix). If the named rule is not found, return: *"No rule named '<name>' found in `<repo>/.aa-review/rules.md`. Present rule names: <list>."*
2. Extract the existing value of the targeted dimension.
3. Show the existing value. Prompt for the new value.
4. Apply field-rule validation from `rule-shape.md` (length caps for body fields; `[CRITICAL]` marker if present is the only allowed heading token).
5. Show unified diff (`old_string` → `new_string`). Confirm.
6. Apply the edit using a single Read → Edit operation (NOT a full file Write).
7. Print the recovery line.

### Sub-op specifics

#### `tighten-pattern` / `tighten-anti-pattern`

No additional warnings beyond the common flow. Validate the new value against the ≤200-character cap.

#### `update-why`

Validate ≤500 chars. If the new value references an incident, encourage the `PROJ-NNNNN` format.

#### `update-example`

Validate the new value against the ≤30-line cap (skipped when removing, since there is no new value).

If adding an example where none existed, append `**Example:** <value>` immediately after the `**Why:**` line.

If removing an example, delete the entire `**Example:** <value>` line (including trailing newline).

#### `toggle-critical` — **WARNING-GATED**

This op covers two transitions:
- Unmarked → `[CRITICAL]` (add marker)
- `[CRITICAL]` → unmarked (remove marker)

Before applying the edit, print this **literal** warning (substitute `<name>` and pick the matching line):

> *"Adding `[CRITICAL]` to `<name>` will mark every future violation as 🔴 CRT regardless of context. Reserve this for rules where there are no exceptions (security non-negotiables, deploy-blocking correctness, data integrity, outage class). Continue?"*

or

> *"Removing `[CRITICAL]` from `<name>` returns it to agent-inferred severity. Future violations may be graded as CRT, IMP, or SUG depending on the specific instance. Continue?"*

Proceed only on explicit confirm. If the requested transition is a no-op (already `[CRITICAL]` and adding, or already unmarked and removing), refuse: *"`<name>` is already `<state>`. No change."*

**CRT gate.** If the new state is `[CRITICAL]`, check whether the rule's **Why** body describes an unconditional class (security / data integrity / deploy-blocking / outage) and contains no hedging ("usually", "in most cases", "except"). If the **Why** hedges, surface:

> *"`[CRITICAL]` means every violation blocks production, no exceptions. This rule's **Why** contains hedging ('<phrase>'). Leave it unmarked and let the agent infer per-finding severity, or proceed anyway?"*

**Deprecated marker cleanup.** If the rule's heading currently contains `[MUST]`, `[MUST-FIX]`, `[tags: severity: ...]`, or the rule's **Why** ends with `Treat as CRITICAL/IMPORTANT/WARN.`, offer in the same edit pass: *"This rule uses a deprecated severity form ('<form>'). Replace with `[CRITICAL]` / unmarked per the new grammar?"* Proceed on confirm.

## Refused ops: `rename` and `remove`

If the user requests a rename or remove (triggers like `"rename <name>"`, `"remove <name>"`, `"retire <name>"`, `"delete <name>"`), refuse with the **literal** message from the spec's Refuse-if conditions:

> *"Rename and remove are deferred for now (citation-breakage risk). Workaround: `add` a replacement rule with the corrected behavior, then `refine` the old rule's `**Pattern:**` so it never matches (effectively a no-op). The old rule stays citeable for any historical findings while new findings cite the replacement."*

Do not proceed even on user pressure. Direct the user back to `add` + `tighten-pattern`.

## Cross-skill dependency failure

If reading `${CLAUDE_PLUGIN_ROOT}/skills/aa-init-rules/references/rule-shape.md` fails (file not found, permission denied), emit:

> *"`rule-shape.md` not found at `${CLAUDE_PLUGIN_ROOT}/skills/aa-init-rules/references/rule-shape.md`. Re-run `aa-code-review/install.sh` to repair the symlinks."*

And exit. Do not proceed without the shape contract.

## Size-cap enforcement

Before any write, compute the size the file would have after the edit. If ≥8 KB, warn: *"File at <N> KB after this edit; consumer cap is 10 KB. Consider pruning before adding more."* The author may continue. If the post-write size would be ≥10 KB, refuse the write and offer to either drop the change or roll back the most recently added rule.

## Trigger-phrase distinguishability

The skill must route correctly between sub-ops. Use these unambiguous mappings:

- `"add"`, `"new rule"`, `"have an idea"` → `add`
- `"tighten"` + named rule + (`"pattern"` | `"anti-pattern"`) → `tighten-pattern` / `tighten-anti-pattern`
- `"tighten"` + named rule (no dimension) → ask for dimension
- `"update why"`, `"change rationale"` → `update-why`
- `"add example"`, `"remove example"`, `"update example"` → `update-example`
- `"mark critical"`, `"add [CRITICAL]"`, `"make critical"`, `"unmark critical"`, `"remove [CRITICAL]"`, `"make advisory"`, `"change severity"` → `toggle-critical`
- `"rename"`, `"remove"`, `"retire"`, `"delete"` → refuse (deferred)
