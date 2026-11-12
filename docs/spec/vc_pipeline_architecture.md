# VC Pipeline Architecture

## Overview

The Verification Condition (VC) Pipeline transforms Nim source code through four phases (Phase 1–4) to produce Lean 4 formal proofs. It connects Nim's AST via bounded model checking (BMC), CEGAR, and LLM-assisted tactic search, ending at the Lean 4 kernel for final verification.

```
  Nim Source
      │
      ▼
  ┌───────────────────────────────────────────────────────┐
  │  Phase 1: BMC Fast-Path (SWAT)                        │
  │  src/verification/pipeline_stage_swat.nim              │
  │  src/core/bmc/                                         │
  │                                                         │
  │  Nim AST → SMT-LIB2 → Z3                               │
  │  If proven → plkL1Bmc (terminal success)               │
  │  If needs more → ssrFallbackRequired                    │
  └───────────────────────┬───────────────────────────────┘
                          │ fallback
                          ▼
  ┌───────────────────────────────────────────────────────┐
  │  Phase 2: CEGAR Loop (Detective + Legislator)          │
  │                                                         │
  │  ┌─────────────────────────┐                            │
  │  │ Step A: Detective       │  src/verification/         │
  │  │ (pipeline_stage_        │  pipeline_stage_detective  │
  │  │  detective.nim)         │  .nim                      │
  │  │                         │  src/core/orchestrator/    │
  │  │ CEGAR counterexample    │  cegar_engine.nim          │
  │  │ analysis + trace report │                            │
  │  └──────────┬──────────────┘                            │
  │             │                                           │
  │             ▼                                           │
  │  ┌─────────────────────────┐                            │
  │  │ Step B: Legislator      │  src/personas/             │
  │  │ (pipeline_stage_        │  legislator.nim            │
  │  │  legislator.nim)        │                            │
  │  │                         │  src/verification/         │
  │  │ LLM-based invariant     │  leanstral_gateway.nim     │
  │  │ drafting (Leanstral)    │                            │
  │  │                         │  src/verification/         │
  │  │ Phase 4 optimization:   │  llm_backend.nim           │
  │  │ CEGAR-proven invariants │                            │
  │  │ skip Legislator         │                            │
  └───────────────────┬───────┘                            │
                      │                                     │
                      ▼                                     │
  ┌───────────────────────────────────────────────────────┐
  │  Phase 3: Scribe + K-Induction Fallback                │
  │  src/verification/pipeline_stage_scribe.nim             │
  │  src/verification/pipeline_stage_k_induction.nim        │
  │                                                         │
  │  Scribe (Leanstral) generates Lean theorem source       │
  │    ↓ if fails                                           │
  │  K-Induction fallback generates Lean proof script       │
  └───────────────────────┬───────────────────────────────┘
                          │
                          ▼
  ┌───────────────────────────────────────────────────────┐
  │  Phase 4: Judge + Kernel Verification                  │
  │                                                         │
  │  ┌─────────────────────────┐                            │
  │  │ Step D: Judge           │  src/verification/         │
  │  │ (pipeline_stage_        │  pipeline_stage_judge.nim  │
  │  │  judge.nim)             │                            │
  │  │                         │  src/core/judge/           │
  │  │ Vacuity check +         │                            │
  │  │ Lean kernel replay      │                            │
  │  └──────────┬──────────────┘                            │
  │             │                                           │
  │             ▼                                           │
  │  ┌─────────────────────────┐                            │
  │  │ Step E: PostProcess     │  src/verification/         │
  │  │ (pipeline_stage_        │  pipeline_stage_           │
  │  │  postprocess.nim)       │  postprocess.nim           │
  │  │                         │                            │
  │  │ Assemble final          │                            │
  │  │ UniversalPipelineResult │                            │
  │  │ + certificate           │                            │
  │  └─────────────────────────┘                            │
  └───────────────────────────────────────────────────────┘
```

## Tactic Search Loop (Fast-Path → LLM → Kernel Verification)

