# Repo Review Rules — example-service

These rules extend `aa-coding-standards` for this repo. The reviewer applies them with equal severity weight. Where these rules conflict with base standards, these win.

> This is a generic example. Generate your own with `/aa-init-rules`, or copy this file to `<repo>/.aa-review/rules.md` and edit. The `[CRITICAL]` marker means every violation blocks; unmarked rules let the reviewer infer severity per finding.

## Parameterized Database Queries  [CRITICAL]
**Pattern:** All SQL uses bound parameters (placeholders or named params); query strings are static constants. ORM query builders with parameterized inputs are fine.
**Anti-pattern:** String concatenation or interpolation of user input into a query; `"... WHERE id = " + id`; dynamic table/column names built from request data.
**Why:** Concatenated SQL is an injection vector — a single reachable path can leak or destroy data. No exceptions; every violation blocks.

## Validate Input at the Boundary
**Pattern:** Request handlers validate and type-coerce input (shape, bounds, enums) before passing it to services; validation lives in one place per endpoint.
**Anti-pattern:** Trusting request fields directly in business logic; scattered ad-hoc checks deep in the call stack; unbounded list/string sizes accepted without limits.
**Why:** Unvalidated input causes incorrect behaviour, crashes, and security holes. Centralizing validation keeps the trust boundary explicit and testable.

## No Secrets in Logs or Source
**Pattern:** Logs record identifiers and status only; secrets come from env/secret-store and are referenced by name. Errors are logged without their sensitive payloads.
**Anti-pattern:** `log.info("token=" + token)`; logging full request/response bodies that may carry credentials or PII; hard-coded API keys, passwords, or connection strings in source.
**Why:** Leaked secrets in logs or version control are a breach and are hard to rotate after the fact.

## Wrap External Calls with Timeout and Error Handling
**Pattern:** Outbound HTTP/RPC/DB calls set an explicit timeout and handle failure (retry-with-backoff, fallback, or a clear error) rather than blocking indefinitely.
**Anti-pattern:** A network client with no timeout; an external call whose failure is swallowed or left to bubble as an unhandled exception; unbounded retries.
**Why:** An unprotected dependency turns a slow upstream into cascading resource exhaustion and outages. Fail fast and degrade predictably.

## Paginate Unbounded Collection Reads
**Pattern:** Endpoints and jobs that read collections use pagination, an explicit limit, or batched iteration.
**Anti-pattern:** `findAll()` / `SELECT *` with no limit on a table that grows with usage; loading an entire collection into memory to return one page.
**Why:** A query that fits in development can exhaust memory or time out in production as data grows.
