# Repo Review Rules — example-service

These rules extend `aa-coding-standards` for this repo. The reviewer applies them with equal severity weight. Where these rules conflict with base standards, these win.

> A simple, illustrative example. Each rule has the same four parts: **Pattern** (what good code does), **Anti-pattern** (what to flag), **Why** (one plain reason), and an optional **Example** (good vs. bad). Full format: `skills/aa-init-rules/references/rule-shape.md`. Make your own with `/aa-init-rules`, or copy this file to `<repo>/.aa-review/rules.md`. `[CRITICAL]` means every violation blocks; unmarked rules let the reviewer judge severity per finding.

## Use Parameterized Database Queries  [CRITICAL]
**Pattern:** Pass values to the database as parameters; keep the query text fixed.
**Anti-pattern:** Building a query by gluing user input into the SQL string.
**Why:** String-built SQL lets an attacker run their own query (SQL injection).
**Example:**
```js
// good — value passed as a parameter
db.query('SELECT * FROM users WHERE email = $1', [email]);

// bad — user input glued into the query
db.query('SELECT * FROM users WHERE email = ' + email);
```

## Validate Input at the Edge
**Pattern:** Check request data (type, range, allowed values, size) before using it.
**Anti-pattern:** Passing raw request fields straight into logic, with no limits.
**Why:** Bad input you didn't check causes crashes, wrong results, and security holes.
**Example:**
```ts
// good — validate, and cap the page size
const { page, size } = parsePagination(req.query); // rejects bad input
return service.list(page, Math.min(size, 100));

// bad — raw, unchecked, unbounded
return service.list(req.query.page, req.query.size);
```

## Keep Secrets Out of Logs and Code  [CRITICAL]
**Pattern:** Log IDs and status only; read secrets from the environment.
**Anti-pattern:** Logging tokens or request bodies, or hard-coding keys in the source.
**Why:** Secrets in logs or git are a leak and stay there long after you "fix" the line.
**Example:**
```ts
// good — identifiers only
log.info('auth ok', { userId, requestId });

// bad — secret in the log, key in the code
log.info('auth ok token=' + accessToken);
const API_KEY = 'sk_live_4eC39HuXk2...';
```

## Set a Timeout on External Calls
**Pattern:** Give every network/database call a timeout and a plan for failure.
**Anti-pattern:** A call with no timeout, or whose error is ignored.
**Why:** One slow dependency with no timeout can hang and take the whole service down.
**Example:**
```ts
// good — timeout, with a fallback on failure
const res = await fetch(url, { signal: AbortSignal.timeout(2000) })
  .catch(() => FALLBACK);

// bad — no timeout, error ignored
const res = await fetch(url);
```

## Limit How Much You Read at Once
**Pattern:** Read lists with a limit, pagination, or batches.
**Anti-pattern:** `findAll()` or `SELECT *` on a table that keeps growing.
**Why:** A query that's fast on test data can run out of memory once real data grows.
**Example:**
```sql
-- good — one bounded page
SELECT id, name FROM orders WHERE org_id = $1 ORDER BY id LIMIT 50 OFFSET $2;

-- bad — reads everything
SELECT * FROM orders WHERE org_id = $1;
```