```
  ┌──────────────────┐
  │ BMC Fast-Path    │  ← Phase 1 (SWAT)
  │ (Z3)             │
  └──────┬───────────┘
         │ proven? → plkL1Bmc (terminal)
         │
         ▼
  ┌──────────────────┐
  │ CEGAR Loop       │  ← Phase 2 (Detective + Legislator)
  │ (Z3 + LLM)       │
  │                  │
  │  ┌─────────┐     │
  │  │Detective│     │  CE analysis → trace report
  │  └────┬────┘     │
  │       │          │
  │       ▼          │
  │  ┌─────────┐     │
  │  │Legislatr│     │  LLM invariant drafting (Leanstral)
  │  └─────────┘     │
  │       │          │
  │       ▼          │
  │  ┌─────────┐     │
  │  │ Scribe  │     │  Lean theorem generation
  │  └────┬────┘     │
  └───────┼──────────┘
          │
          ▼
  ┌──────────────────┐
  │ Lean 4 Kernel    │  ← Phase 3-4 (Scribe → Judge)
  │ Verification     │
  │                  │
  │  ┌─────────────┐ │
  │  │runLeanKernel│ │  src/verification/lean_repl_bridge.nim
  │  └──────┬──────┘ │
  │         │        │
  │    ┌────┴────┐   │
  │    │ pass?   │   │
  │    ├─ Yes ──►│   │  plkL3Scribe (terminal)
  │    │ No      │   │
  │    ▼         │   │
  │  ┌──────┐    │   │
  │  │Retry │    │   │  Backtrack with Goal Delta feedback
  │  └──────┘    │   │
  └──────────────┘   │
```

## Multi-tier Fallback Chain

```
  Tier 1: BMC Fast-Path (Z3 SMT-LIB2)
    ├─ Success → plkL1Bmc (verified_by_bmc)
    └─ Fallback → Tier 2

  Tier 2: CEGAR (Detective + Legislator)
    ├─ CEGAR proves with invariants → skip Legislator (Phase 4)
    ├─ CEGAR + Legislator LLM drafting → Tier 3
    └─ Fallback → Tier 3

  Tier 3: Scribe (LLM theorem generation)
    ├─ Success → Judge kernel verification
    ├─ K-Induction fallback → Lean proof script
    └─ Fallback → Tier 4

  Tier 4: Tactic Backtrack (LLM + Lean LSP)
    ├─ Goal-Context Snapshot Protocol
    ├─ Goal Delta computation → structured LLM retry
    ├─ LRU SnapshotStore (in-memory)
    └─ Global reset on explosion/depth/stagnation/budget
```

## Module Inventory

### Phase 1 — BMC Fast-Path (SWAT)

| Module | Responsibility |
|--------|---------------|
| `src/verification/pipeline_stage_swat.nim` | SWAT stage: BMC fast-path dispatch, `UniversalPipelineResult` construction |
| `src/core/bmc/bmc_generic.nim` | Generic BMC engine for bounded model checking |
| `src/core/bmc/bmc_types.nim` | BMC-specific type definitions (TransitionRule, InvariantRule) |
| `src/core/solver/solver_bridge.nim` | Z3 solver bridge (SMT-LIB subprocess) |
| `src/verification/pipeline_stage_k_induction.nim` | K-induction verification path (CHC/Spacer routing) |

### Phase 2 — CEGAR (Detective + Legislator)

| Module | Responsibility |
|--------|---------------|
| `src/verification/pipeline_stage_detective.nim` | Detective stage: CEGAR counterexample analysis, trace report |
| `src/verification/pipeline_stage_legislator.nim` | Legislator stage: LLM invariant drafting wrapper |
| `src/personas/legislator.nim` | LLM-based invariant drafting (`callLeanstral`), type constraints |
| `src/verification/cegar_engine.nim` | CEGAR engine: counterexample-guided abstraction refinement |
| `src/verification/cegar_adapter.nim` | CEGAR ↔ BMC bridge adapter |
| `src/core/orchestrator/cegar_bmc_types.nim` | CEGAR-BMC integration types |
| `src/core/orchestrator/cegar_types.nim` | CEGAR core types (CounterExamplePayload, etc.) |

### Phase 3 — Scribe + K-Induction

| Module | Responsibility |
|--------|---------------|
| `src/verification/pipeline_stage_scribe.nim` | Scribe stage: Lean theorem source generation |
| `src/verification/pipeline_stage_k_induction.nim` | K-induction fallback: CFG classification, CHC/Spacer routing |
| `src/verification/inductive_proof_emitter.nim` | Inductive proof script generation for Lean |
| `src/verification/spacer_chc_router.nim` | CHC/Spacer invariant synthesis routing |

### Phase 4 — Judge + Kernel Verification

