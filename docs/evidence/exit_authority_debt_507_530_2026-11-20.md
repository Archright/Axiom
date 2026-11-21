# Exit-Authority Debt Closure — DEBT#507 / DEBT#530 (2026-11-20)

Worktree: `worktrees/vs-debt-close-507-530`, branch `workstream/debt-close-507-530`,
base `origin/main` `f895944` (includes PR #233, merge `268e31a` — "fix(cli): canonical
run verdict is the only exit authority").

Binaries used for evidence were rebuilt from this tree (no binary was copied from the
main checkout):

- `make build` → `bin/ax` (`nim c --hints:off -d:allowMissingZ3 -o:bin/ax src/cli/main.nim`, Nim 2.2.10)
- `make bin/debt_engine` → `bin/debt_engine`

## Fix under test (code references)

| Surface | Code | Behavior after PR #233 |
|---|---|---|
| The one run-exit rule | `src/core/utils/decision_algebra.nim:186-229` `projectRunOutcome` | Reads **only** `runOutcome.verdict` (+ `gateVerdict` consistency). `PASS → CONTINUE`, `FAIL → BLOCK`, `BLOCKED`/`INCONCLUSIVE`/absent/malformed/contradictory `→ UNRESOLVED`. `summary` is never read. |
| `ax prove` exit | `src/cli/wf_runners.nim:46-72` `axProofShortcutExitCode` | Consumes `runExitCode(projectRunOutcome(reportNode))`. `summary` is used only as fail-closed input guards (`blockingFailure`, `fatalErrors`, `requirePerfectAsi`) — it can demote, never promote. `ax prove` reprojects at `src/cli/axiom_engine.nim:7178-7188` `runProofPipelineWithExit` (`canonicalProofExitCode`). |
| `ax report` exit | `src/verification/report_engine.nim:63-76` `computeReportExitCode` | Thin projection of `projectRunOutcome` (`CONTINUE → 0`; `BLOCK`/`UNRESOLVED → 1`). |
| `ax report` read path | `src/verification/report_engine.nim:20-59` `loadReportProofState` | Re-decides restored states through `verification_decision_authority.evaluateRestoredStateRunOutcome`; an unbound state cannot assert a PASS. |
| Empty-run verdict | `src/verification/obligation/verification_decision_authority.nim:208-292` `makeRunOutcomeVerdict` / `evaluateRunOutcome` | Empty universe / absent enumeration falls into the fail-closed `otherwise` branch → `INCONCLUSIVE` (never PASS-by-zero-count). |
| Contract | `docs/spec/productization_contract.md:370-371,391` | §7 exit table now says `0` only on canonical PASS and `1` for `FAIL`/`BLOCKED`/`INCONCLUSIVE`/absent verdict; summary counts are telemetry. |

## DEBT#507 — `ax report` exited 0 on a NOT_VERIFIABLE-only run

### Negative-control inputs

`/tmp/debt507530/inconclusive_state.json` — the defect shape: `runOutcome.verdict=INCONCLUSIVE`,
`runOutcome.gateVerdict=FAIL`, `verificationComplete=false`, all summary counters zero:

```json
{
  "schemaVersion": "axiom.report.v1",
  "runOutcome": {"planComplete": true, "executionComplete": true,
                 "verificationComplete": false, "verdict": "INCONCLUSIVE",
                 "basis": "NONE", "gateVerdict": "FAIL"},
  "summary": {"verified": 0, "failedCount": 0, "timeoutCount": 0, "blockedCount": 0}
}
```

`/tmp/debt507530/summary_only_state.json` — the legacy shape with no verdict block at all:

```json
{"schemaVersion": "axiom.report.v1",
 "summary": {"verified": 0, "failedCount": 0, "timeoutCount": 0}}
```

`/tmp/debt507530/inconclusive_state_bound.json` — the same INCONCLUSIVE document with the
current measured `executionIdentity` envelope appended (see "Positive path" below). The
envelope makes read-time revalidation `established`, so the recorded verdict is preserved
and the exit can only be produced by `projectRunOutcome` — this isolates the verdict as the
exit authority.

### Observed results (all run from the worktree root)

```
$ ./bin/ax report --json --state-file /tmp/debt507530/inconclusive_state_bound.json
EXIT=1   # runOutcome.verdict=INCONCLUSIVE, gateVerdict=FAIL,
         # summary verified=0/failedCount=0/timeoutCount=0, no readTimeRevalidation block
         # → the binding state was preserved and the verdict alone produced exit 1

$ ./bin/ax report --json --state-file /tmp/debt507530/inconclusive_state.json
EXIT=1   # read path re-decided: runOutcome.verdict=INCONCLUSIVE, gateVerdict=FAIL,
         # readTimeRevalidation.established=false

$ ./bin/ax report --json --state-file /tmp/debt507530/summary_only_state.json
EXIT=1   # no verdict block → UNRESOLVED (fail-closed); re-decided INCONCLUSIVE/FAIL
```

Observed `runOutcome`/`summary` on the bound negative control (exact JSON projection):

```json
{"runOutcome":{"planComplete":true,"executionComplete":true,"verificationComplete":false,
 "verdict":"INCONCLUSIVE","basis":"NONE","gateVerdict":"FAIL"},
 "summary":{"verified":0,"failedCount":0,"timeoutCount":0,"blockedCount":0}}
```

Before PR #233 this exact shape (`verified=0 ∧ failedCount=0 ∧ timeoutCount=0`) mapped to
`OutcomeContinue` → exit 0. It now exits 1.

### Positive path (PASS still exits 0)

The read path rejects an unbound synthetic PASS (it re-decides it to INCONCLUSIVE;
`readTimeRevalidation.established=false`), so a coherent PASS was tested by appending the
**current measured** execution identity envelope. The envelope was captured with a
temporary probe binary compiled from this same worktree:

```
$ /tmp/debt507530/exec_ctx_probe
{"executionBundleFingerprint":"dc73cadbb2e00cc614e22408d160b884a5ca3444dc22a34ddc0dd25d0425c0b3",
 "executionConfigDigest":"1c27b74604cde596810de317c0faf0af4976a502364aef1c4302c7f8534454c6",
 "toolchainIdentity":"nim-2.2.10|lean-4.33.0|z3-4.13.3|int64bit|linux-amd64|...",
 "executionEpoch":"bde8c6984ac82c3fcd9941c929f9c19cdc5f3aa9067f0081bbcb62b700f0f492",
 "verifierBuildId":"d15af113c33d341a7380c083928460460e0bd66f2c56223bef8ff2e44f51e57f",
 "platform":"linux-amd64"}
```

`pass_state_bound.json` = coherent `runOutcome.verdict=PASS`/`gateVerdict=PASS` +
`runAccounting` with 2 fresh satisfied REQUIRED units + that envelope:

```
$ env -u AXIOM_STATE_DIR ./bin/ax report --json --state-file /tmp/debt507530/pass_state_bound.json
EXIT=0
{"runOutcome":{"planComplete":true,"executionComplete":true,"verificationComplete":true,
 "verdict":"PASS","basis":"PROVEN","gateVerdict":"PASS"},
 "summary":{"verified":2,"failedCount":0,"timeoutCount":0}}
```

Reproduction note: the probe's identity values are environment-dependent (toolchain and
bundle digests). On another tree the envelope must be re-measured; an unbound synthetic
PASS reading INCONCLUSIVE is the documented read-path fail-closed behavior, not a defect.

