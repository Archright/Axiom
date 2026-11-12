# integrity-test AOT Binary + Cache Isolation Fix

## Intent

Eliminate the 120s+ timeout of `integrity-test` gate in pre-push by addressing
the root cause: `tests/integrity_check.nim` compilation time exceeds 600s when
cache is invalidated by other gates sharing the same `nimcache/` directory.

## Root Cause

- `tests/integrity_check.nim` (66 lines) imports `core/gateway` (801 lines)
- `core/gateway` dependency tree includes Lean 4 bridge, Z3 pool, Judge eval
- Cold-start compilation: >600s (10x the 120s gate timeout)
- Cache hit: ~14s, but cache invalidated by `external-cli-smoke-hard`'s `nim c`

## Solution

1. **Cache Isolation**: `--nimcache:build/nimcache/integrity_test/` per gate
2. **AOT Binary**: Pre-compile `bin/integrity_test` so hook executes binary only
3. **Runner Update**: `src/gate/runners/integrity_test.nim` uses AOT binary when available

## Verification

| Metric | Before | After |
|--------|--------|-------|
| `integrity-test` execution | 120s TIMEOUT | 1.5s PASS |
| `bin/gate_hook pre-push` total | 120s+ TIMEOUT | 49.6s ALL PASSED |
| `bin/integrity_test` direct run | 300s+ TIMEOUT | 0.7s PASS |

## Files Changed

- `scripts/gate_hook.nim` — Token scheduler (previous change, staged together)
- `src/gate/runners/integrity_test.nim` — AOT binary + cache isolation logic
- `src/gate/runners/gate_hook.nim` — `runIntegrityTest()` uses AOT binary path
- `tests/gateway/test_aot_runner.nim` — New test verifying AOT binary behavior