| Module | Responsibility |
|--------|---------------|
| `src/verification/pipeline_stage_judge.nim` | Judge stage: final verdict, vacuity check, kernel verification |
| `src/verification/pipeline_stage_postprocess.nim` | Post-process stage: final `UniversalPipelineResult` assembly |
| `src/verification/lean_repl_bridge.nim` | Lean 4 kernel runner (`runLeanKernel`), `ProofStatus` enum |
| `src/verification/tactic_backtrack.nim` | Tactic Backtrack Engine: Goal-Context Snapshot Protocol, Goal Delta |
| `src/core/judge/lean_replay.nim` | Lean replay verification in Judge |
| `src/sieve/trivial_lean_router.nim` | Stage 1.5: refinement-typed IR routing, trivial Lean bypass |

### LLM Layer (Shared across Phase 2–4)

| Module | Responsibility |
|--------|---------------|
| `src/verification/leanstral_gateway.nim` | Leanstral API gateway: caching, prompt construction, result parsing |
| `src/verification/llm_backend.nim` | LLM backend abstraction: HTTP + CLI backends |
| `src/personas/legislator.nim` | LLM-based invariant drafting |
| `src/verification/lean_lsp_tactic.nim` | LSP tactic injection for live Lean interaction |
| `src/verification/lean_repl_bridge.nim` | Tactic injection (`injectTactic`), prompt builder (`buildTacticPrompt`) |
| `src/engine/proof_injector.nim` | Pure string-level tactic injector: `replaceFirst`, `canonicalizeTactic`, `injectTactic` |

### Proof Injector (`src/engine/proof_injector.nim`)

The proof injector performs pure string-level Lean tactic injection without AST parsing or LSP. It is used by the tactic backtrack engine and Lean REPL bridge as a lightweight alternative to LSP-based injection when only a `sorry` placeholder needs to be replaced with a tactic string.

**`replaceFirst(s, sub, by)`:**
Replaces the first occurrence of `sub` in `s` with `by`. Pure function, no side effects.

```nim
assert replaceFirst("a b a", "a", "x") == "x b a"
```

**`canonicalizeTactic(rawTactic)`:**
Strips Markdown code fences (` ```lean ` / ` ``` `), removes leading `by `, and normalizes whitespace. Returns a string always starting with `"by "`. Falls back to `"by simp"` on empty input.

```nim
assert canonicalizeTactic("```lean\nby omega\n```") == "by omega"
assert canonicalizeTactic("by simp") == "by simp"
assert canonicalizeTactic("") == "by simp"
```

**`injectTactic(leanCode, rawTactic)`:**
Replaces `sorry` in `leanCode` with the canonicalized tactic. Handles three patterns in order:
1. `:= by sorry` — inline `:=` with `by` block
2. `:= sorry` — inline `:=` without `by`
3. `:= by\n  ... sorry ...` — multi-line `by` block with indentation preservation

```nim
let code = "theorem add_comm (a b : Nat) : a + b = b + a := by sorry"
let result = injectTactic(code, "omega")
assert result == "theorem add_comm (a b : Nat) : a + b = b + a := by omega"
```

**Usage in pipeline:**
- Called by `src/verification/tactic_backtrack.nim` to inject LLM-generated tactics into Lean theorem stubs during retry cycles
- Called by `src/verification/lean_repl_bridge.nim` as the default `injectTactic` implementation
- Can be used standalone for testing without a running Lean LSP server

### Pipeline Orchestration

