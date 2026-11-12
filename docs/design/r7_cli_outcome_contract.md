# R7 CLI Outcome Contract — Design Document

> **Status**: DRAFT (Phase 3 — Productization Redesign)
> **SSOT anchor**: `docs/spec/productization_contract.md` §v1 CLI Exit-State Contract
> **Predecessor**: `docs/adr/0015-phase0-decision-gate-evidence-boundary.md` (Phase-0 decision gate)

---

## Objective

Define a **self-contained presentation contract** that maps internal verification results → canonical `CliOutcome` states → process exit codes in **one place**. This eliminates the current exit-drift problem where:

- Invalid-input paths emit `exit(1)` instead of the contract-specified `exit(3)` (`src/cli/action_plan_cli.nim:233,242`)
- Internal errors surface as SIGSEGV(139) with no handler at the CLI boundary (`src/cli/main.nim` — no signal handler; `action_interpreter_cli.nim:186-193` catches Exception but still `quit(1)`)
- ~28 scattered `quit()` calls across `action_interpreter_cli.nim:72-204` bypass any centralized mapping authority
- JSON output and process exit are independent channels but consumers may conflate them

The contract must be **deterministic**, **testable**, and **auditable** — one function, one table, one boundary.

---

## Canonical States (CliOutcome)

### Definition

```
CliOutcome = enum
  SUCCESS              # Verification ran; no failures
  NOT_CURRENT          # Artifact is valid but not current product truth (stale toolchain / execution contract)
  VERIFICATION_FAILURE # Verification ran; >=1 failed node / 0 verified (artifact integrity violation)
  INVALID_INPUT        # CLI argument / schema error
  INTERNAL_ERROR       # Normal-classifiable internal error (Nim unhandled exception)
```

### Numeric Mapping (grounded in productization_contract.md §v1 CLI Exit-State Contract)

| CliOutcome | Exit code | Semantic meaning | Current behavior | v1 target | Status |
|---|---|---|---|---|---|
| `SUCCESS` | `0` | Verification ran; no failures | `ax prove` → 0 (`wf_runners.nim:35-68`, dispatched at `axiom_engine.nim:562`); `ax report --json` → 0 when `verified>0 && failed==0` (`report_engine.nim:25-31`, called at `report_cli.nim:484`) | 0 | SATISFIED |
| `NOT_CURRENT` | `4` | Artifact is structurally valid but not current product truth (stale toolchain / execution contract) | N/A — new in Phase 5 | 4 | SATISFIED |
| `VERIFICATION_FAILURE` | `1` | Verification ran; >=1 failed node / 0 verified (artifact integrity violation) | `ax report --json` → 1 (`report_engine.nim:28-31`); `ax prove` → 1 on ordinary failure (`wf_runners.nim:58-67`) | 1 | SATISFIED |
| `INVALID_INPUT` | `3` | CLI argument / schema error | `1` — parser path `quit(1)` (`action_plan_cli.nim:233,242`) | 3 | OPEN-ITEM |
| `INTERNAL_ERROR` | `2` | Normal-classifiable internal error | `139` (SIGSEGV) — observed; no handler installed at CLI boundary | 2 | OPEN-ITEM |

### Justification for Exact Mapping (0/1/2/3)

The existing productization contract already defines this exact numeric mapping (`productization_contract.md:263-271`). Changing it would break:

- Contract tests in `tests/unit/wf_runners_exit_code_test.nim`
- Evidence envelope `commands.exitCode` assertions (`productization_contract.md:162`)
- R5 invariant keys (`successExitCode`, `verificationFailureExitCode`, etc.)

The mapping is minimal, non-overlapping, and fits within POSIX reserved range (0–255). Signal exits (e.g., 139) remain out-of-contract by design.

### State Precedence Rule

When multiple outcomes could apply to a single execution, precedence determines which wins:

```
INTERNAL_ERROR > INVALID_INPUT > VERIFICATION_FAILURE > NOT_CURRENT > SUCCESS
```

**Rationale:**

