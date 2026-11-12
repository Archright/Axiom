# Execution Liveness Contract

Status: **contract (v1)** — defines the liveness/observability requirement for
every external-process invocation in Axiom's verification and gate execution
paths. Where a mechanism exists, it is cited. Where it is required but **not yet
implemented**, it is explicitly marked `REQUIRED` (never described as present).

> Scope discipline (this repository's invariants): liveness is an execution
> **boundary** contract, not a memo/identity/cache concern. This document does
> NOT touch `QueryID`, result reuse, the memo subsystem, the gate daemon, or CI
> workflow YAML. Those are unchanged by this contract.

---

## 1. Problem statement

The reference incident (a 100-minute undetected hang, ~181 `ax` processes forked
recursively with no progress) exposed two distinct determinism gaps:

| Gap | Nature | Correct resolution |
|---|---|---|
| `serial != parallel` artifact | build path leaking into binary identity | hermetic/reproducible build (separate contract: `docs/spec/artifact_determinism.md`) |
| 100-minute hang undetected | only process *termination* was observed, not *progress* | explicit liveness / progress contract (this document) |

The common root: **if no observable liveness contract exists, the system cannot
decide what actually happened.** This document defines that contract for
execution.

---

## 2. Invariants

- **I-LIV-1 (bounded execution):** every external subprocess spawned by Axiom is
  bounded by a *containment* deadline. A deadline bounds **lifetime**, never
  *correctness*: reaching it is a FAIL-CLOSED outcome, not a verdict.
- **I-LIV-2 (progress observability):** long-running computation exposes a
  monotonic *progress epoch* (or equivalent monotonic witness). A constant epoch
  across a threshold ⇒ `LIVENESS VIOLATION` ⇒ fail-closed.
- **I-LIV-3 (recursion bound):** a single Axiom execution must not recursively
  launch an unbounded chain of sibling Axiom processes. `REQUIRED`: an execution
  token / depth bound so the second recursive invocation fails immediately rather
  than accumulating processes. *(Not enforced in code today — see §6.)*
- **I-LIV-4 (fail-closed):** liveness machinery never falls open. A hung-but-not-
  dead process is treated as a failure, never silently waited on indefinitely.
- **I-LIV-5 (ambient signals are forensic, not adjudicative):** log `mtime`, `ps`,
  CPU usage and D-state are **diagnostic fallback only**. The liveness verdict is
  decided by the monotonic witness alone.

---

## 3. Witness surfaces (existing)

The following are real, verifiable surfaces already present in the codebase. The
liveness supervisor consumes these as liveness evidence:

| Surface | Source | Role |
|---|---|---|
| `BatchUapProgressSink` | `src/verification/batch_uap/private/types.nim` (`proc(nodeId, status)`) — invoked in `loop_depth_scheduler.nim`, `loop_driver.nim`, `certificate_hydration_runner.nim` | Per-node in-process progress events (`CACHE-HIT` / `VERIFIED` / `PROCESSED`) on the verification hot path |
| `atomicWriteProofState` | `src/verification/state_persistence.nim` (I/O-boundary `axiomIoBoundary` module; durable `logs/ax_proof_state.json`) | Durable proof-state snapshot that advances as verification makes progress |
| Trajectory `extra` | `src/verification/unified_trajectory.nim` (`entry["extra"] = extra`) | Extensible per-entry metadata channel |

---

## 4. Bounded-execution baseline (verified current state)

The live verification and gate execution paths are **already liveness-bounded**
at the spawn sites that matter. Cited for auditability:

| Site | Bounding mechanism |
|---|---|
| Heavy-gate scheduler | `src/gate/orchestrator/hook/executor.nim` `pollL2GatesWithTimeout(…, effectiveTimeoutMs)` — per-gate SLA deadline with kill-on-timeout |
| Lean REPL / kernel | `src/verification/lean_repl_bridge.nim` `waitForExit(timeoutMs)` |
| Z3 solver | `src/verification/spacer_chc_router.nim` `z3SafetyNetMs` deadline |
| Hermetic build / verify | `src/verification/lean_build_sandbox.nim` `execCmdWithTimeout(…, timeoutMs)` |
| Generic bounded exec | `src/infrastructure/process_utils.nim` `execCmdWithTimeout` (supports an optional `progressProbe` since the Layer-4 extension — see §5) |

The few remaining unbounded `startProcess`/`execCmdEx` sites are **orphaned**
(no live callers, e.g. `src/gate/framework/hermetic_runner.nim`) or deliberate
exit-code-fidelity wrappers (e.g. `src/gate/utils/git_wrapper.nim`). They are not
on the critical verification path; they are inventoried here so a future PR can
bound them without touching identity/reuse/memo/daemon/CI-yaml.

---

## 5. The `progressProbe` primitive (Layer 4 extension)

`execCmdWithTimeout` (`src/infrastructure/process_utils.nim`) now accepts an
optional `progressProbe: proc(): bool`:

```nim
proc execCmdWithTimeout*(
  cmd: string;
  workingDir: string = "";
  timeoutMs: int = defaultExecTimeoutMs;
  progressProbe: proc(): bool {.nimcall, raises: [], gcsafe.} = nil
): (string, int)
```

Semantics:

- **Probe absent** (`nil`): deadline-only containment — backward compatible with
  the original behavior.
- **Probe present**: once the deadline is reached, if the probe has returned
  `true` at least once (i.e. there is liveness evidence), the deadline is
  **extended** to `lastProgressMs + timeoutMs`; otherwise / thereafter the
  process is `SIGTERM` → (2 s) → `SIGKILL` and the call fails closed.

The deadline is **containment**, never a *correctness* signal: a long but
progressing computation is allowed to run; a stalled one is killed.

`REQUIRED`: the caller that wraps a long-running subprocess should pass a
`progressProbe` that reads a monotonic witness from §3 (e.g. an epoch counter on
the proof-state / trajectory surface), so the extension window is granted only
while liveness evidence is actually arriving.

---

## 6. Not-yet-implemented contract requirements (honest gaps)

These are stated as requirements for a follow-on execution-boundary slice. They
exist **nowhere in code today** and are listed so the contract is not conflated
with the present implementation.

1. **Epoch emission (`I-LIV-2`):** a monotonic counter/epoch advanced by the
   verification loop and surfaced through a §3 witness (proof-state JSON or
   trajectory `extra`). Existing sinks emit per-node events but do not yet
   publish a single sealed, monotonic epoch that a supervisor can compare
   across two samples.
2. **Supervisor watchdog (`I-LIV-2`):** `REQUIRED` a fail-closed watchdog that
   samples the epoch witness, and flags `LIVENESS VIOLATION` when the epoch is
   frozen past a configured threshold. Only the monotonic witness is adjudicative
   (§ `I-LIV-5`); `log mtime`/CPU/`ps` remain forensic.
3. **Recursion bound (`I-LIV-3`):** `REQUIRED` an execution token / max-depth
   guard so an `ax` → `ax` → … chain is rejected at the second invocation
   instead of growing unbounded (the ~181-process failure mode).
4. **Execution boundary unification:** `REQUIRED` a single `AxiomExecutionBoundary`
   entry that lays down the token, registers the progress channel, and attaches
   deadline/liveness for *every* command — replacing the weaker "preflight only
   checks `--version`" pattern.

These follow-on items target **execution** and do not alter verification
semantics, identity, reuse, memo, daemon, or CI YAML — consistent with the
Phase-4 scope boundary.

---

## 7. Fail-closed adjudication

```
sample witness epoch E1 at t0
sample witness epoch E2 at t1   (t1 - t0 = pollInterval)

E2 > E1        → ALIVE  (continue; deadline becomes E1 + window)
E2 == E1       → stall counter += 1
                 stall counter > threshold → LIVENESS VIOLATION → FAIL-CLOSED
E2 < E1        → impossible (monotonic violation) → FAIL-CLOSED
```

- Reaching a containment deadline ⇒ FAIL-CLOSED (kill, record `timeout`),
  independent of the stall counter.
- A `LIVENESS VIOLATION` is a *liveness* failure (`BLOCKED_BY_RUNTIME_SUBSTRATE`),
  distinct from a semantic FAIL. Axiom never reports a liveness stall as a
  verification verdict.

---

## 8. Acceptance criteria for this contract

- **[A1]** Every spawning site on the verification hot path is either bounded
  (§4) or explicitly inventoried as orphaned/deliberate (§4). — **verifiable now.**
- **[A2]** `execCmdWithTimeout` with a `progressProbe` compiles and the extension
  semantics are documented (§5). — **verifiable after Layer-4 build.**
- **[A3]** `REQUIRED` items in §6 carry no fabricated "present" claims in this
  doc and are tracked as follow-on work. — **verifiable by inspection.**
