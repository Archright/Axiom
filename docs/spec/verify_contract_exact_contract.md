# verify-contract — Local Exact Contract

**Status**: Active
**Created**: 2026-09-04
**Source of truth**: `Makefile` (`verify-contract`/`verify-contract-serial`/`verify-contract-unit`/`verify-invariant-mutation`/`verify-scenario-oracles`/`verify-contract-release-e2e`), `tools/hermetic_build.nim --check-source-hash` (CI job definitions retired with the CI=0 cutover, 2026-09-20)
**Invariant**: `LocalExact(STATE) == CI(STATE)` — CI 레이어 소멸(CI=0, 2026-09-20) 후에도 로컬 실행 간 결정성 불변식으로 유지

---

## Purpose

This document defines the canonical contract for reproducing the `verify-contract` CI job
locally with **bit-identical semantics**. Two executors — the CI runner and the local
developer runner — must reach the same verdict for every subtarget if the input snapshot,
preflight substrate, and toolchain are identical.

The contract does not introduce new gates or new tooling. It documents the existing
ordered pipeline so that any deviation (local vs CI, or across CI runs) is detectable,
attributable, and actionable.

The verify-contract pipeline guards the Productization Contract Preservation invariant
(GO 6조건 회귀 방어). ENFORCED = G1 ∧ G2 ∧ G4 ∧ G6 ∧ G7 (G3 = Engineering Guard,
here excluded). CI runs `make verify-contract` as a single entrypoint; this document
records the local exact path that mirrors it.

---

## The LocalExact Invariant

```
LocalExact(STATE) == CI(STATE)
```

- **Same subtarget set** — all 4 subtargets are executed, in the declared order, without omission
- **Same order** — step N runs only after step N−1 has reported
- **Same argv / env / policy** — source snapshot, generated-artifact manifest, debt baseline,
  and toolchain identity are pinned (see §Input Closure)
- **Same per-subtarget verdict** — a failure records the same subtarget id and exit code
  locally as it would in CI; accepting that "Local FAIL == CI FAIL semantically"

An intentional violation (e.g., a known broken invariant that deliberately fails one subtarget)
must fail locally **and** in CI with the **same subtarget id + exit code**. It is not
sufficient to match only the aggregate verdict.

---

## Runtime Substrate Preflight

Before any verify-contract subtarget runs, two independent substrate contracts must be
satisfied. They are **separated** — a single combined target would conflate distinct
failure modes and obscure the root cause.

### Contract A — Build State Coherence

- **Trigger**: `bin/hermetic_build --check-source-hash` (bin/ax is **not** executed)
- **Mechanism**: Compares the embedded `BuildSourceHash` in `src/generated/build_env.nim`
  against a live recomputation of the `src/` tree hash via `computeDeterministicSourceHash`.
- **Pass**: `[build-coherence] PASS` + exit 0 (build state is coherent; no rebuild needed)
- **Fail**: `[build-coherence] FAIL` + exit 1 (embedded hash ≠ live tree hash; the binary
  is stale relative to source — a self-rebuild would be triggered by `checkAndSelfBootstrap`
  at `src/cli/main.nim:77-110`)
- **Failure reason**: `BLOCKED_BY_BUILD_STATE_COHERENCE` (fail-closed exit 1)
- **Non-destructive**: bin/ax is never executed; no files are written or modified.

### Contract B — Binary Liveness

- **Prerequisite**: Contract A must pass first. Contract B is meaningless if the build state
  is incoherent — a stale binary could liveness-pass but carry wrong logic.
- **Trigger**: `bin/ax --version`
- **Mechanism**: Verifies that `bin/ax` is executable (`test -x`) and terminates within
  120 seconds (`timeout 120`).
- **Pass**: exit 0, prints version info (discarded to `/dev/null`)
- **Fail**: `BLOCKED_BY_BINARY_LIVENESS` with one of:
  - `bin/ax not executable` — file missing or not executable
  - `bin/ax --version did not terminate within 120s` — hung process (timeout exit 124)
  - `bin/ax --version exit=N` — non-zero exit code N ≠ 124
- **Failure reason**: `BLOCKED_BY_BINARY_LIVENESS` (fail-closed exit 1)
- **Timeout note**: 계약은 '필수 command가 종료한다'이며 timeout 수치는 검사 수단.
  The 120s ceiling is a safety bound, not a semantic contract.

### BLOCKED Semantics

`BLOCKED_BY_*` is expressed as a `failureReason` string + `exit 1`. No new `CliOutcome`
enum value is introduced — the 4-state exit contract (`src/cli/cli_outcome.nim:10-31`)
remains unchanged. The preflight contracts are Makefile-level guards that operate outside
the Nim exit-code mapping.

---

## Input / Policy / Environment Closure

For `LocalExact == CI` to hold, every variable the subtargets inspect must be pinned.

