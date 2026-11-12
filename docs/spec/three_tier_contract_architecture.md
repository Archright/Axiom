# 3-Tier Code-First Contract Architecture

## Overview

Axiom employs a 3-Tier Code-First Contract Architecture for formal verification.
Each tier applies different enforcement strength based on criticality.

## Tier Classification

### Tier 1: SSOT Core (~88 procs)
- **Target**: metrics.nim, certificate_types.nim, verification_tier.nim, proof_hydration.nim
- **Verification**: Layer 1 (Smart Type) + Layer 2 (AST Contract)
- **Enforcement**: Compile-time 100% (compiler blocks illegal states)
- **Smart Types**: ASIRatio, VerifiedKernelRatio, NonNegativeDuration, CertificateStatus

### Tier 2: Pure Mathematical (~3,974 procs)
- **Target**: func/noSideEffect pure functions
- **Verification**: Layer 3 (Z3 SMT AST virtual scanning)
- **Enforcement**: CI gate (UNSAT blocks, UNKNOWN warns)

### Tier 3: IO/Glue/CLI (~3,018 procs)
- **Target**: CLI, Gate, Personas
- **Verification**: Smart Constructor boundary guards
- **Enforcement**: Type system automatic (must pass init*() to enter Tier 1)

## Smart Types Registry

| Spec ID | Type | Module | Constraint |
|---------|------|--------|------------|
| SPEC-T1-ASIRATIO | ASIRatio | asi_types.nim | 0.0 <= val <= 1.0 |
| SPEC-T1-VKDRATIO | VerifiedKernelRatio | vkd_types.nim | 0.0 <= val <= 1.0 |
| SPEC-T1-DURATION | NonNegativeDuration | certificate_types.nim | val >= 0 |
| SPEC-T1-CERTSTATUS | CertificateStatus | certificate_types.nim | enum validated |

## Spec-Code Binding

All Tier 1 Smart Types carry `{.spec("ID").}` pragma. At compile time:

1. Nim macro reads this document via `staticRead`
2. Verifies spec ID exists in the registry table (cell-level matching)
3. Fails compilation if ID is missing (prevents doc-code drift)

Example:
```nim
type
  ASIRatio* {.spec("SPEC-T1-ASIRATIO").} = object
    val: float
```

If `SPEC-T1-ASIRATIO` is missing from the table above, compilation fails with:
```
❌ [COMPILER-SPEC-DRIFT] Spec ID 'SPEC-T1-ASIRATIO' is missing in docs!
   ACTION: Add '| SPEC-T1-ASIRATIO | ... |' to the specification table.
```

## Enforcement

### Compiler-Level (Tier 1)
- Private Field Object pattern prevents casting bypass
- `{.contractProc.}` macro injects pre/post conditions
- `{.spec.}` pragma enforces doc-code sync

### CI-Level (Tier 2)
- `tools/gate_tier_integrity.nim` — T1-NO-RAW + T2-Z3-UNSAT
- `tools/check_imports_ast.nim` — staged-only incremental scan
- Exit code 1 on violation = CI failure

### Git Hooks
- pre-commit: nim check triggers compile-time spec verification (< 0.2s)
- pre-push: gate_tier_integrity with strict-blocking (< 1.5s)

## History
- 2026-07-23: Initial implementation (Compiler-Guided Single-Pass Hardening)