1. **INTERNAL_ERROR outranks everything**: If an internal fault occurs during input validation or verification, the result is unreliable — the consumer must know the system itself failed, not just that the input was bad or the proof failed.
2. **INVALID_INPUT outranks VERIFICATION_FAILURE**: A malformed request should never produce a "verification failed" result, because the verifier never actually ran. The consumer needs to fix the input, not investigate proof artifacts.
3. **VERIFICATION_FAILURE outranks NOT_CURRENT**: A broken artifact (structural/crypto integrity violation) is worse than a stale artifact (valid but not current product truth). The consumer must know the artifact is broken before learning it is stale.
4. **NOT_CURRENT outranks SUCCESS**: A stale-but-valid artifact is more informative than a generic success — the consumer needs to know the artifact is not current product truth.

**Implementation note**: Precedence is enforced at the dispatch layer — the first matching outcome (in precedence order) is selected before mapping to exit code. No two outcomes can coexist for a single action.

**Implementation**: The `CliOutcome` declaration is ordered by ascending severity — `SUCCESS(0) < NOT_CURRENT(1) < VERIFICATION_FAILURE(2) < INVALID_INPUT(3) < INTERNAL_ERROR(4)` — and that order is machine-checked directly via `ord` comparisons in the outcome tests. `exitCode` maps by name and is unaffected by that order. Run outcomes reach the CLI axis through `cliOutcomeForRun` (`CONTINUE → SUCCESS`, `BLOCK`/`UNRESOLVED → VERIFICATION_FAILURE`); the rule that produces them — including the aggregation precedence when multiple outcomes could apply — is `src/core/utils/decision_algebra.nim` `projectRunOutcome`.

---

## Centralized Exit Mapping

### The Single Mapping Table

```
CliOutcome ──→ Exit Code
──────────────────────────────
SUCCESS          → 0
VERIFICATION_FAILURE → 1
INVALID_INPUT    → 3
INTERNAL_ERROR   → 2
```

### The Single Mapping Function

One function, one location, the only place that maps `CliOutcome` → process exit:

```
proc cliOutcomeToExitCode(outcome: CliOutcome): int
```

Every command returns `CliOutcome` instead of calling `quit()` directly. The interpreter's `cliQuit` branch becomes:

```
of cliQuit:
  quit(cliOutcomeToExitCode(parseCliActionOutcome(action)))
```

Where `parseCliActionOutcome` derives the `CliOutcome` from the `CliAction.exitCode` field using the same table (normalizing legacy numeric codes back to canonical states).

### Collapse Analysis

Current state (before change):

| Location | Pattern | Count |
|---|---|---|
| `action_interpreter_cli.nim` | `quit(exitCode)` per command branch | ~28 guards |
| `action_interpreter_cli.nim` | `quit(1)` on engine error | 2 direct calls |
| `action_plan_cli.nim` | `quit(1)` on unknown subcommand | 2 direct calls |
| `main.nim` | `quit(ec)` on self-rebuild | 2 direct calls |
| **Total scattered exit points** | | **~34** |

After change:

| Location | Pattern | Count |
|---|---|---|
| `action_interpreter_cli.nim` | `cliQuit` → `cliOutcomeToExitCode()` | 1 call site |
| All commands | Return `CliOutcome` | 0 direct `quit()` calls |
| **Total scattered exit points** | | **1** |

The ~28 command branches in `action_interpreter_cli.nim:72-204` each currently do:

```nim
let exitCode = someCommand(args)
if exitCode != 0:
  quit(exitCode)
```

Under the new contract, each command returns `CliOutcome`. The interpreter collects the outcome and applies the single mapping once at the boundary. Commands that previously returned raw `int` exit codes will return `CliOutcome` instead, with the mapping applied centrally.

### CliAction Normalization

`CliAction(kind: cliQuit, exitCode)` is the existing mechanism for "terminate with this code." Under the new contract:

1. `planAxActions` produces `CliAction(kind: cliQuit, exitCode: N)` where `N` comes from the canonical mapping.
2. `interpretCliActions` receives `cliQuit` and calls `quit(cliOutcomeToExitCode(N))` — effectively a pass-through that documents intent.
3. For commands returning `CliOutcome` directly, the interpreter wraps them as `cliQuit` actions with the mapped exit code.

