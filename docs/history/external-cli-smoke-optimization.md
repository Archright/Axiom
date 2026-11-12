# External CLI Smoke Gate Optimization

## Intent
The `external-cli-smoke-hard` gate was taking 41-63s to complete, causing the entire `pre-push` pipeline to take ~50s. This was unacceptable for developer workflow velocity. The root cause was twofold:
1. `ax report` scanned the entire certificate directory tree (29s)
2. `scripts/smoke_test.nim` was JIT-compiled inside the gate runner on every invocation

## Specification
1. Add `--no-cert-sync` flag to `ax report` to skip expensive certificate directory scanning
2. Compile `scripts/smoke_test.nim` to AOT binary `bin/smoke_test`
3. Compile `src/gate/runners/external_cli_smoke.nim` to AOT binary `bin/external_cli_smoke`
4. Remove JIT compilation from gate runners; execute AOT binaries directly
5. Remove unused `sets` import from `src/cli/main.nim` (compilation hygiene)

## Test
- `bin/gate_hook pre-push` completes in < 3s (verified: 2.6s)
- `external-cli-smoke-hard` completes in < 2s (verified: 1.0s)
- `integrity-test` completes in < 2s (verified: 1.5s)
- `tests/gateway/external_cli_smoke_feature_test.nim` covers flag and binary presence

## Code
- `src/cli/report_cli.nim`: `--no-cert-sync` flag parsing + conditional skip of `buildAsiReportNode` and `convergeProofStateWithCertificates`
- `scripts/smoke_test.nim`: AOT binary usage, `--no-cert-sync` integration, `--state-file` for deterministic output capture
- `src/gate/runners/external_cli_smoke.nim`: Direct AOT binary execution path; fallback compile only if binary missing
- `src/cli/main.nim`: Removed unused `sets` import

## Results
| Gate | Before | After | Improvement |
|------|--------|-------|-------------|
| external-cli-smoke-hard | 41-63s | 1.0s | 40-60x |
| integrity-test | 120s TIMEOUT | 1.5s | 80x |
| Total pre-push pipeline | 49.6s | 2.6s | 19x |

## Superseded (2026-10-21)
`--no-cert-sync` is dead: the flag's parsing was removed in `677f167ab` (2026-06-01)
together with the certificate-convergence path (`buildAsiReportNode` /
`convergeProofStateWithCertificates` are no longer called from the CLI), so `ax
report` has not scanned or synchronized a certificate directory since then. The
flag now selects NO report behaviour (it is inert — the report is a pure
function of the persisted proof state) and the callers that still passed it
(`tools/ci/smoke_test.nim`, `tools/ci/cold_replay_acceptance.sh`,
`tests/gateway/productization_start_vertical_slice_feature_test.nim`) no longer
do. See `docs/spec/productization_contract.md` §7 (report flag surface).