| Module | Responsibility |
|--------|---------------|
| `src/verification/universal_pipeline.nim` | Universal Acceptance Pipeline: IoC entry point, FSM runner |
| `src/verification/pipeline_transition.nim` | Pure `Transition[T]` types for defunctionalized stages |
| `src/verification/pipeline_transition_engine.nim` | FSM transition engine: Phase 1–4 routing, CEGAR skip optimization |
| `src/verification/pipeline_phase.nim` | `PipelinePhase` enum + typed constructors for each stage |
| `src/verification/pipeline_state_types.nim` | State types: `DetectedState`, `LegislatedState`, `ScribedState`, `JudgedState` |
| `src/verification/pipeline_effect.nim` | Open-world effect handling (IO, retry, user input) |
| `src/verification/pipeline_core_types.nim` | Core pipeline types, trace normalization, JSON serialization |
| `src/verification/unified_trajectory.nim` | Unified trajectory tracking across pipeline stages |
| `src/verification/unified_trajectory_types.nim` | Trajectory state types |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AXIOM_LLM_CMD` | `kimi` | CLI command for LLM backend (HTTP API or CLI) |
| `AXIOM_LEANSTAL_MODEL` | `labs-leanstral-2603` | Leanstral model identifier |
| `AXIOM_LLM_TIMEOUT_MS` | `30000` | LLM request timeout in milliseconds |
| `AXIOM_STATE_LEDGER_PATH` | — | Path to cross-process state ledger (v27) |
| `AXIOM_HERMETIC_BUILDING` | — | Hermetic build recursion guard (v28) |
| `AXIOM_RECURSION_GUARD` | — | HMAC-signed process-tree bypass token |

## CLI Backend vs HTTP API Backend

### CLI Backend (`AXIOM_LLM_CMD`)

Default mode. Invokes a CLI command (e.g., `kimi`) as a subprocess via `runProcessWithTimeout`. The prompt is piped to stdin; the response is read from stdout. Used by:
- `src/verification/llm_backend.nim` (`httpLLMBackend` → delegates to CLI)
- `src/personas/legislator.nim` (LLM invariant drafting)

### HTTP API Backend

Legacy compatibility shim. Retains `apiUrl`/`apiKey` parameters for backward compatibility but delegates to the same CLI subprocess mechanism. See `src/verification/llm_backend.nim:47`.

## Integration Tests

| Suite | Location | Guard |
|-------|----------|-------|
| VC Pipeline Integration | `tests/integration/test_vc_pipeline.nim` | `findExe("lean")` — skips when Lean 4 unavailable |
| VC Pipeline E2E Convergence | `tests/test_vc_complete.nim` | `findExe("lean")` — skips when Lean 4 unavailable |

Test scenarios cover: tactic injection, prompt building, goal extraction, Lean kernel execution (syntax error, verified, timeout), temp file sandboxing, and 2-round deterministic convergence (`sorry` fixture → inject tactic → verify).

## Pipeline Command → Stage Mapping

```
cmdRequireSwat        → skSwat
cmdRequireDetective   → skCegar
cmdRequireLegislator  → skLegislator
cmdRequireScribe      → skScribe
cmdRequireJudge       → skJudge
cmdRequirePostProcess → skCertificate
cmdPipelineComplete   → skCertificate
```

## Test Fixtures

### `test_custom_reverse_sorry.lean` — Input Fixture (Unproven Stub)

**Location:** `tests/fixtures/test_custom_reverse_sorry.lean`

**Purpose:** Input fixture for the E2E test. Contains the `my_concat_assoc` theorem with a bare `sorry` — simulates a theorem stub fresh from the Scribe stage before any tactic injection.

**Content:**
```lean4
theorem my_concat_assoc {α : Type} (xs ys zs : MyList α) :
    my_concat (my_concat xs ys) zs = my_concat xs (my_concat ys zs) :=
  /- AXIOM_PROOF_BEGIN -/
  sorry
  /- AXIOM_PROOF_END -/
```

Used by `tests/test_vc_complete.nim` as the starting point for the 2-round deterministic convergence test.

### `test_custom_reverse.lean` — Expected Output Fixture (Proved)

**Location:** `tests/fixtures/test_custom_reverse.lean`

**Purpose:** Demonstrates the expected final state of the fixture after successful tactic injection and Lean kernel verification. The `by induction xs with ...` proof block replaces the `sorry`.

**Theorem `my_concat_assoc` (proved):**
```lean4
theorem my_concat_assoc {α : Type} (xs ys zs : MyList α) :
    my_concat (my_concat xs ys) zs = my_concat xs (my_concat ys zs) :=
  by
    induction xs with
    | nil => simp
    | cons h t ih => simp [ih]