This preserves backward compatibility: existing `cliQuit` actions continue to work, but their `exitCode` values are now guaranteed to come from the canonical mapping.

---

## JSON/Report vs Process Exit

### Independent Channels

JSON output and process exit are **separate communication channels**:

- **JSON channel** (`outputJson` field in `AxCommandCliResult`): Data payload. Always emitted when `emitJson=true` (`report_cli.nim:480-485` — `$stateJson` is always serialized into `outputJson`). Contains structured verification results including `schemaVersion: "axiom.report.v1"` (`core/utils/constants.nim` — `axiomReportSchemaVersion`).
- **Process exit channel** (OS-level exit code): Control signal. Read by shells, CI systems, and orchestration tools. Determined by `CliOutcome` via the single mapping function.

### Consumer Contract

Consumers **must read the exit code, not infer success from JSON presence.**

Justification from current behavior (`productization_contract.md:278`):

> JSON is emitted regardless of exit code. Consumers must not infer success from JSON presence; read the exit code.

This is already the documented behavior. The design formalizes it as an invariant:

```
INVARIANT: JSON emission ≠ success. Exit code is the sole authority for control flow.
```

### Schema Version Anchor

Both `ax prove` output and `ax report --json` documents carry `"schemaVersion": "axiom.report.v1"` at the top level (`productization_contract.md:242`). This anchors the JSON data channel independently of the exit code channel.

---

## 5-State Gold Matrix

| Scenario | Expected CliOutcome | Exit Code | JSON Behavior |
|---|---|---|---|
| `ax prove` completes; all symbols verified | `SUCCESS` | 0 | Not applicable — `ax prove` has no `--json` flag (`productization_contract.md:277`). Report JSON consumed separately via `ax report --json`. |
| `ax prove` completes; >=1 symbol fails | `VERIFICATION_FAILURE` | 1 | Same as above — prove does not emit JSON. |
| `ax report --json` completes; `verified>0 && failed==0` | `SUCCESS` | 0 | JSON emitted with `summary.failed == 0`, `summary.verified > 0`. |
| `ax report --json` completes; `failed>0` or `verified==0` | `VERIFICATION_FAILURE` | 1 | JSON emitted with `summary.failed > 0` or `summary.verified == 0`. Exit code distinguishes from success. |
| Unknown subcommand (`ax foobar`) | `INVALID_INPUT` | 3 | No JSON emitted. Error message on stderr. |
| Missing required argument (`ax prove --limit abc`) | `INVALID_INPUT` | 3 | No JSON emitted. Error message on stderr. |
| Flag parsing error (`ax report --invalid-flag`) | `INVALID_INPUT` | 3 | No JSON emitted. Error message on stderr. |
| Unhandled Nim exception during verify | `INTERNAL_ERROR` | 2 | May or may not contain partial JSON. Exit code is authoritative. |
| `ax verify <cert>` — artifact structurally valid, current toolchain | `SUCCESS` | 0 | Not applicable — verify does not emit JSON. |
| `ax verify <cert>` — artifact structurally valid, stale toolchain | `NOT_CURRENT` | 4 | Not applicable — verify does not emit JSON. |
| `ax verify <cert>` — artifact integrity violation | `VERIFICATION_FAILURE` | 1 | Not applicable — verify does not emit JSON. |
| SIGSEGV / fatal OS signal | Out-of-contract | 139+ | Undefined. Process crash. Never shimmed to exit(2). |

### Key Properties

1. **JSON is always emitted on success/failure** (when `--json` requested), regardless of outcome.
2. **Invalid-input never emits JSON** — the pipeline short-circuits before any verification artifact is produced.
3. **Internal-error may emit partial JSON** — the contract does not guarantee JSON integrity in this case. Consumers must check exit code.
4. **Signal crashes are out-of-contract** — no mapping, no guarantee, no shim.

---

## Invalid-Input Contract

### Problem

