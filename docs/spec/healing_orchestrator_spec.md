# Healing Orchestrator — Specification

> DEBT#182 — Last updated: 2026-06-05

## Purpose

The Healing Orchestrator coordinates **verification-layer self-healing loops** that iteratively
repair source code and strengthen invariants until verification passes or a deterministic
termination condition is met. It bridges the negative invariant scanner, refactoring engine,
and Lean proof replay into a single coordination layer.

## Module Location

`src/verification/healing_orchestrator.nim`

## Architecture

The orchestrator exposes two independent healing loops:

```
┌──────────────────────────────────────────────────┐
│  runSelfHealingLoop                               │
│  ┌─────────────┐    ┌──────────────────────┐     │
│  │ Negative     │───▶│ Refactoring Template │     │
│  │ Invariant    │    │ Application          │     │
│  │ Scanner      │◀───│ (per vuln kind)      │     │
│  └─────────────┘    └──────────────────────┘     │
│       │ if no fix possible → break                │
│       │ if hasVulnerability → re-scan             │
└──────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────┐
│  runLeanProofRefinementLoop                       │
│  ┌─────────────┐    ┌──────────────────────┐     │
│  │ Lean Spec    │───▶│ Compiler Verification│     │
│  │ Inference    │    │ (lean --verify)      │     │
│  └─────────────┘    └──────────────────────┘     │
│       │                    │                      │
│       │◀─── diagnostics ──┘                       │
│       │    (extract goals, missing hypotheses)    │
│       ▼                                           │
│  strengthenInvariantFromLeanHints()               │
│  applyRefactoringTemplate()                       │
│  re-scan → loop or break                          │
└──────────────────────────────────────────────────┘
```

## Entry Points

### `runSelfHealingLoop(sourceCode, translation, initial, maxRounds, activeInvariant)`

**Contract**: Iteratively applies refactoring templates to fix vulnerabilities detected by
negative invariant scanning.

- **Input**: Source code, universal translation, initial scan, round cap
- **Output**: `(finalSource, finalScan, rounds: seq[HealingRound])`
- **Termination**: `roundsCap = 1` (hard cap), no vulnerabilities, or no applicable fix
- **Purity**: Proc (calls `runNegativeInvariantSearch` and `applyRefactoringTemplate`)

### `runLeanProofRefinementLoop(req, translation, sourceCode, activeInvariant, maxRounds)`

**Contract**: Generates Lean proof spec, verifies with compiler, extracts diagnostics, and
strengthens the invariant based on compiler feedback.

- **Input**: Pipeline request, translation, source, active invariant, round cap
- **Output**: `(finalSource, finalInvariant, rounds, nearestDiagnostic, failedReplayAttempts, leanKernelVerified)`
- **Termination**: `roundsCap = 1`, Lean kernel accepts, loop detected, or no actionable hints
- **Key feature**: State fingerprinting for loop detection — prevents infinite cycles

## Key Types (External)

| Type | Source Module | Role |
|------|--------------|------|
| `HealingRound` | `pipeline_core_types` | Per-round status: round number, phase, fixed kinds, remaining vulns, feedback |
| `NegativeInvariantScan` | `pipeline_core_types` | Scan result: `hasVulnerability`, `hits`, `logicModelConflicted` |
| `UniversalTranslation` | `translator/universal_mapper` | Normalized AST representation |
| `UniversalPipelineRequest` | `universal_pipeline_core` | Verification request parameters |

## Healing Strategies

### Negative Invariant Healing (Loop 1)
For each vulnerability hit:
1. Map `$hit.hit.kind` → refactoring template via `applyRefactoringTemplate()`
2. If template changes source and isn't rejected → accept patch
3. Re-scan to verify fix; repeat up to `roundsCap`

### Lean Proof Refinement (Loop 2)
1. `inferLeanSpec()` generates a Lean theorem from source + invariant
2. Verify with `lean` compiler via `verifyGeneratedLeanSourceWithCompiler()`
3. If `compilerResult.verified` → done, set `leanKernelVerified = true`
4. Extract `goals` and `diagnostics`; infer missing hypotheses
5. Map diagnostic kind → vulnerability kind for template application:
   - `unsolved_goals` → `vkDeadlockRaceCondition`
   - `tactic_failed` → `vkIntegerOverflowUnderflow`
   - `type_mismatch` → `vkNullPointerDereference`
   - `missing_instance` → `vkGhostUpdate`
   - `invalid_projection` → `vkBufferOverflow`
6. Strengthen invariant via `strengthenInvariantFromLeanHints()`
7. Fingerprint current state; if visited → loop guard engaged → break

## Integration Points

| Dependency | Usage |
|-----------|-------|
| `core/refactoring_engine` | `applyRefactoringTemplate()` — source code patching |
| `verification/lean_lsp` | `verifyGeneratedLeanSourceWithCompiler()` — Lean kernel verification |
| `verification/pipeline_negative_scan` | `runNegativeInvariantSearch()` — vulnerability detection |
| `verification/pipeline_lean_spec_inference` | `inferLeanSpec()` — Lean theorem generation |
| `core/logic/lean_diagnostic` | `inferMissingHypotheses()`, `diagnosticKind()` — compiler feedback parsing |
| `core/logic/pipeline_healing_logic` | `healingStateFingerprint()`, `strengthenInvariantFromLeanHints()` — state tracking |
| `core/logic/pipeline_fingerprint_engine` | `computeAsiFixed4()` — ASI score computation |

## Termination Guarantees

Both loops enforce **deterministic termination** via:
1. **Hard round cap**: `roundsCap = 1` (single retry)
2. **Loop detection**: SHA-like state fingerprinting of `(source, invariant)` pairs
3. **No-fix bail**: If no template applies or no hints exist → immediate break
4. **Re-scan convergence**: If source and invariant unchanged between rounds → break

## Known Limitations

- **Single retry cap**: `roundsCap = 1` prioritizes determinism over thoroughness. Complex
  multi-vulnerability code may require multiple healing passes.
- **Diagnostic→vulnerability mapping**: Fixed heuristic mapping from Lean diagnostic kinds to
  vulnerability kinds — may misclassify novel failure modes.
- **Sequential phases**: Negative invariant healing and Lean proof refinement are independent
  loops; no cross-phase feedback (e.g., Lean diagnostics don't feed back into invariant healing).
- **Lean executable**: Resolved via `getEnv("AXIOM_LEAN_CMD", "lean")` — no version validation.
