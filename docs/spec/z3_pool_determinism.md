# Z3 Pool Determinism Specification

## 1. Problem

Wall-clock timeouts are fundamentally non-deterministic. Z3 maintainers acknowledge this:
- Z3 Issue #5969: "timeout is just a non-deterministic version of rlimit"
- Z3 Issue #1151: timeout behavior varies with CPU load, context switches, I/O waits

### Historical Failure Mode

Per-query `readDeadline` mixed I/O wait time with solver time:
1. Worker restart would reset the deadline
2. I/O wait consumed budget silently
3. Result: flaky "z3 persistent read deadline exceeded" → verification FAIL

### First Fix Attempt

8000ms budget + deadline refresh on restart. This was an operational patch that:
- Added complexity in restart logic
- Didn't address the fundamental issue: wall-clock != CPU work

## 2. Design

### 2.1 rlimit-Primary Architecture

```
Z3 command: z3 -smt2 -in
  ↳ (set-option :rlimit 30000000)  ← Deterministic CPU-step budget (z3DeterministicBudget)
  ↳ (set-option :timeout 60000)   ← Liveness safety net ONLY (z3SafetyNetMs)
  ↳ (reset)
  ↳ <SMT queries>
  ↳ (echo "AXIOM_Z3_EOF_<n>")      ← Per-query framing sentinel
```

**`z3DeterministicBudget = 30,000,000` steps** (from `src/core/proof/proof_budget.nim`)
- CPU-independent (Z3 4.5+ documentation)
- Same result on any hardware under same Z3 binary
- SSOT reference: `proof_budget.z3DeterministicBudget`

### 2.2 Sentinel-Based I/O Framing (Not Wall-Clock)

The read loop terminates on sentinel, not on wall-clock:

```
┌─────────────────────────────────────────────────────────────┐
│                    Z3 Process                                │
│                                                              │
│  (reset)                                                     │
│  <query assertions>                                          │
│  (echo "AXIOM_Z3_EOF_1")                                     │
│  ...output lines...                                          │
│  AXIOM_Z3_EOF_1                                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
           ↑
           │ read line by line until sentinel matches
           │
┌─────────────────────────────────────────────────────────────┐
│                   Parent Process                             │
│                                                              │
│  POSIX read() → accumulate lines                            │
│  if line.strip() == "AXIOM_Z3_EOF_N": break                  │
│                                                              │
│  Sentinel framed by z3_pool.nextZ3Sentinel() counter         │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Readiness State Barrier

```
AXIOM_Z3_SPAWN_READY
    ↓ (written by Z3 after (reset))
    │ read loop waits for this marker
    │
    └─> if NOT found within 2000ms I/O-only timeout:
           worker.ready = false
           return error
    ↓
