# Quality reviewer checklist

Charter: Design, Performance & Testing, Readability — SOLID, encapsulation, interfaces, test coverage, performance, naming, comments, consistency. Apply every check below against the changed lines.
A check is "clean" only if you looked and found nothing — silence is not clearance.
(Merged from the v1 design, performance-testing, and readability lenses; no checks dropped.)

## Checklist — Design & Structure

### SOLID & Simplicity
- [ ] Single responsibility: each class/function does exactly one thing
- [ ] Open/closed: can the code be extended without modification?
- [ ] Liskov substitution: do subtypes honor the base contract?
- [ ] Interface segregation: are interfaces lean or do clients depend on methods they don't use?
- [ ] Dependency inversion: high-level modules depend on abstractions, not concrete implementations
- [ ] The solution is the simplest that meets requirements — no gold-plating
- [ ] No premature abstractions or unnecessary design patterns
- [ ] No dead code, unused imports, or commented-out blocks
- [ ] Library-first: existing libraries used where appropriate instead of custom code
- [ ] DRY — but only when the duplication represents the same concept

### Encapsulation
- [ ] Fields and methods private by default, only widened when genuinely needed
- [ ] No public fields that should be behind accessors
- [ ] Internal implementation details hidden from public API surface
- [ ] `protected` access justified by actual inheritance needs
- [ ] Module/package-level visibility used where appropriate
- [ ] Utility classes restrict instantiation when appropriate
- [ ] Prefer immutable data structures — mutate only when performance requires it

### Interface Design
- [ ] Dependencies injected via interfaces/abstractions, not concrete classes
- [ ] Components testable in isolation (mockable boundaries)
- [ ] Contracts (input/output types) explicitly defined
- [ ] Modules loosely coupled with clear boundaries
- [ ] Request/response payloads modeled as dedicated types (DTOs), not raw maps or inline literals
- [ ] Immutable models at boundaries — DTOs and value objects not mutated after construction

### Architectural Fit
- [ ] Does the change fit the existing architecture or introduce a new pattern?
- [ ] If a new pattern: is it justified? Does it conflict with existing approaches?
- [ ] Module boundaries respected — no reaching across layers
- [ ] Could this be simpler? Challenge the complexity.

## Checklist — Performance & Testing

### Test Coverage
- [ ] All public methods/endpoints covered by tests
- [ ] Happy path AND failure paths tested
- [ ] Tests assert behavior, not implementation details
- [ ] Branch coverage ≥ 80% on changed code
- [ ] Test names descriptive of the scenario they verify

### Test Quality
- [ ] Assertions verify actual behavior — a test can pass while checking nothing meaningful
- [ ] Missing negative tests: for every feature path, is there a test for "what happens when this fails?"
- [ ] Missing boundary tests: empty list, single element, max size, zero, negative, overflow
- [ ] Test independence: no dependency on execution order or shared mutable state
- [ ] No flaky patterns: time-dependent, network-dependent, order-dependent assertions
- [ ] Mocking at correct boundaries — not over-mocking (testing mocks instead of code)

### Performance — Data Access
- [ ] No N+1 patterns — use batch/bulk operations instead of row-by-row iteration
- [ ] Filtering/aggregation pushed to data layer (WHERE, GROUP BY) not fetch-all-then-filter
- [ ] Queries examined for missing indexes on new columns/filters
- [ ] Large collections paginated or streamed

### Performance — Runtime
- [ ] No unbounded loops or memory leaks in hot paths
- [ ] No unnecessary allocations or redundant computations
- [ ] Expensive operations cached or deferred where appropriate
- [ ] Blocking operations in async context? (thread pool starvation risk)

### Deployment & Breaking Changes
- [ ] API changes backward compatible? New fields optional?
- [ ] Database migrations reversible? Data backfill needed?
- [ ] Feature flags for risky changes?
- [ ] New dependencies impact startup time or memory footprint?

## Checklist — Readability & Conventions

### Naming
- [ ] Names (variables, functions, classes) are self-documenting
- [ ] A new team member can understand each function within 30 seconds
- [ ] No generic dump names: `utils`, `helpers`, `common`, `shared` without clear purpose
- [ ] Domain-specific names used: `OrderCalculator` not `Processor`
- [ ] No magic numbers or strings — named constants used (includes HTTP headers, query params, config keys, event names)
- [ ] Prefer meaningful names over comments

### Structure & Readability
- [ ] Nesting depth ≤ 3 levels — if deeper, extract or use early returns
- [ ] Single responsibility per function
- [ ] Functions ≤ 80 lines (aim for under 50), files ≤ 200 lines
- [ ] Code flows top-down — reader doesn't need to jump around to understand

### Comments & Documentation
- [ ] Self-explanatory code left without unnecessary comments
- [ ] Non-obvious elements commented: business logic, workarounds, regex, algorithms
- [ ] Comments explain WHY, not WHAT
- [ ] Public API interfaces documented (params, returns, throws)
- [ ] TODO/FIXME/HACK comments tracked with ticket references
- [ ] No stale comments that contradict the code

### Language Idioms & Consistency
- [ ] Follow language-specific conventions (PEP 8, gofmt, Google Java Style, etc.)
- [ ] Code follows existing project conventions (naming, structure, patterns)
- [ ] Similar problems solved the same way across the codebase
- [ ] Code style consistent with surrounding files
- [ ] Error handling patterns consistent with rest of codebase
- [ ] Prefer explicit over implicit — define variable types where supported