### Code inspection — no summary-based exit fallback remains

- `projectRunOutcome` (`src/core/utils/decision_algebra.nim:186-229`): no `summary`,
  `verified`, `failedCount`, or `timeoutCount` read; only `runOutcome.verdict` /
  `gateVerdict`.
- `axProofShortcutExitCode` (`src/cli/wf_runners.nim:46-72`): summary appears only in
  fail-closed guards; the exit is `runExitCode(projectRunOutcome(reportNode))`.
- `computeReportExitCode` (`src/verification/report_engine.nim:63-76`): `case
  projectRunOutcome(stateJson)` only.

### Disposition: DEBT#507 closed

## DEBT#530 — proposal-mode empty (no-obligation) run exited 0

### Input

`/tmp/debt507530/propositions_empty_target.json` (schema v2, one claim-form proposition
whose canonical target resolves to zero frontier nodes; proposal mode degrades the
`--target` refusal into `INCAPABLE{LANE_NOT_EQUIPPED}` and continues, exactly the empty
run shape the entry describes):

```json
{"schema_version":2,
 "subject":{"repository":"local/axiom-worktree","commit":"f895944000000000000000000000000000000000"},
 "agent":{"id":"debt530-empty-run-probe","version":"1.0"},
 "propositions":[{"id":"debt530-empty-run","logic":"forbid-set-membership",
   "expression":"toOpenArrayProbe(x, 0, 1).len == 2",
   "target":"src/core/utils/decision_algebra.nim::functionThatDoesNotExistForDebt530"}]}
```