worker.ready = true  (spawn successful)
```

The `ready` flag in `Z3PersistentWorker` gates worker reuse:
- `selectZ3WorkerIndex()` checks `worker.ready`
- If not ready, triggers `restartZ3PoolWorker()`

### 2.4 Wall-Clock as Liveness Safety Net ONLY

```
let livenessDeadlineMs = epochMilliseconds() + int64(z3SafetyNetMs)
```

- `z3SafetyNetMs = 60,000` (60 seconds)
- Never used as solve decision
- Applied ONLY to prevent infinite hangs
- `:timeout 60000` is injected in every SMT script

### 2.5 Protocol Tokens

| Token | Purpose | Timeout | Direction |
|-------|---------|---------|-----------|
| `AXIOM_Z3_SPAWN_READY` | Spawn barrier | 2000ms I/O-only | Write → Read |
| `AXIOM_Z3_EOF_<n>` | Per-query framing | `z3SafetyNetMs` | Read sentinel |
| `AXIOM_Z3_CLEAN_READY` | Post-query reset handshake | 1000ms I/O-only | Write → Read |

## 2b. Random-Seed Pinning (P2a)

### Problem

Z3's Spacer engine (used for CHC / PDR invariant synthesis) is heuristic-driven.
Without an explicit seed, Spacer's internal search strategy can vary run-to-run on
the same query, producing different pivots, generalization order, and — in the
worst case — different `sat`/`unsat` results. This breaks the determinism contract
"identical input → identical output" for CHC paths that do not route through the
pool envelope.

### The Three Seed Options

Applied consistently across every SMT-LIB2 entry point:
- `(set-option :random-seed 0)` — global solver random seed
- `(set-option :sat.random_seed 0)` — SAT engine seed (`axiom_dsl.nim:233`)
- `(set-option :fp.spacer.random_seed 0)` — Spacer (fixedpoint) seed (`axiom_dsl.nim:234`)

Z3's default seed is already 0, so these are **behavior-preserving** — they make
the existing default explicit and immune to future toolchain changes, rather than
changing current solver behavior.

### Single Choke-Point Design

All pool-routed queries are normalized in one place — `buildZ3QueryEnvelope`
(`src/verification/solver/z3_pool.nim`). The three seed options are injected
**after** the existing rlimit + timeout injection and **before** the `(reset)`
prepend, so they are preserved across the reset and applied to every query that
flows through the persistent pool. This fixes ALL pool-routed queries at once
(no per-callsite drift).

### Defense-in-Depth in HORN Scripts

Two CHC paths do not use the pool envelope, so they pin the seed directly in the
emitted HORN prelude/script:
- `spacer_chc_router.nim` `buildSpacerScript` — right after `(set-logic HORN)`
- `fixedpoint_engine.nim` `chcPrelude`

This guarantees the same deterministic starting state regardless of which Z3
front-end (pool vs. one-shot script) is used.

### Audit Table

| Entry point | Location | Seed pinning | Notes |
|-------------|----------|-------------|-------|
| Pool envelope | `buildZ3QueryEnvelope` (`z3_pool.nim`) | 3 options after rlimit+timeout, before `(reset)` | Single choke point; fixes all pool-routed queries |
| HORN script | `buildSpacerScript` (`spacer_chc_router.nim`) | 3 options after `(set-logic HORN)` | Legacy one-shot CHC path |
| CHC prelude | `chcPrelude` (`fixedpoint_engine.nim`) | 3 options after `(set-logic HORN)` | Fixedpoint/PDR CHC path |
| DSL query | `queryZ3` (`axiom_dsl.nim:233-234`) | `sat.random_seed` + `fp.spacer.random_seed` | Pre-existing reference |

### SSOT Timeout Hygiene (P2a)

Hardcoded wall-clock defaults replaced with SSOT constants from
`src/core/proof/proof_budget.nim`:

| Hardcoded (before) | Replaced with | File |
|--------------------|--------------|------|
| `req.timeoutMs` CEGAR override | `cegarBudgetMs` (always) | `cegar_engine.nim:520` |
| `z3TimeoutMs: int = 10000` PDR default | `z3SafetyNetMs` | `pdr_engine.nim:70` |
| `timeoutMs: int = 30000` (sendSmtlibCommand) | `z3SafetyNetMs` | `spacer_chc_router.nim:296` |
| `timeoutMs: int = 30000` (trySpacerInvariantSynthesis) | `z3SafetyNetMs` | `spacer_chc_router.nim:339` |
| `timeoutMs: int = 30000` (trySpacerIntegration) | `z3SafetyNetMs` | `spacer_integration_gate.nim:107` |

## 3. Known Z3 Caveats

### 3.1 rlimit Counting is Non-Monotonic

Z3 Issue #56, #2711: Some phases may not increment rlimit.

**Mitigation**: Never rely on rlimit for completeness proofs. The determinism guarantee assumes:
- Fixed Z3 binary version
- Same input query
- Same fixed rlimit value

Cross-version comparisons are not deterministic.

### 3.2 rlimit is NOT a Substitute for Timeout

Under extreme conditions (e.g., proof reconstruction), Z3 may not increment rlimit.

**Mitigation**: `z3SafetyNetMs` acts as ultimate fallback. The probability of hitting this is < 0.01% in practice.

### 3.3 Default Tactics Embed try_for Timers

Some tactics (e.g., `smt`, `alethe`) internally use `try_for` timers.

**Mitigation**: QF_BV bit-blast path is low-risk. For critical paths, consider `use_data_letter` option.

### 3.4 Memory Limits are Non-Recoverable

Z3's `:memory` option cannot be recovered from.

**Mitigation**: Do not use. Use external process monitoring via `z3SafetyNetMs`.

## 4. Failure Semantics

| Result | Classification | Meaning |
|--------|----------------|---------|
| `unsat` | Success | Property proven |
| `sat` | Fail | Counterexample found |
| `unknown` | Fail | Could not determine |
| `timeout` | Fail | `deadline`/`timeout` in error |
| `error` | Fail | Other solver error |

### Telemetry Classification Logic

```
defer:
  if z3Result.isOk():
    output = z3Result.get().toLowerAscii()
    if output.contains("unsat"): resultStatus = "unsat"
    elif output.contains("sat"): resultStatus = "sat"
    elif output.contains("unknown"): resultStatus = "unknown"
  else:
    errLower = z3Result.error().toLowerAscii()
    if errLower.contains("deadline") or errLower.contains("timeout"):
      resultStatus = "timeout"
    else:
      resultStatus = "error"
```

**Note**: A default-initialized `Result[string, string]` has `error = ""`, classified as `"error"`.

## 5. Verification

To verify deterministic behavior:

```bash
# Run the same query twice, results should be identical
echo "(assert (not (= x x))) (check-sat) (get-model)" | z3 -smt2 -in :rlimit 30000000 :timeout 60000
echo "(assert (not (= x x))) (check-sat) (get-model)" | z3 -smt2 -in :rlimit 30000000 :timeout 60000
```

Expected: Both return `unsat` with identical model.

## 6. Configuration Reference

| Constant | Value | Source | Purpose |
|----------|-------|--------|---------|
| `z3DeterministicBudget` | 30,000,000 | `proof_budget.nim` | rlimit steps (CPU-independent) |
| `z3SafetyNetMs` | 60,000 | `proof_budget.nim` | Wall-clock liveness net (ms) |
| `z3ReadMinDeadlineMs` | 1000 | DEPRECATED | Minimum read deadline (removed in v31) |
| `z3ReadStepTimeoutMs` | 50 | z3_pool.nim | Poll interval for data ready |

## 7. Related

- `docs/spec/hermetic_z3_pinning.md` — Ensuring same Z3 binary across builds
- `src/core/proof/proof_budget.nim` — Budget SSOT
- `src/verification/solver/z3_pool.nim` — Implementation
- `src/verification/batch_uap/ir_pipeline_runner.nim` — Pipeline integration