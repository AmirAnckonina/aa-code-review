---
description: "Parallel multi-reviewer code review of the current branch's diff vs. trunk"
argument-hint: "[focus areas] [base=<ref>] [--deep] [adapter=<name>]"
---

Use the Skill tool to invoke the **aa-review-engine** skill with `$ARGUMENTS` passed verbatim. The skill runs at the top level of this conversation (never dispatch it as a subagent — it needs the Agent tool to launch reviewers).

After it completes, relay its report verbatim — no summarizing, no table-to-prose conversion.
