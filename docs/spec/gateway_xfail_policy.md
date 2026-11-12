# Gateway Known-Failing (xfail) Policy

## Purpose

`make test-gateway` runs the business BDD gateway suite (`tests/gateway/*_feature_test.nim`,
§0.7 scope). A small number of tests may be quarantined as **known-failing (xfail)**
when they cannot pass in the current environment or require an immutable-policy change.

This mechanism is **fail-open by design, and explicitly documented and logged at runtime**
per AGENTS.md §0.9 (documented fail-open is not theater). It exists solely to keep CI green
while quarantined tests remain visible and their lifecycle is deterministically managed.

## Mechanism

- Quarantine list: `config/known_failing_gateway.txt` (one test base name per line; `#` comments
  allowed). It is the SSOT for the current quarantine set.
- `all_gateway_runner --skip-known-failing=config/known_failing_gateway.txt` excludes listed
  tests from the main run (compile + run phases). Excluded tests do not touch the incremental
  cache (content-addressed cacheKey; cache pollution-free).
- `--probe-known-failing` re-runs quarantined tests **report-only**. A quarantined test that now
  PASSES triggers a `[WARN]` and a final `[XFAIL]` summary listing tests that must be removed
  from the quarantine list. CI stays green; the warning enforces lifecycle cleanup.

## Anti-Theater Guarantees

1. **Explicit list**: quarantine is not a wildcard skip; every entry is named and committed.
2. **Runtime logging**: skipped tests are echoed as `[INFO] known-failing quarantined=N (...)`
   and probed tests as `[OK] still fails` / `[WARN] now passes`.
3. **Fix detection**: the probe phase prevents "repaired test silently stays quarantined"
   (theater signature #5). A pass in probe forces quarantine removal.
4. **DEBT tracking**: each quarantined entry must be registered in `data/debt_registry.json`
   with `status: "open"`, `category: "TechnicalDebt/KnownFailingGatewayTests"`, and an
   `{.axiomDebt.}` marker in a `src/` file (debt_integrity_gate Step 5 requirement).

## Current Quarantine

| Test | Reason |
|------|--------|

## Lifecycle

1. Quarantine is removed when the underlying issue is fixed (probe detects pass).
2. New failures in the active set are **never** silently skipped — they fail CI (zero-regression
   guarantee; a single new business failure turns CI red).
