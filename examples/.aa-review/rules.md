# Repo Review Rules — example-service

These rules extend `aa-coding-standards` for this repo. The reviewer applies them with equal severity weight. Where these rules conflict with base standards, these win.

> A generic, illustrative example. Each rule follows the canonical shape — `**Pattern:**` / `**Anti-pattern:**` / `**Why:**`, plus an optional `**Example:**` snippet (see `skills/aa-init-rules/references/rule-shape.md`). Generate your own with `/aa-init-rules`, or copy this file to `<repo>/.aa-review/rules.md` and edit. The `[CRITICAL]` marker means every violation blocks; unmarked rules let the reviewer infer severity per finding.

## Parameterized Database Queries  [CRITICAL]
**Pattern:** All SQL uses bound parameters; the query text is a static constant and request data reaches the database only through the parameter list, never via string building.
**Anti-pattern:** Concatenating or interpolating request data into the query (`"... WHERE id = " + id`, `f"... '{name}'"`); dynamic table/column names taken from input.
**Why:** Concatenated SQL is the classic injection vector — one reachable path can read, alter, or destroy data across tenants. Parameterization is non-negotiable; every violation blocks regardless of how "trusted" the input looks.
**Example:**
```js
// compliant — value bound as a parameter
db.query('SELECT * FROM users WHERE email = $1', [email]);

// anti-pattern — request data concatenated into the query text
db.query('SELECT * FROM users WHERE email = ' + email);
```

## Validate Input at the Boundary
**Pattern:** Each request handler validates and coerces input (shape, types, bounds, allowed values, size limits) at the edge before any business logic runs; one validator per endpoint.
**Anti-pattern:** Passing raw request fields straight into services; accepting size-unbounded arrays or strings; validation scattered as ad-hoc `if` checks deep in the call stack.
**Why:** Unvalidated input causes crashes, wrong results, and security holes, and the failure surfaces far from its cause. A single explicit boundary keeps the trust edge testable and obvious.
**Example:**
```ts
// compliant — validate + coerce at the edge, cap the page size
const { page, size } = parsePagination(req.query); // throws 400 on bad input
return service.list(page, Math.min(size, 100));

// anti-pattern — raw, unbounded request values reach the service
return service.list(req.query.page, req.query.size);
```

## No Secrets in Logs or Source  [CRITICAL]
**Pattern:** Logs carry identifiers, status, and timing only; secrets load from env or a secret store and are referenced by name. Errors are logged without their sensitive payloads.
**Anti-pattern:** `log("token=" + token)`; logging whole request/response bodies; hard-coded API keys, passwords, or connection strings committed to source.
**Why:** Secrets in logs or version control are a breach and painful to remediate — log archives and git history both persist long after the offending line is "fixed." Every violation blocks.
**Example:**
```ts
// compliant — identifiers only
log.info('auth ok', { userId, requestId });

// anti-pattern — secret in the log line, and a committed key
log.info('auth ok token=' + accessToken);
const API_KEY = 'sk_live_4eC39HuXk2...'; // committed secret
```

## Wrap External Calls with Timeout and Error Handling
**Pattern:** Every outbound HTTP/RPC/DB call sets an explicit timeout and handles failure deliberately — a bounded retry with backoff, a fallback, or a clearly surfaced error.
**Anti-pattern:** A client created with no timeout; an external call whose error is swallowed or left to bubble unhandled; unbounded or tight-loop retries.
**Why:** An unprotected dependency turns one slow upstream into thread and connection exhaustion, then a cascading outage. Failing fast and degrading predictably keeps one bad dependency from taking down the service.
**Example:**
```ts
// compliant — explicit timeout, failure handled
const res = await fetch(url, { signal: AbortSignal.timeout(2000) })
  .catch(() => FALLBACK);

// anti-pattern — no timeout, failure ignored
const res = await fetch(url);
```

## Paginate Unbounded Collection Reads
**Pattern:** Endpoints and jobs that read collections use pagination, an explicit limit, or batched iteration sized to bounded memory.
**Anti-pattern:** `findAll()` / `SELECT *` with no limit on a table that grows with usage; loading an entire collection into memory to return a single page.
**Why:** A query that is instant on dev data can exhaust memory or time out in production as rows grow. The cost stays invisible until scale exposes it, usually during an incident.
**Example:**
```sql
-- compliant — bounded, ordered page
SELECT id, name FROM orders WHERE org_id = $1 ORDER BY id LIMIT 50 OFFSET $2;

-- anti-pattern — unbounded read that grows with the table
SELECT * FROM orders WHERE org_id = $1;
```