Currently, invalid-input paths emit `exit(1)` instead of the contract-specified `exit(3)`:

- `action_plan_cli.nim:233` — empty args → `quit(1)`
- `action_plan_cli.nim:242` — unknown subcommand → `quit(1)`
- Parser-level errors in individual subcommands also route through `quit(1)` paths

This creates ambiguity: consumers cannot distinguish "bad input" from "verification failed" at the shell level.

### Design

Single path for all invalid-input scenarios:

```
User Input → parseInput() → InvalidInputError → CliOutcome.INVALID_INPUT → cliOutcomeToExitCode() → exit(3)
```

All entry points share this path:

1. **Top-level dispatch** (`action_plan_cli.nim:228-243`): Unknown subcommand, empty args, deprecated commands (`heal`) → `INVALID_INPUT`.
2. **Subcommand flag parsing** (generated parsers in `cli_surface_generated.nim`): Invalid flag values, missing required arguments → `INVALID_INPUT`.
3. **Argument validation** (per-command validators): Range checks, type mismatches → `INVALID_INPUT`.

### Implementation Principle

No command branch calls `quit()` directly for input errors. Instead:

- Flag parsers return `Result[Flags, string]` (error message).
- The plan layer converts parse errors to `CliAction(kind: cliQuit, exitCode: 3)`.
- The interpreter applies the canonical mapping (which maps `INVALID_INPUT` → 3).

This fixes the 3-vs-1 drift while preserving the existing `Result[T, string]` pattern already used throughout the CLI surface.

---

## Internal-Error Contract

### Problem

Currently, internal errors surface as:

- `action_interpreter_cli.nim:186-193` — `runAxiomEngine` catches `Exception` and calls `quit(1)` (not 2).
- `action_interpreter_cli.nim:195-196` — engine error result also calls `quit(1)`.
- SIGSEGV (139) — no handler at CLI boundary (`main.nim` — no signal handler). Observed bug state, not designed contract state.

### Design

#### Expected Internal Failures → INTERNAL_ERROR(2)

For classifiable internal errors (Nim exceptions, assertion failures, unexpected nil dereferences that are caught):

```
Exception caught → log stack trace → CliOutcome.INTERNAL_ERROR → cliOutcomeToExitCode() → exit(2)
```

The `cliRunAxiomEngine` branch in `action_interpreter_cli.nim:186-193` already catches `Exception` and logs the stack trace. Under the new contract, it returns `INTERNAL_ERROR` instead of calling `quit(1)`.

#### Fatal Signals → Out-of-Contract Process Crash

SIGSEGV, SIGABRT, SIGBUS, and other fatal OS signals remain **out-of-contract**. They are not mapped to any exit code. Observing them during supported execution is a Start blocker (R5/R8 FAIL).

**Rationale**: Signal handlers introduce non-determinism, potential deadlocks, and theater risk (§0.9). A signal handler that catches SIGSEGV and returns exit(2) is indistinguishable from a legitimate internal error — it masks the root cause. The correct behavior is:

1. Let the process crash (natural signal delivery).
2. Record the signal number in audit logs.
3. Treat as a bug, not a contract state.

**Start blocker condition**: If a SIGSEGV occurs on a supported execution path (i.e., a path that should be reachable with valid inputs), this is a critical defect that blocks release until fixed.

### No Signal-to-Exit Shim

```
INVARIANT: No signal → exit-code conversion shim shall be introduced.
```

This is a hard prohibition aligned with the constitution's theater prevention rules (§0.9) and the infinite-regress termination principle (§0.9b). A signal handler that claims to "handle" SIGSEGV is performing theater — it cannot recover from a segfault deterministically.

---

## Application Scope

### Command Surface Enumeration

From `action_plan_cli.nim:153-214` (`parseAxSubcommandKind`), the full list of recognized subcommands:

| # | Subcommand | Type |
|---|---|---|
| 1 | prove | Primary product surface |
| 2 | report | Primary product surface |
| 3 | help | Utility |
| 4 | topology | Diagnostic |
| 5 | scaffold | Utility |
| 6 | gate | Gate management |
| 7 | lint | Code analysis |
| 8 | cert | Certificate operations |
| 9 | shadow | Shadow mode |
| 10 | config | Configuration |
| 11 | version | Utility |
| 12 | io | I/O diagnostics |
| 13 | dag | Dependency graph |
| 14 | cache | Cache management |
| 15 | check | Validation |
| 16 | infra | Infrastructure |
| 17 | shape | Shape analysis |
| 18 | git | Git integration |
| 19 | cst | CST parsing |
| 20 | scope | Scope management |
| 21 | release | Release management |
| 22 | observability | Telemetry |
| 23 | check-spec | Spec validation |
| 24 | baseline | Baseline management |
| 25 | invariants | Invariant checking |
| 26 | vkd | VKD lifecycle |
| 27 | verify | Verification utility |
| 28 | budget | Budget management |
| 29 | debt | Debt tracking |

**Total: 29 subcommands** (including `help` which is a built-in alias).

### Phased Adoption

| Phase | Commands | Rationale |
|---|---|---|
| **Phase 3 (this design)** | `prove`, `report` | Primary product surface per `productization_contract.md:23`. These are the only commands with a defined exit-state contract. |
| **Phase 4** | `topology`, `scaffold`, `gate`, `lint`, `cert`, `shadow`, `config`, `version`, `io`, `dag`, `cache`, `check`, `infra`, `shape`, `git`, `cst`, `scope`, `release`, `observability`, `check-spec`, `baseline`, `invariants`, `vkd`, `verify`, `budget`, `debt` | Remaining 26 commands adopt the shared `CliOutcome` mapping. Each command's existing `int` return value is wrapped as `CliOutcome` via the canonical mapping. |
| **Permanent** | `help` | Always exits 0. Trivially maps to `SUCCESS`. |

### Why Prove/Report First

Per `productization_contract.md:23`:

> Documented commands (v1 contract surface): `ax prove`, `ax report` (each with help surface required).

These two commands carry the customer-facing verification promise. Fixing their exit contract first addresses the highest-risk paths:

- `prove`'s scattered `quit(1)` in `wf_runners.nim:35-68` and `action_interpreter_cli.nim:186-193`
- `report`'s `computeReportExitCode` in `report_engine.nim:25-31` (already centralized within the report module, but not connected to the global contract)

Once these two are solid, the remaining commands can adopt the shared mapping mechanically — they follow the same `dispatchCommandAction` → `interpretCliActions` pattern.

---

## Invariants

The following invariants must hold for the R7 CLI Outcome Contract:

### INV-1: No Internal Error Converts to SUCCESS

```
INVARIANT: CliOutcome.INTERNAL_ERROR → exit code 2. Never 0.
```

An internal error indicates unreliability. Returning exit(0) would allow a failing process to masquerade as successful — this is theater (§0.9) and violates R6 (`failureConvertsToSuccess` observation key).

### INV-2: One Exit Point

```
INVARIANT: Exactly one function (`cliOutcomeToExitCode`) maps CliOutcome → process exit code.
```

All `quit()` calls in the CLI layer must route through this function. Direct `quit()` calls for business logic are prohibited. The only permitted direct `quit()` calls are:

- Self-bootstrap rebuild failures in `main.nim:97,109` (these are operational, not verification outcomes)
- Infra bootstrap in `infra_cli.nim:235` (operational, not verification)

### INV-3: JSON and Exit Are Independent

```
INVARIANT: JSON emission status does not determine exit code. Exit code does not determine JSON emission.
```

JSON is emitted based on `emitJson` flag (user request + capability). Exit code is determined by `CliOutcome` (verification result). These are orthogonal dimensions.

### INV-4: Invalid-Input Never Produces Verification Artifacts

```
INVARIANT: CliOutcome.INVALID_INPUT → no JSON, no certificates, no proof state written.
```

If input is invalid, the verification pipeline never starts. No artifacts are produced. This prevents consumers from interpreting stale or partial artifacts as valid results.

### INV-5: Signal Crashes Are Out-of-Contract