Prerequisite: `--proposals` requires `AXIOM_STATE_DIR`; the engine resolves the kernel
scope lock under the state root when that variable is set, so the lock was copied to
`$AXIOM_STATE_DIR/data/verification_scope.lock` before the run.

### Command and observed result

```
$ AXIOM_STATE_DIR=/tmp/debt507530/state \
    ./bin/ax prove --proposals /tmp/debt507530/propositions_empty_target.json --limit 1
PROVE_EXIT=1

# stderr excerpts:
# PROPOSITIONS_INTAKE: ... propositions=1 incapable=[debt530-empty-run=UNSUPPORTED_LOGIC]
# frontier_selection: --target=...::functionThatDoesNotExistForDebt530 not found in frontier
#   — canonical target: NotFound (fail-closed, empty selection)
# axiom_engine: ... propositions-introduced target: degrading to per-proposition
#   INCAPABLE{LANE_NOT_EQUIPPED} (byo_agent_proposition_contract §3); run continues
# axiom_engine: frontier eligibility gate: excluded 17 non-proof-candidate candidate(s); eligible=0
```

Persisted state (`/tmp/debt507530/state/logs/ax_proof_state.json`) — the empty-run shape:

```json
{"runOutcome":{"planComplete":true,"executionComplete":true,"verificationComplete":true,
 "verdict":"INCONCLUSIVE","basis":"NONE","gateVerdict":"FAIL","reuseConditions":[]},
 "runAccounting":{"requiredCount":0,"pendingCount":0,"satisfiedCount":0,"units":[]},
 "summary":{"verified":0,"failedCount":0,"timeoutCount":0,"blockedCount":0,"preSieved":0}}
```

`display.units=[]` and `display.propositions=[{capability: INCAPABLE/UNSUPPORTED_LOGIC,
verification: {attempted:false, verdict:null}}]` — no obligation executed a verification.
The run previously collapsed this shape to `OutcomeContinue` → exit 0; it now exits 1 with
an explicit `INCONCLUSIVE` / `gateVerdict=FAIL` verdict.

Cross-check — the same persisted state through the `ax report` read path:

```
$ env -u AXIOM_STATE_DIR ./bin/ax report --json \
    --state-file /tmp/debt507530/state/logs/ax_proof_state.json
REPORT_ON_REAL_EMPTY_RUN_EXIT=1
{"verdict":"INCONCLUSIVE","gateVerdict":"FAIL","revalidation":null,
 "verified":0,"requiredCount":0}
```

`revalidation:null` means read-time revalidation was established (the run state is bound to
this tree/build); the exit 1 comes from the recorded INCONCLUSIVE verdict.

### Disposition: DEBT#530 closed

## Unit-test corroboration (same worktree)

```
$ nim c -r --hints:off tests/unit/wf_runners_exit_code_test.nim
WF_RUNNERS_TEST_EXIT=0
  [OK] INCONCLUSIVE verdict -> UNRESOLVED, exit 1
  [OK] summary-only document is telemetry, never success (1)
  [OK] summary-only with blocked obligations is not success (1)
  [OK] malformed runOutcome block is UNRESOLVED, exit 1
  ... (all cases OK)

$ nim c -r --hints:off tests/unit/report_engine_test.nim
REPORT_ENGINE_TEST_EXIT=0
  [OK] canonical no-obligation PASS (verified=0) → exit 0
  [OK] timeout-aborted run (INCONCLUSIVE) → exit 1
  [OK] summary-only document with zero failures → exit 1
  [OK] verdict contradicted by gateVerdict → exit 1
  [OK] zero reused rows + envelope mismatch → INCONCLUSIVE; the recorded PASS does not survive
  [OK] zero reused rows + matching envelope → established and NOT degraded
  ... (all cases OK)
```