```

**3-Round Convergence Scenario (pipeline-level, `test_custom_reverse.lean`):**

| Round | Attempt | Resolution |
|-------|---------|------------|
| 1 | BMC Fast-Path (Z3) | Fails — SMT solver cannot reason about inductive `MyList` without unrolling; fallback to CEGAR |
| 2 | CEGAR + Legislator LLM drafting | Fails — CEGAR counterexample analysis may produce a trace report, but the LLM-drafted invariant (e.g., a `∀ xs, my_concat xs MyList.nil = xs` lemma) may be incomplete or misaligned with the bidirectional induction required |
| 3 | Scribe + Lean kernel verification | Succeeds — LLM generates a working Lean induction proof (e.g., `induction xs; simp [my_concat]`). Judge verifies via `runLeanKernel`, returning `plkL3Scribe` |

This 3-round trajectory exercises the full fallback chain: BMC → CEGAR → Scribe → Judge, making `test_custom_reverse.lean` a representative end-to-end test for the VC Pipeline's error recovery and multi-stage convergence behavior.

## E2E Tests

| Suite | File | Description |
|-------|------|-------------|
| VC Pipeline E2E Integration | `tests/test_vc_complete.nim` | 2-round deterministic convergence test: loads `_sorry` fixture, verifies `psUnsolvedGoals`, injects induction tactic via `injectTactic`, verifies `psVerified` |
| checkLeanOutput unit tests | `tests/integration/test_vc_pipeline.nim:82–99` | 6 scenarios covering sorry detection, error detection, case-insensitivity, empty output, and embedded keywords |

### `checkLeanOutput(output: string): bool`

**Location:** `src/verification/lean_repl_bridge.nim:22`

**Signature:**
```nim
proc checkLeanOutput*(output: string): bool
```

**Logic:**
1. Lowercases the output string.
2. Returns `false` if the output contains `"sorry"` — indicates unsolved goals.
3. Returns `false` if the output contains `"error:"` — indicates a Lean syntax or type error.
4. Returns `true` otherwise (including empty output) — indicates clean verification.

Called by `runLeanKernel` at line 74 to distinguish verified output (`exitCode == 0` + no sorry/error) from unsolved-goals output (`exitCode == 0` but sorry or error present). This prevents false positives where Lean exits zero but contains `sorry` placeholders or non-fatal warnings that indicate incomplete proofs.

### E2E Test: 2-Round Deterministic Convergence (`tests/test_vc_complete.nim`)

This test exercises the tactic injection + kernel verification flow without involving BMC/CEGAR/LLM:

1. **Round 1 (Failing):** Load `test_custom_reverse_sorry.lean` → run `runLeanKernel` → assert `psUnsolvedGoals`. Confirms the bare `sorry` fixture is correctly detected as unproven.
2. **Injection:** Read the fixture content, call `injectTactic()` with an `induction` tactic, write the result to a temp file.
3. **Round 2 (Passing):** Run `runLeanKernel` again → assert `psVerified`. Confirms the injected tactic is syntactically valid and the Lean kernel accepts the proof.

This is a deterministic, LLM-free test that validates the core injection-and-verify round-trip used in the Scribe → Judge handoff.

## References

- `src/verification/pipeline_transition_engine.nim` — FSM transition logic (Phase 4 CEGAR skip at line 103)
- `src/verification/tactic_backtrack.nim` — Goal-Context Snapshot Protocol with Goal Delta
- `src/verification/lean_repl_bridge.nim` — `ProofStatus` enum and `runLeanKernel`
- `src/verification/universal_pipeline.nim` — IoC entry point `runPipelineWithDispatch`
- `docs/agents/architecture.md` — System architecture overview
- `docs/spec/pipeline_overhaul_retirement.md` — Pipeline migration history

## CI Integration (Zero-YAML Bypass)

### Strategy

- No `.github/workflows/` modification required (AGENTS.md §-1 compliant)
- `make test` or `nimble test` → `test_contract_pipeline` + `perf-check` (fail-closed performance gate)
- `check-env` auto-sources `~/.elan/env` for CI containers

### Performance Profiling Architecture

#### `profileBlock` Template

- Location: `src/engine/profiler.nim`
- Compile flag: `-d:axiomProfile`
- Output: `data/benchmarks/perf_latest.json` (untracked execution artifact — gitignored, regenerated per run)

#### Performance Gate

- Profiling (`profileBlock`, `maxMs` parameter) only logs a `[WARN]` line on threshold breach — it never quits.
- Gate enforcement lives in `tools/perf_checker.nim` (fail-closed, schema v2), wired via `make test` → `perf-check`.
- Baseline: `data/benchmarks/perf_baseline.json` — versioned, written only by the explicit `make perf-baseline` target (never automatically).
- Artifact: `data/benchmarks/perf_latest.json` (`schemaVersion`/`environment`/`provenance`/`measurements`) — the latest run's output is an execution artifact, NOT versioned: it is gitignored and regenerated in place by every `make test` → `perf-check` run (a fresh checkout has none until the first run). Only approved baselines are versioned (`perf_baseline.json` / `perf_budget.json`), so baseline updates stay explicit/reviewable (`make perf-baseline` + a real diff) and gate runs never sweep measurement churn into unrelated commits. The gate (`tools/perf_checker.nim`) still fails closed when the latest artifact is absent — a missing latest is an explicit failure, never a silent pass; `tools/ci/check_perf.nim` (budget validator) is fail-open by contract but logs its skip explicitly when the artifact has not been generated yet.
