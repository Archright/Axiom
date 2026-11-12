# Tier-2 CI Activation — 2026-08-08 (Decision ③, Option A + C)

> Date: 2026-08-08 · Scope: `.github/workflows/ci.yml` (verify-integration)

## Summary

The architect approved tier-2 gate activation in CI as **Option A + C in parallel**:

- **Option A**: run tier-2 gate execution in `verify-integration` with a **300s budget**.
- **Option C**: separate out / document which tier-2 gates are already covered by
  alternate CI paths, so we only double-execute the ones with no other coverage.

## Mechanism

`bin/gate_hook ci` dispatches to `runCi` → `runAllGatesParallel(gsAnyCi)`, which applies
`filterDeferredGates` (tier-2 gates are removed from the active set and deferred to
post-commit). **Therefore `bin/gate_hook ci` runs tier-1 gates only.** Tier-2 gates must be
executed by a separate mechanism — in CI they are run directly from their gate binaries.

## Per-gate coverage separation (Option C)

| Tier-2 gate | stages | Alternate CI coverage | Action in CI (verify-integration) |
|---|---|---|---|
| `gateway-test` | ci | ✅ `make test-gateway` (84 feature tests, Makefile:204) covers the same business BDD scenario scope | Duplicate execution: skip; rely on `make test-gateway` |
| `nim-check` | ci | ✅ multiple `nim c`/`nim check` builds (CI build steps) + `.githooks/pre-commit` nim check | Duplicate execution: skip; rely on build coverage |
| `proof-universe-lock-gate` | pre-push | ❌ no alternate path | Execute directly (300s budget) |
| `verification-auditor` | pre-push, manual | ❌ no alternate path | Execute directly (300s budget) |

## CI steps added (decision ① + ③)

1. `AXIOM_CI: "1"` env added — required for `gsCI` gates (e.g. `integrity-workflow`) to pass
   `shouldRun` (gate_utils.shouldRun requires `evCi=="1"` for gsCI gates).
2. `Run CI-stage gates (tier-1 via hook, 300s budget)`:
   - `bin/precompile_gates` runs first (build if missing) so hook execution never JIT-compiles
     (no CAS miss).
   - `bin/gate_hook ci` — actively executes the tier-1 skCI gates (incl. formerly-dead
     `integrity-workflow`), budget 300s, `continue-on-error: false`.
3. `Run tier-2 gates without alternate coverage (300s budget)`:
   - `proof_universe_lock_gate` and `verification_auditor_gate` run directly via `nim c -r`
     (they are standalone executables with `main()`), budget 300s.

## Notes

- No production code was changed for this decision; only CI wiring + documentation.
- `gateway-test` and `nim-check` are intentionally NOT re-run in CI as tier-2 because they have
  approach-equivalent alternate coverage (Option C separation).
- Pre-commit / pre-push local extension of `ciAotGuard` was explicitly **held** (out of scope
  for this approval — CI path is the approved core; see Work 3 in the execution record).
