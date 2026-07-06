# Bugs reviewer checklist

Charter: Correctness & Reliability — logic, edge cases, null safety, error handling, failure modes, operations. Apply every check below against the changed lines.
A check is "clean" only if you looked and found nothing — silence is not clearance.
(Merged from the v1 correctness-lens, reliability-lens lenses; no checks dropped.)

## Checklist

### Logic Errors
- [ ] Walk through code paths with concrete values — pick boundary values (0, -1, max, empty, null) and mentally execute
- [ ] Challenge every conditional: what happens in the else? Are compound conditions correct under all combinations?
- [ ] Follow data from entry to exit — where can it be null/empty/malformed that the code doesn't check?
- [ ] Are transformations lossy? Data type conversions that lose precision or truncate?
- [ ] Off-by-one errors in loops, slices, ranges, pagination

### Data Flow
- [ ] Can variables reach a state the code doesn't handle?
- [ ] Are return values from called functions checked before use?
- [ ] Does the code correctly distinguish between "absent" and "present but empty"?
- [ ] Optional/Maybe types used instead of returning null where the language supports it

### State & Side Effects
- [ ] Can the code reach an inconsistent state? What if a step fails midway?
- [ ] Does any function modify state beyond its return value? Are callers aware?
- [ ] Concurrent/race conditions — shared mutable state? Are operations atomic that need to be?

### Boundary Values
- [ ] Boundary values handled: max, min, zero, negative, empty, single element, overflow
- [ ] Unexpected input shapes: wrong type, extra fields, truncated data
- [ ] Timeout and retry scenarios — what happens at the boundary of max retries?

### Intent vs. Implementation
- [ ] Does the code actually do what the MR description/intent says it does?
- [ ] Are there code paths that contradict the stated intent?
- [ ] Are there missing code paths that the intent implies should exist?

## Checklist

### Error Handling
- [ ] Errors caught at appropriate levels — never swallowed silently
- [ ] No bare `catch` / `except` without specific handling
- [ ] Catch blocks are minimal and specific — no suppressing or generalizing the original error
- [ ] Recoverable vs. fatal errors are distinguished
- [ ] Consistent error response structure for APIs
- [ ] Error messages aid debugging without leaking internals
- [ ] No inline error codes (magic numbers) — use named constants or enums
- [ ] No suppressed compiler/linter warnings without a justifying comment and ticket
- [ ] All HTTP status codes in swagger/OpenAPI annotations have explicit handling paths

### Resource Management
- [ ] Connections, streams, locks, and transactions properly opened and closed — including on error paths
- [ ] Look for try-without-finally, missing `close()`, unreleased resources
- [ ] Timeout handling — what happens when external calls hang?
- [ ] Circuit breaker / retry patterns used correctly (not infinite retry, not retry on non-idempotent)

### Failure Recovery
- [ ] State transitions — can it reach an inconsistent state on failure?
- [ ] Partial failure cleanup — what if step 3 of 5 fails?
- [ ] Graceful degradation — does the system degrade safely or crash entirely?
- [ ] Async errors propagated or handled — not silently swallowed by detached goroutine/thread/promise
- [ ] Spawned goroutines/threads/tasks are bounded — no unbounded spawning

### Logging & Observability
- [ ] Key operations logged: entry points, state transitions, external calls
- [ ] Flow reconstructable from logs alone without a debugger
- [ ] Log levels correct: DEBUG for internals, INFO for business events, WARN for recoverable issues, ERROR for failures
- [ ] Logs follow project's existing conventions (format, library, structure)
- [ ] No sensitive data in logs (tokens, passwords, PII)
- [ ] Log messages are actionable — what happened and where
- [ ] Correlation/request IDs included for traceability in distributed flows
- [ ] New error paths have corresponding log statements