### Source Snapshot

The working tree at invocation time. The CI job first performs a destructive reset
(`git reset --hard HEAD && git clean -ffdx …`) to establish a clean snapshot. Locally,
the developer is responsible for a clean tree (enforced by the purity check, step 18 of
the verify-static pipeline). The preflight contracts are non-destructive (see
§Non-Destructive Reuse).

### Generated Artifacts

These files are produced by code-generators during the gate run and are **not**
pre-committed in CI. Locally they must be regenerated by the drift-guard steps
(steps 15–16 of verify-static):

| Path | Generator |
|------|-----------|
| `src/gate/manifest.d/*.json` | `tools/sync_topology.nim` |
| `src/generated/manifest_registry.nim` | `tools/sync_topology.nim` |
| `src/generated/gate_registry.nim` | `tools/sync_topology.nim` |
| `src/generated/helper_registry.nim` | `tools/sync_topology.nim` |
| `config/gates.manifest.toml` | `tools/sync_topology.nim` |
| (decision graph artifacts) | `tools/sync_decisions.nim` |

### Debt Baseline

`data/nimtry_baseline.json` — the tracked snapshot used by the debt gate (step 5 of
verify-static).

### Toolchain Identity

| Tool | Pin | Verified by |
|------|-----|-------------|
| Nim | 2.2.10 | `nim --version` (via `check-toolchain-pin`) |
| Z3 | 4.13.3 | `z3 --version` |
| Lean | 4.33.0 | `lean --version` |

Pins are installed by `.github/actions/setup-axiom-toolchain` and verified in the
CI determinism-guard step. Locally, `make check-toolchain-pin` verifies these pins
without modifying the tree.

### Environment Variables