```
INVARIANT: No signal → exit-code mapping exists. SIGSEGV, SIGABRT, SIGBUS remain process-crash.
```

Signal handling is explicitly excluded from the contract. Observing a signal crash on a supported path is a Start blocker.

### INV-6: Precedence Is Enforced

```
INVARIANT: When multiple outcomes apply, the highest-precedence outcome wins. No two outcomes coexist.
```

Precedence order: `INTERNAL_ERROR > INVALID_INPUT > VERIFICATION_FAILURE > SUCCESS`.

### INV-7: Mapping Is Bijective Within Valid Range

```
INVARIANT: Each CliOutcome maps to exactly one exit code. Each exit code in {0,1,2,3,4} maps to exactly one CliOutcome.
```

No gaps, no overlaps. Exit codes outside {0,1,2,3,4} are either signal-derived (out-of-contract) or reserved for future expansion.

---

## Appendix A: File:Line Ground Truth Reference

| Claim | Source | Lines |
|---|---|---|
| 29 subcommands in `parseAxSubcommandKind` | `src/cli/action_plan_cli.nim` | 153-214 |
| `CliActionKind` enum with `cliQuit` | `src/cli/cli_types.nim` | 42-48 |
| `CliCommandKind` enum (28 commands) | `src/cli/cli_types.nim` | 50-78 |
| `AxSubcommandKind` enum (29 subcommands) | `src/cli/cli_types.nim` | 79-108 |
| `CliAction` type with `exitCode` field | `src/cli/cli_types.nim` | 118-124 |
| `interpretCliActions` dispatch loop | `src/cli/action_interpreter_cli.nim` | 61-204 |
| ~28 `quit(exitCode)` guards per command | `src/cli/action_interpreter_cli.nim` | 72-204 |
| Engine error `quit(1)` | `src/cli/action_interpreter_cli.nim` | 186-196 |
| Final `quit(0)` fallback | `src/cli/action_interpreter_cli.nim` | 204 |
| Empty args `quit(1)` | `src/cli/action_plan_cli.nim` | 233 |
| Unknown subcommand `quit(1)` | `src/cli/action_plan_cli.nim` | 242 |
| `planAxActions` function | `src/cli/action_plan_cli.nim` | 247-360 |
| `mainLoop` function | `src/cli/action_plan_cli.nim` | 362-374 |
| `runReportCli` proc | `src/cli/report_cli.nim` | 331-540 |
| `computeReportExitCode` definition | `src/verification/report_engine.nim` | 25-31 |
| JSON always emitted (`$stateJson` → `outputJson`) | `src/cli/report_cli.nim` | 480-485 |
| `schemaVersion: axiom.report.v1` constant | `src/core/utils/constants.nim` | (symbol: `axiomReportSchemaVersion`) |
| No signal handler in `main.nim` | `src/cli/main.nim` | 1-142 (confirmed absent) |
| 4-state model documentation | `docs/spec/productization_contract.md` | 246-286 |
| Invalid-input drift (1 vs 3) | `docs/spec/productization_contract.md` | 258 |
| SIGSEGV out-of-contract | `docs/spec/productization_contract.md` | 261 |
| JSON/exit independence | `docs/spec/productization_contract.md` | 278 |
| v1 contract scope (prove/report primary) | `docs/spec/productization_contract.md` | 23, 283-285 |
| R5 CLI contract stability keys | `docs/spec/productization_contract.md` | 82-93 |
| R6 failure semantics | `docs/spec/productization_contract.md` | 95-102 |

## Appendix B: Open Items from Productization Contract

These items from `productization_contract.md` remain OPEN-ITEM and are addressed by this design:

| Item | Current | Target | Owner |
|---|---|---|---|
| Invalid-input exit code | 1 | 3 | This design (R7) |
| Internal-error exit code | 139 (SIGSEGV) | 2 | This design (R7) |
| Centralized exit mapping | Scattered (~34 quit calls) | Single function | This design (R7) |
| Signal shim | None (correct) | None (prohibited) | Constitution §0.9 |
