# Adapters — the two extension seams

The engine (`skills/aa-review-engine/SKILL.md`) is adapter-agnostic except at two seams. An adapter is a markdown spec that tells the engine how to fill each seam. Adding one requires NO engine surgery — write the adapter doc, teach Step 1/Step 6 to honor its `adapter=<name>` value.

## Seam 1 — Context source (engine Step 1)

The adapter must yield: `BASE_REF` + resolution label, `MERGE_BASE`, a changed-file list with origin tags, the unified diff, and pre-read file contents (binary + hidden-dir filtered).

| Adapter | How | Status |
|---|---|---|
| `local` | git merge-base vs. resolved trunk; committed + working tree + untracked | ✅ implemented (`local.md`) |
| `github` | `gh pr view/diff <n>` — review a PR without checking it out | planned |
| `gitlab` | `glab mr view/diff <n>` | planned |

## Seam 2 — Report sink (engine Step 6)

The adapter receives: the rendered report, the verdict, and the structured finding set (ID, severity, reviewer tag, rule cite, file:line, title, mechanism).

| Adapter | Sink | Status |
|---|---|---|
| `local` | 3-layer markdown to the terminal; Layers 2/3 served interactively | ✅ implemented |
| `github` | PR review comments (inline per finding) + summary comment | planned |
| `gitlab` | MR discussion threads | planned |
| `file` | JSON/SARIF artifact for CI gates | planned |

## CI shape (planned, for orientation)

A CI integration = install this plugin in the runner + `claude -p "/aa-review adapter=github base=origin/${TARGET_BRANCH}"`. The engine's read-only invariants and verdict math are identical in CI; only the two seams differ.

## Mixed seams

`adapter=<name>` sets both seams for now. If a real use case needs split values (e.g., local context → file sink), extend the arg grammar then — YAGNI today.
