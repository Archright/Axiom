# Verification Personas — Specification

> DEBT#188 — Last updated: 2026-06-05

## Purpose

The personas subsystem implements the **4-layer verification pipeline** through five specialized
agent roles. Each persona owns a distinct verification layer, produces a typed artifact, and
communicates exclusively through the `persona_interface` module — enforcing strict SoC between
the orchestration logic and the verification strategy.

Per AGENTS.md §1.1: Verification Workflow runs as
`SWAT(BMC) → Detective(CEGAR+Z3) → Scribe(Leanstral) → Judge(Lean Kernel)`.

## Module Map

| File | Persona | Layer | Responsibility |
|------|---------|-------|----------------|
| `persona_interface.nim` | — | — | **SSOT**: all artifact types (`DetectiveArtifact`, `JudgeArtifact`, `ScribeArtifact`, `LegislatorArtifact`, `SwatArtifact`), `PersonaKind` enum, layer mapping. Zero infrastructure imports. |
| `swat.nim` | SWAT | L1 BMC | Fast-path BMC on loop-free functions. Bug-found → short-circuit. Proven → short-circuit. Inconclusive → pass to Detective. |
| `detective.nim` | Detective | L2 CEGAR | Abstract interpretation, CEGAR loop, fixed-point engine, unsat core extraction. Two entry points: `openCase` (initial) and `investigate` (post-healing). |
| `scribe.nim` | Scribe | L3 LLM | Leanstral LLM synthesis of Lean 4 theorems. Calls `callLeanstral` → `runLeanReplay` for kernel validation. |
| `legislator.nim` | Legislator | L3 Invariant | LLM-only invariant drafting (per `legislator_llm_only_policy.md`). No static heuristics. |
| `legislator_feedback.nim` | Legislator | L3 Closed-loop | Counterexample-guided invariant revision (CEGIR). Judge rejection → structured prompt → LLM re-drafting. |
| `judge.nim` | Judge | L4 Lean Kernel | Lean 4 kernel proof verification. Self-healing loop, proof refinement, closed-loop feedback to Legislator on rejection. |

## Key Types

| Type | Module | Description |
|------|--------|-------------|
| `PersonaKind` | `persona_interface` | Enum: `pkDetective`, `pkJudge`, `pkLegislator`, `pkScribe`, `pkSwat` |
| `PersonaLayerKind` | `persona_interface` | Layer enum with compile-time bijectivity guard |
| `DetectiveArtifact` | `persona_interface` | CEGAR evidence, unsat core vars, extraction status, trace report |
| `JudgeArtifact` | `persona_interface` | Lean kernel verdict, proof depth, remediation payload, `ProofArtifact` |
| `ScribeArtifact` | `persona_interface` | Lean theorem source, tactic trace, verified flag |
| `LegislatorArtifact` | `persona_interface` | Baseline/active invariant, evolution reasoning |
| `SwatArtifact` | `persona_interface` | BMC result, reproduction path, BDD feature path, POC snippet |
| `CounterExamplePayload` | `persona_interface` | Closed-loop data from Judge → Legislator (node ID, Lean diagnostic, SMT counterexample) |
| `UnsatCoreExtractionStatus` | `persona_interface` | Distinguishes success vs I/O failure vs parse failure for Z3 unsat core |

## Entry Points

| Proc | Persona | Signature |
|------|---------|-----------|
| `executeRaid` | SWAT | `(req, translation, scan, invariant, hit, trace) → Result[SwatArtifact]` |
| `openCase` | Detective | `(req, translation) → Result[DetectiveArtifact]` |
| `investigate` | Detective | `(req, translation, prior, initial, final, invariant, diag, attempts) → Result[DetectiveArtifact]` |
| `synthesizeLeanTheorem` | Scribe | `(req, translation, source, invariant) → Result[ScribeArtifact]` |
| `legislate` | Legislator | `(req, translation, scan, prior, source) → Result[LegislatorArtifact]` |
| `legislateWithFeedback` | Legislator | `(req, translation, scan, prior, source, history) → Result[LegislatorArtifact]` |
| `certify` | Judge | `(req, translation, source, invariant, verdict, maxRounds, ...) → Result[JudgeArtifact]` |

## Integration Points

- **`verification/universal_pipeline_core`** — Orchestrator dispatches personas in layer order
- **`verification/cegar_engine`** — Detective's CEGAR loop implementation
- **`verification/leanstral_gateway`** — Scribe/Legislator's LLM interface (`callLeanstral`)
- **`core/lean_replay`** — Scribe/Judge Lean 4 kernel validation
- **`verification/healing_orchestrator`** — Judge's self-healing loop
- **`core/refactoring_engine`** — Judge's f×g×h refactoring template extraction
- **`core/proof_artifact`** — Judge's SSOT `ProofArtifact` construction

## Key Contracts

1. **Effect boundary**: `persona_interface.nim` is `{.push raises: [].}` + `{.push noSideEffect.}`. Persona entry procs are `proc` (I/O via LLM/solver calls).
2. **Compile-time guard**: `LayerMapping` asserts bijective persona↔layer mapping at compile time.
3. **Closed-loop CEGIR**: Judge rejection → `CounterExamplePayload` → `legislateWithFeedback` → revised invariant → Judge re-verification.
4. **LLM-only mandate**: Legislator uses exclusively `callLeanstral`; static heuristic invariant generation is forbidden (AGENTS.md §0.2a).
5. **Layer boundary**: Each persona communicates artifacts only; no cross-layer function calls.

## Known Limitations

- **CEGAR budget**: Detective's CEGAR loop runs max 20 iterations / 30s wall-clock. Complex invariants may exhaust budget.
- **Single retry**: Judge's closed-loop feedback performs exactly one Legislator retry before accepting the result.
- **Leanstral dependency**: Scribe and Legislator require an active Leanstral LLM endpoint; offline mode returns empty artifacts.