| Variable | Value | Effect |
|----------|-------|--------|
| `AXIOM_CI` | `1` | Enables CI-only guards and suppresses interactive prompts |
| `AXIOM_CI_PRESERVE_CACHE` | `1` | Prevents cache invalidation between gate runs |
| `AXIOM_HERMETIC_BUILDING` | (set by `check-build-state-coherence`) | Signals hermetic build mode to `hermetic_build` |
| `AXIOM_PROVE_WORKERS` | `1` | Forces sequential prove path (DEBT#415; CI also uses workers=1) |

All four must be set for local runs that seek CI-equivalent behavior. `AXIOM_PROVE_WORKERS=1`
is required because the CI runner used a single worker (see admission_producer.yml `verify-integration` job,
line 188 — CI=0 cutover, 2026-09-20로 해당 job 소멸, 단일 worker 근거는 설계 기록으로 유지); the parallel-worker
robustness defect is tracked separately and MUST NOT be re-enabled without a root-fix.

### Immutable Fixture Concept

The local exact path assumes a **fixed commit + prepared artifacts** as the immutable
fixture. The developer must not introduce new source changes between preflight and
subtarget execution. Any source mutation invalidates the snapshot and breaks the
`LocalExact == CI` invariant.

---

## Canonical Step Table

The verify-contract pipeline has two execution modes: **parallel** (CI and `make verify-contract`)
and **serial** (`make verify-contract-serial`). Both modes execute the same 4 subtargets;
only the concurrency differs.

### Parallel Mode (CI and `make verify-contract`)

| # | CI Step Name | Local Makefile Target | Semantic Contract |
|---|--------------|----------------------|-------------------|
| 1 | G2 — unit tests | `make verify-contract-unit` | Runs 10 canonical contract invariant unit tests (resolveNodeOutcome, evidence propagation, candidate eligibility, execution identity, bundle digest, promotion semantics, certificate eligibility, proof state machine, doc reference, make probe). Uses isolated `--nimcache:build/nimcache/verify-contract-unit`. |
| 2 | G1 — invariant mutation | `make verify-invariant-mutation` | Runs the mutation harness (`tools/invariant_mutation_harness.sh`) in an isolated worktree via `bin/purity_check --warm-nimcache --exec-cmd`. M1/M2/M3 mutations must die. |
| 3 | G6·G4 — oracles + fail-closed | `make verify-scenario-oracles` | Scenario 5 (state manager self-healing projection count), Scenario 6 (evidence truth boundary oracle), G6 runtime/reference DATA-FLOW (prove, journal-not-reference, reference-divergence), G4 negative compile-reject (`forge_receipt_external.nim` must fail to compile). Uses isolated `--nimcache:build/nimcache/verify-scenario-oracles`. |
| 4 | G7 — release E2E | `make verify-contract-release-e2e` | Builds release `bin/ax` if missing, then: `sha256sum bin/ax`, `bin/ax scope hash`, `bin/ax prove --target normalizeMaxWorkers`, `bin/ax report --json`, `bin/ax status --json`. Uses isolated `--nimcache:build/nimcache/verify-contract-release-e2e`. |

#### Parallel orchestration (Makefile 336-355)

The 4 subtargets run concurrently via shell `&` background jobs + `wait`. Each job
writes its PID, log, and exit status to `.verify-contract-logs/`:

| File | Subtarget | Content |
|------|-----------|---------|
| `.verify-contract-logs/g2.pid` | G2 | PID of background job |
| `.verify-contract-logs/g2.log` | G2 | stdout/stderr capture |
| `.verify-contract-logs/g2.status` | G2 | Exit code (0 = PASS) |
| `.verify-contract-logs/g1.pid` | G1 | PID of background job |
| `.verify-contract-logs/g1.log` | G1 | stdout/stderr capture |
| `.verify-contract-logs/g1.status` | G1 | Exit code |
| `.verify-contract-logs/g6g4.pid` | G6·G4 | PID of background job |
| `.verify-contract-logs/g6g4.log` | G6·G4 | stdout/stderr capture |
| `.verify-contract-logs/g6g4.status` | G6·G4 | Exit code |
| `.verify-contract-logs/g7.pid` | G7 | PID of background job |
| `.verify-contract-logs/g7.log` | G7 | stdout/stderr capture |
| `.verify-contract-logs/g7.status` | G7 | Exit code |

After `wait`, the orchestrator reads each `.status` file; any non-zero exit code
triggers a FAIL report with the subtarget name and exit code. The `.verify-contract-logs`
directory is removed after reporting. If any subtarget failed, `make verify-contract`
exits 1.

#### Shared artifact prebuild — Build once → Freeze → Fan-out (DEBT#457)

`verify-contract` declares `verify-contract-artifacts` as a normal make
prerequisite, so the shared generated binaries are materialized exactly once,
serially, BEFORE any subtarget fans out: `bin/feature_manifest_generator` and
`bin/sync_certs` (stable `--out:` names — the `--usenimcache` per-params hash
suffix is dropped for these two tools). The serial compile also warms
`hermeticPreBuild` artifacts (`bin/hermetic_build`, `bin/sync_topology`,
`bin/decision_binding_checker`), closing the fresh-checkout parallel build hole.

Invariants enforced by the structure:

- **A — no shared-artifact writes in the parallel phase**: `config/integrity.nims`
  hooks never compile under `AXIOM_VERIFY_CONTRACT_FANOUT=1`; they only execute
  the frozen binaries. (Documented single-writer exception: G7 rebuilds `bin/ax`,
  which no other subtarget reads concurrently.)
- **B — artifacts exist before fan-out, fail-closed**: a missing frozen binary
  under the guard aborts the subtarget (`FANOUT fail-closed ... missing`), never
  silently skips.
- **C — read-only after fan-out**: the parallel phase consumes the artifacts
  execute-only; `--ensure` is idempotent when fresh (no write).
- **D — scheduling-independent evidence**: with the parallel write edge removed,
  subtarget scheduling cannot change the evidence produced.

Rationale: `nim c -r` relinks and overwrites the output binary on every
invocation (no binary freshness skip — `compiler/main.nim` `setOutFile`), so
concurrent hooks relinking `bin/<tool>_<usenimcache-hash>` raced
writer↔writer and writer↔executing-process (ETXTBSY / Permission denied).
The write edge is removed from the concurrency graph rather than locked.

### Serial Mode (`make verify-contract-serial`)

| # | Makefile Target | Semantic Contract |
|---|----------------|-------------------|
| 1 | `verify-contract-unit` | Same as parallel G2 |
| 2 | `verify-invariant-mutation` | Same as parallel G1 |
| 3 | `verify-scenario-oracles` | Same as parallel G6·G4 |
| 4 | `verify-contract-release-e2e` | Same as parallel G7 |

Serial mode runs subtargets sequentially with `|| exit 1` after each, providing a
deterministic baseline for D3 cross-check against the parallel mode.

### Nimcache Isolation

Each subtarget uses a dedicated `--nimcache` path under `build/nimcache/` to prevent
cache collisions between parallel runs:

| Subtarget | Nimcache Path |
|-----------|---------------|
| verify-contract-unit | `build/nimcache/verify-contract-unit` |
| verify-scenario-oracles | `build/nimcache/verify-scenario-oracles` |
| verify-contract-release-e2e | `build/nimcache/verify-contract-release-e2e` |

`verify-invariant-mutation` uses `--warm-nimcache` via `bin/purity_check` and does not
have a dedicated nimcache path (it runs in an isolated worktree).

---

## SideEffectContract

> **Note**: This section is scoped for P5 D3 experimental use (agent-validated schema).
> It describes the side-effect contract that a correct verify-contract run must satisfy.
> It is not a gate — it is a specification for what outputs are expected and what writes
> are permitted or forbidden.

### Required Outputs

| Artifact | Required | Normalization |
|----------|----------|---------------|
| `logs/ax_proof_state.json` | Yes | `timestamp` and `sourceRoot` fields excluded from comparison; `entries[]` sorted by canonical key |
| `.axiom/cache/gate_memo/` CAS entries | Yes | `timestamp` field excluded from comparison |
| `.axiom/cache/gates/` CAS binaries | Yes | Hash-filename authenticated (no fields excluded) |
| Hash filename certificates | Yes | No fields excluded |

### Permitted Temporary Outputs

| Artifact | Condition |
|----------|-----------|
| `gate_memo/.epoch` | PID\|timestamp marker |
| `gate_memo/.migration_lock` | PID\|timestamp marker |
| `gate_output/*.log` | Per-subtarget log output |
| `build/certificates/` | Transient build artifacts |
| `build/nimcache/` | Compilation cache (isolated per subtarget) |
| `data/trusted/certificates/` | Promotion-only (see Forbidden Writes) |

### Forbidden Shared Writes

| Artifact | Reason |
|----------|--------|
| `data/trusted/certificates/` direct write | Must use promotion flag only; direct write bypasses canonical identity check |
| `logs/ax_proof_state.json` concurrent write | G7 is the sole writer; concurrent writes from other subtargets corrupt the canonical state |
| `src/verification/certificates/` | Read-only; any write is a contract violation |

---

## Non-Destructive Reuse Principle

### Preflight Contracts Are Non-Destructive

- **Contract A** (`check-build-state-coherence`): Runs `bin/hermetic_build --check-source-hash`,
  which reads `src/generated/build_env.nim` and the `src/` tree. No files are written or
  modified. bin/ax is never executed.
- **Contract B** (`check-binary-liveness`): Runs `test -x bin/ax` and `timeout 120 bin/ax --version`.
  The `--version` flag is read-only; no state changes occur.
- **`check-toolchain-pin`**: Verifies toolchain pins via `grep` on version output. Read-only.

None of the preflight contracts modify tracked files, untracked files, or the working tree.

### Contrast with CI's Destructive Reset

The CI determinism-guard step runs `git clean -ffdx` to establish a clean snapshot.
The local exact path does **not** reproduce this command. The developer is responsible
for a clean tree before invocation.

---

## How to Run

### Standard Local Execution

```bash
AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 AXIOM_PROVE_WORKERS=1 make local-verify-contract-exact
```

This aggregate target runs the substrate preflight contracts (A then B), then
`check-toolchain-pin`, then `verify-contract` (parallel mode). All `AXIOM_CI*` env vars
must be set to suppress interactive prompts and enable CI-only guards.

### Serial Baseline Execution

```bash
AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 AXIOM_PROVE_WORKERS=1 make verify-contract-serial
```

Runs the same 4 subtargets sequentially. Useful for D3 cross-check (parallel vs serial
must produce the same verdicts).

### Detached Substrate Execution

For running in an isolated git worktree (e.g., for reproducibility testing):

```bash
# 1. Create a detached worktree at the target commit
git worktree add --detach /tmp/axiom-test <commit-hash>

# 2. Enter the worktree
cd /tmp/axiom-test

# 3. Bootstrap the CI-equivalent environment
make ci-bootstrap

# 4. Run the local exact gate
AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 AXIOM_PROVE_WORKERS=1 make verify-contract
# or, with preflight:
AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 AXIOM_PROVE_WORKERS=1 make local-verify-contract-exact
```

---

## Boundaries / Non-Goals

This document defines the **contract** for the `verify-contract` pipeline. It explicitly
does **not**:

- Modify `Makefile` subtarget definitions — the Makefile targets are the authoritative source (§-1; CI workflow definitions retired with the CI=0 cutover, 2026-09-20)
- Modify `AGENTS.md` or any gate implementation
- Introduce new gate names — all subtargets reuse the exact Makefile targets listed above
- Modify the Makefile — the `local-verify-contract-exact` aggregate target and preflight
  contracts are being added in parallel (tracked as work items P3/P4)
- Enable new memoization, cache-reuse, or daemon modes that would alter gate semantics
- Introduce new `CliOutcome` enum values — the 4-state exit contract (`src/cli/cli_outcome.nim:10-31`) is preserved unchanged; BLOCKED is expressed as `failureReason` string + exit 1
- Substitute a different test runner for any subtarget implementation
- Introduce new identity, memo, or reuse layers — P0 exact path is the reference oracle

Any change that alters the subtarget set, subtarget order, or subtarget verdict for a given
input snapshot is a **contract violation** and must be documented as a revision to this
document before being merged.

---

## Revision History

| Date | Change |
|------|--------|
| 2026-09-04 | Initial commit — document verify-contract canonical 4-subtarget pipeline, LocalExact invariant, substrate preflight contracts (A: build state coherence, B: binary liveness), and parallel/serial execution modes |