## Debt-engine closure mechanics

Both entries were closed with the worktree engine's atomic mutation path
(`tools/debt_engine.nim` `cmdClose`, DEBT#437), which validates first, mutates the SSOT
entry, regenerates projections, syncs the budget ledger, re-validates, and rolls back on
any failure. Exact observed transcript:

```
$ bin/debt_engine --close DEBT#507 --resolution "FIXED 2026-11-20 ..." --note "..."
  Checks: 1826 total, 1826 passed, 0 failed
  ✅ Post-validation passed.
Close complete: DEBT#507 (status: open → closed)
CLOSE_507_EXIT=0

$ bin/debt_engine --close DEBT#530 --resolution "FIXED 2026-11-20 ..." --note "..."
  Checks: 1826 total, 1826 passed, 0 failed
  ✅ Post-validation passed.
Close complete: DEBT#530 (status: open → closed)
CLOSE_530_EXIT=0

# ledger counters: before 60 open / 232 closed → after 507: 59 / 233 → after 530: 58 / 234

$ bin/debt_engine --codegen
CODEGEN_EXIT=0
  [skip] src/generated/debt_constants.nim unchanged
  [skip] docs/DEBT_REGISTRY.md unchanged
ProjectionStatus: P1=complete

$ bin/debt_engine --sync-budget
SYNC_BUDGET_EXIT=1
  Records processed: 6
  Updates applied:   0
  Skipped (no evaluator): 3
    BUDGET#002 (evaluator error)   # bin/layer_enforcement_gate missing
    BUDGET#003 (evaluator error)   # bin/effect_contract_projection missing
    BUDGET#004 (evaluator error)   # bin/nimtry missing
  Writing data/debt_ledger.json... Done. 0 record(s) updated.
  Sync INCOMPLETE: 3 of 6 BUDGET record(s) unmeasured ... exiting 1 (fail-closed)
# Expected DEBT#543 fail-closed behavior for the three unrelated evaluator binaries that
# are not built in this worktree; `debt_registry_open`/`debt_registry_closed` were already
# synced by the `--close` path (58/234), so no counter drift remains.

$ bin/debt_engine --validate
VALIDATE_EXIT=0
  Checks: 1826 total, 1826 passed, 0 failed
  Metric evaluation: 3 PASS, 0 DRIFT
  All debt validation checks passed.
```

## Residual risks / follow-ups (not modified here)

1. **Stale BYO contract line.** `docs/spec/byo_agent_proposition_contract.md:120` still
   states that an all-INCAPABLE run exits 0. This is stale against the now-observed exit 1
   and against the selftest workflow's own acceptance, which already asserts exit 1 for the
   all-INCAPABLE fixture (`.github/workflows/byo-agent-selftest.yml:77,290`). Updating the
   contract is a documentation/contract revision outside this closure's authority.
2. **Exit-1 semantics broadened.** After the fix, exit 1 covers canonical `FAIL`,
   `BLOCKED`, and `INCONCLUSIVE` (including empty runs). Consumers that equate exit 1 with
   `DISPROVED` must read `runOutcome.verdict`; this is the DEBT#528 wrapper-classification
   concern, not a new engine defect.
3. **Read path is intentionally strict.** A synthetic PASS without a matching
   `executionIdentity` reads INCONCLUSIVE (exit 1). Real states written by a run on the
   same context revalidate; cross-context/restored states fail closed by design.
4. **Standalone `--sync-budget` in this worktree.** It exits 1 (DEBT#543 fail-closed)
   because `bin/layer_enforcement_gate`, `bin/effect_contract_projection`, and `bin/nimtry`
   are not built here; the three affected BUDGET records keep their last verified values.
   The debt-registry counters were synced by `--close` (open 60 → 58, closed 232 → 234) and
   the final `--validate` passes 1826/1826 with 0 failed checks.