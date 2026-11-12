# Unsat Core Pipeline Specification

> Data contract for Z3 unsat-core extraction, propagation, and consumption
> across the Detective → Judge → Legislator persona chain.
>
> Version: 0.1.0
> Date: 2026-06-04

---

## 1. Overview

When the CEGAR engine in `detective.nim` encounters a proof obligation that Z3 cannot satisfy, it extracts the **minimal unsatisfiable core** (unsat core) — the smallest subset of assumptions that jointly cause the contradiction. This document specifies how that unsat core is propagated through the pipeline and consumed by downstream personas.

---

## 2. Unsat Core Extraction (Detective Layer)

### 2.1 SMT-LIB Generation

The CEGAR loop must emit SMT-LIB2 with **tracking literals** (assumption variables) so Z3 can identify which candidate invariants contributed to the unsat result.

```smt-lib2
(set-option :produce-unsat-cores true)
(declare-const track_0 Bool)
(declare-const track_1 Bool)
... ; one tracking literal per candidate invariant

(assert (=> track_0 (candidate_invariant_0)))
(assert (=> track_1 (candidate_invariant_1)))
...

(check-sat-assuming (track_0 track_1 ...))
(get-unsat-core)
```

### 2.2 Z3 Output Parsing

`core/solver/z3_result_parser.nim::parseUnsatCore` consumes the raw Z3 stdout and returns `seq[string]` of tracking-literal identifiers.

```nim
func parseUnsatCore*(raw: string): seq[string]
```

**Precondition**: Z3 was invoked with `:produce-unsat-cores true`.
**Postcondition**: Returned identifiers are a subset of the tracking literals passed to `(check-sat-assuming)`.

### 2.3 Mapping to Source Variables

`detective.nim` maps tracking-literal identifiers back to:
- `unsatCoreVars: seq[string]` — variable names referenced in the contradictory invariants
- `cegarSmtlib2: string` — the full SMT-LIB2 query for audit
- `cegarEvidenceLog: string` — human-readable trace

These fields are attached to `DetectiveArtifact`.

---

## 3. Propagation (Batch UAP Orchestrator)

### 3.1 Enrichment

[DEPRECATED] `batch_uap_orchestrator.nim::buildUapRequest` must forward the CEGAR `unsatCoreVars` into the `UniversalPipelineRequest` so the Judge can access them.

```nim
uapReq.unsatCoreVars = cegarOutput.unsatCoreVars
```

### 3.2 JSON Contract

The orchestrator JSON report includes `smtUnsatCoreVars` per node:

```json
{
  "nearestDiscontinuities": [{
    "filePath": "src/api.nim",
    "lineNumber": 42,
    "smtUnsatCoreVars": ["x", "y", "z"],
    "discontinuityKind": "dkMissingInvariant",
    "description": "..."
  }]
}
```

---

## 4. Consumption (Judge & Legislator Layers)

### 4.1 Judge — `MathematicalDiscontinuity`

`judge.nim::parseDiagnosticToDiscontinuities` populates:

```nim
MathematicalDiscontinuity(
  filePath: loc.filePath,
  lineNumber: loc.lineNumber,
  smtUnsatCoreVars: unsatCoreVars,  # ← from DetectiveArtifact
  discontinuityKind: kind,
  description: diagnostic
)
```

### 4.2 Legislator Feedback — CounterExamplePayload

`legislator_feedback.nim::buildFeedbackPrompt` includes the unsat core in the LLM prompt:

```
## SMT Counterexample (Unsat Core)
The following variables were identified as the minimal set causing the contradiction:
- x
- y
- z

## Instructions
Revise the invariant to EXCLUDE states where these variables jointly violate the constraint.
```

### 4.3 Integrity Refinement Loop — Registry Minimisation

`integrity_refinement_loop.nim::minimizeRegistryByUnsatCore` uses the unsat core to prioritise invariants:

- Invariants relevant to the unsat core receive a **+5 priority bonus**.
- Irrelevant invariants may be evicted when the registry is full.

---

## 5. Determinism Guarantees

| Property | Guarantee |
|----------|-----------|
| Unsat core minimality | Z3 guarantees the returned core is minimal **with respect to the current solver state**. Re-running with identical assertions yields an identical core. |
| Tracking literal stability | Tracking literals are assigned deterministically (incremental integer suffix `track_0`, `track_1`, …). |
| Propagation idempotency | Passing the same `DetectiveArtifact` through `buildUapRequest` twice produces bit-identical JSON. |

---

## 6. Future Extensions

- **AST-node-level mapping**: Map each `unsatCoreVar` to its originating AST node via Nim compiler parser for structural diagnosis.
- **Cross-node unsat core union**: When a node depends on another, union their unsat cores to detect shared root causes.
