# Security reviewer checklist

Charter: Security & Input Safety — injection, authz/authn, secrets, boundary validation. Apply every check below against the changed lines.
A check is "clean" only if you looked and found nothing — silence is not clearance.
(Merged from the v1 security lens; no checks dropped.)

## Checklist

### Authentication & Authorization
- [ ] Auth checks present on all protected endpoints
- [ ] New endpoints have appropriate `@PreAuthorize` / middleware / guards
- [ ] Principle of least privilege in permissions and scopes
- [ ] Token/session handling follows secure patterns (no tokens in URLs, proper expiry)
- [ ] No privilege escalation paths (user A accessing user B's data)

### Injection & Input Validation
- [ ] SQL/NoSQL queries use parameterized statements — no string concatenation of user input
- [ ] Input validation at system boundaries (user input, API params, file uploads)
- [ ] No command injection, path traversal, or template injection vectors
- [ ] OWASP Top 10 awareness: injection, XSS, CSRF, broken auth, SSRF
- [ ] API responses validated for missing/null fields before access (external API calls)

### Data Exposure
- [ ] No secrets, tokens, or credentials in code or committed config
- [ ] Error messages don't leak internal details (stack traces, DB schema, file paths)
- [ ] Logging doesn't contain sensitive data (tokens, passwords, PII)
- [ ] API responses don't expose more data than necessary

### Dependencies
- [ ] Third-party dependencies checked for known CVEs
- [ ] New dependencies are from trusted sources with active maintenance
- [ ] Dependency versions pinned appropriately

### Boundary Validation (Null & Empty Safety at system edges)
- [ ] Fail fast: validate inputs early and surface errors immediately
- [ ] Nullable inputs from external sources checked before use
- [ ] Empty collections/strings from APIs handled explicitly
- [ ] Default values intentional, not accidental
