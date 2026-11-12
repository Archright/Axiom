# CFG Contract Specification — Phase 0 Contract Freeze

> **Status**: Active (Phase 0)  
> **Version**: v32  
> **SSOT**: This document  

## Overview

This document defines the 20 contracts (C1–C20) that govern the Axiom CFG, VerificationModel, Canonical CHC,
and Evidence validation pipeline. All implementation phases (P0.3.7–P0.3.11) MUST conform to these contracts.
No code changes precede this document — the contracts are frozen before any implementation begins.

## Design Decision: No Synthetic PC Variable

**Decision**: Program counter (PC) is NOT a state variable in VerificationModel.
CFG NodeId / CHC relation identity represents control location structurally.

**Rationale**:
- PC as state variable inflates SMT formula size (every transition needs `pc = B0 /\ pc' = B1`)
- Invariant includes PC, making EvidenceValidator also verify PC semantics
- Multiple CHC relations (`B0(x)`, `B1(x')`) already encode location via predicate identity

**Exception**: A downstream encoder MAY introduce a synthetic PC if a flattened transition
encoding is required (e.g., single-relation CHC with explicit PC). Such encoder must document
this in its module.

---

## C1 — Deterministic Node Identity

### Rule
Every CFG node has a unique `NodeId` allocated by a **deterministic allocation algorithm**.
`NodeId` alone is not sufficient — the **allocation contract** guarantees determinism.

### Allocation Contract
```
NodeId = sequential uint32 assigned in deterministic traversal order:
  1. Entry node (always 0)
  2. All nodes reachable via BFS from entry, following CFG edge order
  3. Exit node (always last)
```

### Type
```nim
NodeId* = distinct uint32  # Reuse existing type from analyzer/types.nim
```

### Non-Determinism Prohibited
- `HashTable`/`Table` iteration MUST NOT drive NodeId allocation
- `OrderedTable`/`seq` with stable insertion order is permitted
- Same source → same traversal → same NodeId sequence

### Existing Types
- `SorterNodeId* = distinct string` — SSOT for sorter node identifiers
- `NodeId* = distinct uint32` — analyzer dense handle (reuse for CFG)
- `NodeId* = distinct uint32` — symbol interning handle (separate domain)

---

## C2 — Symbol Identity

### Three-Layer Mapping
```
ScopedSymbolId → CanonicalSymbolId → SMTSymbol
```

### Canonical Ordering Key
```nim
CanonicalSymbolOrderKey = (
  ScopePath:        seq[string]    # e.g. ["foo", "bar"]
  DeclarationOrdinal: uint32       # position in source
  SymbolKind:       enum           # variable, parameter, loopIndex, etc.
  OriginalName:     string         # original source name (tie-breaker)
)
```

### Determinism
- Same symbol table → same CanonicalSymbolId sequence
- Canonical SMT names: `s0`, `s1`, `s2`, ... (stable across runs)
- `SymbolTable` already exists in `symbol_table_types.nim` — extend with canonical mapping

---

## C3 — Explicit CFG Topology

### Structure
```
FunctionCFG:
  entry: NodeId          # single entry point
  normalExit: NodeId     # normal return exit
  returnExits: seq[NodeId]  # explicit return edges
  nodes: seq[CFGNode]

CFGNode:
  id: NodeId
  kind: CFGNodeKind
  successors: seq[NodeId]
  predecessors: seq[NodeId]
```

### Loop Canonical Form
```
Header → Condition → Body → Latch → Header
                              ↓
                            Exit
```

### CFGNodeKind
```nim
CFGNodeKind* = enum
  cnkEntry
  cnkExit
  cnkCondition     # if/loop condition
  cnkBlock         # sequential block
  cnkMerge         # phi/join point
  cnkReturn        # return statement
  cnkBreak         # break target
  cnkContinue      # continue target
```

### PC Decision
Control location is represented by CFG NodeId / CHC relation identity.
No synthetic PC variable in VerificationModel.

---

## C4 — Transition Semantics

### Type
```nim
Transition* = object
  source*: NodeId
  target*: NodeId
  guard*: IRExpr         # boolean formula
  update*: ParallelUpdate
```

### Edge Types
- `lkFor`/`lkWhile` → Init/Guard/Transition/BackEdge/Exit (existing)
- `break` → explicit edge from break point to Exit node
- `continue` → explicit edge from continue point to Latch node
- `return` → explicit edge from return point to FunctionExit node

### Semantic Contract
Every transition edge is:
- **Exact**: semantics matches source program exactly
- **OverApproximate**: verified abstraction (e.g., Havoc)
- **Unsupported**: documented in C12

---

## C5 — Parallel State Update

### Type
```nim
ParallelUpdate* = object
  assignments*: seq[Assignment]   # ALL RHS evaluated in pre-state
  havocs*: seq[SymbolId]          # unconstrained post-state

Assignment* = object
  symbol*: SymbolId
  expr*: IRExpr
```

### Simultaneous Semantics
```python
# All RHS evaluated in pre-state, all LHS written simultaneously:
x = y
y = x
# Correct: x' = y, y' = x  (swap, NOT sequential)
```

### Frame Semantics
For every state variable `v`:
- `assigned(v)` → `v' = specified_expr`
- `havoc(v)` → `v'` is unconstrained
- `otherwise` → `v' = v` (frame condition)

### Storage vs Semantics
`seq` preserves storage order for deterministic serialization.
`seq` does NOT imply sequential evaluation order.

---

## C6 — Frame + Havoc Semantics

### Frame Rule
Every transition implicitly asserts:
```
forall v in StateVars:
  if v not in assigned(update) and v not in havocs(update):
    v' = v
```

### Havoc Semantics
- `Havoc(symbol)` = post-state value is unconstrained
- Must be paired with `AbstractionKind` (see C11)
- Over-approximation: safe for reachability verification

### AbstractionKind
```nim
AbstractionKind* = enum
  akExact             # semantics matches source exactly
  akOverApproximation # verified over-approximation (safe)
  akUnsupported       # semantics not modeled (see C12)
```

---

## C5.1 — Golden Transition-Formula Semantics (Testable Contract)

The exact semantics of a transition's post-state, shared by **every** encoder
(CHC, BMC, EvidenceValidator). This is the single operational definition of
`ParallelUpdate`.

**Given pre-state `S` and post-state `S'`, the transition formula is:**
1. Evaluate every RHS against pre-state `S`.
2. Apply all assignments **simultaneously**.
3. Havoc variables are **unconstrained** in `S'`.
4. Every state variable not explicitly assigned/havoc'd is **frame-preserved**: `v' = v`.
5. Update ordering is **not** semantically observable.

**Golden cases (MUST be byte-identical across CHC, BMC, Evidence):**
```
Assignment swap:  x := y ; y := x     ⇒  x' = y  /\  y' = x     (NOT y' = x')
Single assign:    x := e              ⇒  x' = e(x)  /\  forall z != x : z' = z
Frame:            (no x in update)    ⇒  x' = x
Havoc:            havoc x             ⇒  x' unconstrained
Parallel distinct: x := y ; y := z    ⇒  x' = y  /\  y' = z  (both RHS from S)
```
These golden cases are enforced by `tests/unit/test_transition_formula_golden.nim`
and are reused identically by the current encoders (CHC, Evidence) and by BMC
when it is migrated to consume the VerificationModel (PHASE 9).

---

## C7 — VerificationModel Semantics + Immutability

### Type
```nim
VerificationModel* = object
  semantic*: VMSemantic
  metadata*: VMMetadata

VMSemantic* = object
  states*: seq[StateVar]
  initExprs*: seq[IRExpr]
  transitions*: seq[Transition]
  property*: Option[IRExpr]       # NEW: safety property
  exitGuard*: Option[IRExpr]
  obligations*: seq[Obligation]
  loopFacts*: Option[LoopFacts]
  logicalDomain*: LogicalDomain

VMMetadata* = object
  functionExit*: NodeId           # NEW: single-function exit node
  symbolMap*: SymbolTable         # Canonical ↔ Original name mapping
  sourceLocation*: string         # Source file:line
```

### Immutability (HARD RULE)
`VerificationModel` is **immutable after construction**:
- Construction via builder pattern or factory function
- No `var` fields exposed after construction
- All consumers (BMC, CHC, Differential) read from the same immutable model
- Guarantees: deterministic encoding, reproducible verification

### Single-Function Unit
`VerificationModel` represents exactly one function's verification semantics.
Multiple functions → multiple VerificationModel instances.

---

## C8 — Canonicalization + EncodingConfig

### Canonical Invariant
```
CanonicalSerialize(
    Canonicalize(
        VerificationModel,
        EncodingConfig
    )
)
```
Same `VerificationModel` + same `EncodingConfig` → **byte-identical output**.

### CanonicalModel (NOT a copy)
```nim
CanonicalModel* = object
  canonicalSymbols*: seq[CanonicalSymbol]  # deterministic ordering
  canonicalNodes*: seq[CFGNode]            # deterministic ordering
  canonicalRelations*: seq[CHCRelation]    # deterministic ordering
  normalizedFormulas*: seq[Formula]        # normalized expressions
  encodingConfig*: EncodingConfig
```

### EncodingConfig
```nim
EncodingConfig* = object
  loopStrategy*: LoopEncoding
  arithmeticDomain*: ArithmeticDomain
  memoryModel*: MemoryModel
  printCertificate*: bool
```

### Byte-Identical CHC
- `CHC AST` → `SMT-LIB2` serializer is deterministic
- No `Table` iteration in serialization path
- `OrderedTable` or computed `seq` with stable ordering

---

## C9 — Solver Abstraction

### Interface
```nim
SolverAdapter* = concept
  solve(chc: CanonicalCHC) -> SolverOutcome

SolverOutcome* = object
  status*: SolverStatus        # sat / unsat / unknown / timeout / error
  certificate*: CandidateCertificate
  statistics*: SolverStatistics
  diagnostics*: string
```

### SolverStatus
```nim
SolverStatus* = enum
  sosUnsat
  sosSat
  sosUnknown
  sosTimeout
  sosResourceLimit
  sosProcessError
  sosParseError
```

### SolverOutput → SolverOutcome (boundary)
The SolverAdapter is the **sole boundary** between solver output format and verification logic:
- Z3 stdout/stderr format is COMPLETELY hidden inside SolverAdapter
- `(get-model)`, `(get-answer)`, `:print-certificate` → implementation detail
- `print_certificate=true` parameter is set via SolverAdapter, not by caller
- Z3 version changes only affect SolverAdapter, not EvidenceValidator or VerificationResult

### CandidateCertificate
```nim
CandidateCertificate* = object
  predicateInvariants*: OrderedTable[RelationId, Formula]
  # Map: each CHC relation → its inductive invariant formula
  solverMetadata*: string
```

---

## C10 — Evidence Obligations

### Three Obligation Families (NOT 3 Queries)
```nim
EvidenceValidator* = concept
  validate(model: VerificationModel, cert: CandidateCertificate) -> ValidatedEvidence

ValidatedEvidence* = object
  initiations*: seq[ObligationResult]     # PO1 family
  consecutions*: seq[ObligationResult]    # PO2 family
  safety*: seq[ObligationResult]          # PO3 family
  overall*: VerificationResult
```

### Initiation (PO1 family)
For each CFG entry / CHC initial relation:
```
InitRelation(args) ⇒ InvariantRelation(args)
```
Z3 query: `(assert (not (=> Init Inv)))` — expect UNSAT.

### Consecution (PO2 family)
For each transition edge (source → target):
```
Invariant_source(state) ∧ Transition(state, state') ⇒ Invariant_target(state')
```
Z3 query: `(assert (not (=> (and Inv_s Trans) Inv_t)))` — expect UNSAT.

### Safety (PO3 family)
For each exit node / property relation:
```
Invariant_exit(state) ⇒ Property(state)
```
Z3 query: `(assert (not (=> Inv_exit Prop)))` — expect UNSAT.

### Soundness
- `Safe` requires ALL three families to pass
- `Disproved` requires at least one counterexample obligation
- `Inconclusive` requires at least one failed obligation + no counterexample

---

## C11 — Abstraction/Soundness Boundary

### AbstractionKind
```nim
AbstractionKind* = enum
  akExact             # semantics matches source program exactly
  akOverApproximation # sound over-approximation (safe for verification)
  akUnsupported       # semantics not modeled (see C12)
```

### Soundness Gate
`Safe` verdict is valid ONLY if:
```
for every abstraction used in the verification:
  abstraction.kind in {akExact, akOverApproximation}
```

### Existing Related Types
- `BoundaryCompleteness` (`bcComplete`/`bcPartialHavoc`/`bcIncompleteIO`/`bcTrivialDiscard`) — boundary-level
- `VerificationTier` (`vtSmtNative`/`vtStructural`/`vtNonDecidable`/`vtUfAbstract`) — tier-level
- `AbstractionKind` is the **semantic abstraction level** per transition/operation

---

## C12 — Unsupported Semantics Policy

### Classification
Every semantic construct carries one of:
- **Exact** — fully modeled
- **OverApproximate** — sound abstraction (e.g., Havoc for external calls)
- **Unsupported** — cannot be modeled (not a soundness issue, a capability issue)

### Unsupported ≠ Unknown
- `Unsupported` = explicit admission that this construct has no semantic model
- `Unknown` = solver could not decide (temporary)
- `Unsupported` MUST produce `vsInconclusive` with `rkUnsupportedTheory`
- `Unsupported` MUST NOT silently degrade to `Safe`

### Current Unsupported Patterns
| Construct | Current Handling | Target |
|-----------|-----------------|--------|
| Pointer/aliasing | `Havoc` via `bcPartialHavoc` | OverApproximate |
| Exception | Not modeled | Unsupported |
| Closure/dynamic dispatch | Not modeled | Unsupported |
| External I/O | `bcPartialHavoc` + isolation atoms | OverApproximate |
| Float (non-BV) | `rkUnsupportedTheory` | Unsupported |
| String (non-const) | `rkUnsupportedTheory` | Unsupported |

### Enforcement
- Every `Unsupported` classification must be documented in this file
- Adding new `Unsupported` patterns requires updating this contract
- `Unsupported` is NOT a debt item — it is an explicit capability boundary

---

## C13 — Backend Activation / Provenance

### Rule
`VerificationBackend` and `BackendPolicy` are **separate** concepts. The pipeline MUST NOT conflate them into one enum.

### Backend (execution backend)
```
VerificationBackend = CanonicalCHC | Legacy
```
- `CanonicalCHC` — the VerificationModel-derived canonical CHC pipeline (Semantic SSOT → CanonicalModel → CHCAst → Spacer).
- `Legacy` — the pre-VerificationModel CHC encoding (`buildChcTransitionSystem`). **Not** a production default.

### Policy (selection policy)
```
BackendPolicy = RequireCanonical | AllowLegacyFallback
```
- `RequireCanonical` — canonical MUST execute; any canonical failure is a verification failure. **No implicit fallback.**
- `AllowLegacyFallback` — compatibility/debug mode only; fallback is permitted but MUST be provably observable.

### Result provenance (mandatory fields)
```
requestedBackend
selectedBackend
actualBackend
fallbackOccurred : bool
fallbackReason   : string  # empty when fallbackOccurred == false
```

### Enforcement
- `requestedBackend == CanonicalCHC /\ BackendPolicy == RequireCanonical` ⇒ **never** fall back; failing canonical yields a FAIL (not a silent success).
- `fallbackOccurred == true` ⇒ `actualBackend == Legacy` MUST be recorded; the resulting `Safe`/`Proved` provenance must expose `actualBackend`.
- Implicit fallback with an unobservable result is **theater** (§0.9) and is forbidden.

> **See also:** [Verification Result Types — Backend Capability & Execution-Availability](verification_result_types.md). The capability≠executable principle (§0.9) complements C13: C13 governs *which backend actually ran* (provenance), while the capability model governs *which backends are eligible to run* (capability vs. availability). Only backends with `availableToRun = true` may be routing targets.

---

## C14 — Semantic ↔ Encoding ↔ Evidence Identity Preservation

### Rule
Identity is **structural and explicit**, never restored by name-string guessing or by formula equality. Three identity layers are kept separate (no "God Object"):

```
Semantic Identity
  ├── NodeId
  ├── TransitionId
  └── ObligationId

Encoding Identity
  ├── BackendId
  ├── RelationId
  └── StateSignature

Evidence Identity
  ├── CandidateEvidenceId
  └── EvidenceFingerprint
```

Explicit inter-layer mappings (Semantic ↔ Encoding ↔ Evidence) are required; string-sniffing / name-based recovery is forbidden.

### Critical: Identity ≠ Ordering
- `TransitionId    = canonical semantic edge key` = `(sourceNode, guardCanonicalKey, updateCanonicalKey)`
- `TransitionOrdinal` = **serialization order only** (tie-breaker for identical canonical edge keys).
- `TransitionId` and `TransitionOrdinal` MUST NOT be a single fused value. Identity must not be derived from a temporal insertion counter or hash-table iteration order.

### Obligation identity
```
ObligationKey = { family: Initiation|Consecution|Safety,
                   relation: RelationId,
                   transition: Option[TransitionId],
                   stateSignature }
ObligationId = canonical serialization(ObligationKey)   -- digest optional, index only
```
The **structural key is preserved**; a digest is used only for serialization/indexing.

### Enforcement
- `CanonicalRelation` carries `relationId`, `sourceNode`, `targetNode`, `stateSignature` (provenance).
- A `.obiNodeId`-free mapping (relation recovered by parsing a relation-name string) is forbidden.
- The mapping `Semantic Identity ↔ Encoding Identity ↔ Evidence Identity` is deterministic, immutable, and serialized/debuggable.

---

## C15 — Artifact Identity & Provenance

### Rule
Fingerprint is **not** identity. Semantic identity and fingerprint are separate concerns. A fingerprint (M/C/K/E over the canonical serialization) is a **provenance / artifact-integrity attestation** — it attests that a given artifact was produced by a specific canonicalization run — and is **not** a soundness guarantee. The presence of a fingerprint does not imply a correct or logically valid verdict.

### Fingerprint targets (all over **canonical serialization**, never memory layout / hash-iteration)
```
M = canonical VerificationModel
C = canonical CHC artifact
K = candidate certificate
E = validated evidence
```
```
fingerprint(M)  fingerprint(C)  fingerprint(K)  fingerprint(E)
```

### Artifact identity (versioned)
```
ArtifactIdentity = {
  compilerSchemaVersion,
  encodingConfig,
  canonicalModel
}
```
- `CompilerSchemaVersion` (a.k.a. `EncodingSchemaVersion`) MUST be mixed into fingerprint inputs so that a canonicalization-rule change invalidates old fingerprints (no silent collision).
- `EncodingConfig` carries a stable fingerprint/version.

### Certification invariants (provenance is a verification invariant, not a log)
```text
Evidence.modelFingerprint        == CurrentModel.fingerprint
Evidence.chcFingerprint          == CurrentCHC.fingerprint
Evidence.certificateFingerprint  == CandidateCertificate.fingerprint
requestedBackend / actualBackend / fallbackPolicy / fallbackReason (per C13)
```
A `Safe` verdict is sound **only** when backed by a real proof-obligation discharge — the initiation/consecution/safety obligation aggregation (`allPassed`) against a genuinely inducing certificate — never by fingerprint presence alone. The fingerprint confirms the artifact's provenance; the obligation discharge confirms the verdict's logical validity. A well-typed CHC (every HORN rule variable bound via `declare-var`, consistent sorts) is the determinism guard that makes a solver `unsat` a real proof rather than a spurious/mercy `unsat` from an ill-typed script.

### Enforcement
- A `ValidatedEvidence` that cannot tie its model/chc/certificate fingerprints to the current artifacts is rejected.
- Two different relations that happen to share a formula are distinguished by `RelationId`, never by formula content.
- Hash function consistency: all verification fingerprints MUST use the same strong digest (SHA-256); mixed FNV-1a / SHA-256 paths are forbidden.

---

## C16 — Semantics are not decided by the solver

### Rule
The `VerificationModel` is the ONLY semantic SSOT (states, init, transitions, property, abstraction, CFG identity). Solvers (Z3/Spacer etc.) are verification backends providing a proof/evidence *service* over that model; they do NOT define semantics.

### Derivation
Multiple encodings (CHC, BMC, future) derive FROM the VerificationModel via the Semantic Kernel; no encoding redefines semantics.

### Enforcement
- The VerificationModel is the single source of truth for all semantic facts.
- Solver output (SAT/UNSAT/unknown) is evidence about the model, not a definition of it.
- No solver-specific type or predicate may be elevated to a semantic role in the VerificationModel.

---

## C17 — Evidence Validator solver independence

### Rule
`EvidenceValidator` MUST NOT import or otherwise depend on: CHC AST/SMT-LIB serializer, Z3, Spacer, or `SolverAdapter`.

### Dependencies
`EvidenceValidator` SHOULD depend only on: `VerificationModel`, `CandidateEvidence`, and the Semantic Kernel.

### Obligation Discharge
All obligation discharge is delegated to a backend-neutral `ObligationDischarger` abstraction (implementations: Z3, CVC5, Lean, internal checker).

### Enforcement
- `EvidenceValidator` must compile without any solver-specific imports.
- Adding a new solver backend requires only a new `ObligationDischarger` implementation, not a change to `EvidenceValidator`.
- Test: `EvidenceValidator` must be verifiable in isolation with a mock `ObligationDischarger`.

---

## C18 — Candidate Evidence is backend-neutral

### Rule
`CandidateEvidence` is Axiom's neutral evidence type. It has a `source` discriminator: `Solver | Synthesizer | User | Imported`, plus `invariants: Map[RelationId, Formula]`, `provenance`, and `fingerprint`.

### Source Discriminator
| Source | Meaning |
|--------|---------|
| `Solver` | Produced by a solver backend (Z3, CVC5, Lean, etc.) |
| `Synthesizer` | Produced by an invariant synthesis procedure |
| `User` | Provided manually by the user |
| `Imported` | Loaded from an external artifact |

### Inconclusive Semantics
A solver certificate is merely ONE means of producing `CandidateEvidence`. Absence of any candidate evidence → Inconclusive (never Safe).

### Enforcement
- `CandidateEvidence.source` MUST be set for every candidate.
- A `Safe` verdict without any `CandidateEvidence` is theater (§0.9).
- The `CandidateEvidence` type MUST NOT carry solver-specific fields.

---

## C19 — Encoding Identity Separation

### Rule
`RelationId` is an ENCODING identity, not a semantic identity. It is distinct from semantic `NodeId`.

### Three Identity Layers
| Layer | Identifiers | Purpose |
|-------|------------|---------|
| Semantic | `NodeId`, `TransitionId`, `ObligationId` | Semantic graph structure |
| Encoding | `BackendId`, `RelationId`, `StateSignature` | SMT/CHC encoding artifacts |
| Evidence | `CandidateEvidenceId`, `EvidenceFingerprint` | Evidence artifact identity |

### Inter-Layer Mappings
Explicit inter-layer mappings (Semantic ↔ Encoding ↔ Evidence) are required; string-sniffing / name-based recovery is forbidden.

### Enforcement
- No identity from one layer may be used as a substitute for another layer's identity.
- `RelationId` must never be treated as a `NodeId`; the mapping between them is explicit and documented.
- Adding a new encoding backend introduces new `BackendId`/`RelationId` values but does not alter the Semantic layer.

---

## C20 — Safe Gate

### Rule
`Safe` holds IFF: `ValidatedEvidence` exists AND all required obligations are discharged AND the abstraction is sound AND provenance matches.

### Inconclusive Conditions
The following conditions each independently yield `Inconclusive` (never `Safe`):
- Bare solver `UNSAT` alone (without independent `EvidenceValidator` discharge)
- Missing evidence (no `CandidateEvidence` produced)
- Unsupported abstraction (`AbstractionKind = akUnsupported`)
- Provenance mismatch (fingerprint or backend provenance does not match current artifacts)

### Enforcement
- No production path may set `Safe/Proved` from raw solver status without an independent `EvidenceValidator` discharge.
- `Safe` requires passing all three obligation families (C10) with sound abstractions (C11) and matching provenance (C13, C15).
- Any shortcut that bypasses `EvidenceValidator` is theater (§0.9).

---

## Contract Summary

| ID | Name | Key Constraint |
|----|------|---------------|
| C1 | Node Identity | Deterministic allocation, not just type |
| C2 | Symbol Identity | 3-layer mapping + canonical ordering key |
| C3 | CFG Topology | Explicit edges, loop canonical form, no PC variable |
| C4 | Transition | source/target/guard/ParallelUpdate |
| C5 | ParallelUpdate | Simultaneous assignment, frame semantics |
| C6 | Frame/Havoc | Frame rule + AbstractionKind |
| C7 | VerificationModel | Single-function, immutable, semantic/metadata split |
| C8 | Canonicalization | Same model+config → same bytes (artifact determinism) |
| C9 | Solver Abstraction | SolverAdapter boundary, format hidden |
| C10 | Evidence | 3 obligation families, not 3 queries |
| C11 | Abstraction/Soundness | Safe requires all abstractions sound |
| C12 | Unsupported | Explicit classification, Unsupported ≠ Unknown |
| C13 | Backend Activation/Provenance | Backend × Policy separated; no implicit fallback; provenance mandatory |
| C14 | Semantic↔Encoding↔Evidence Identity | Identity ≠ ordering; 3-layer split + explicit mapping |
| C15 | Artifact Identity & Provenance | Fingerprint ≠ identity; versioned canonical fingerprints; certification invariants |
| C16 | Solver Independence | VerificationModel is the sole semantic SSOT; solvers are backends |
| C17 | Evidence Validator Independence | EvidenceValidator depends only on VerificationModel, CandidateEvidence, Semantic Kernel |
| C18 | Candidate Evidence Neutrality | Backend-neutral evidence with source discriminator; absence → Inconclusive |
| C19 | Encoding Identity Separation | Three identity layers (Semantic/Encoding/Evidence) with explicit inter-layer mappings |
| C20 | Safe Gate | Safe requires ValidatedEvidence + all obligations discharged + sound abstraction + provenance match |

## Implementation Order

```
PHASE 0: This document (contract freeze)
PHASE 1: C1–C6 types (NodeId, Transition, ParallelUpdate, CFGNode, AbstractionKind)
P0.3.7:  C3–C4 edges (break/continue/return → explicit transitions)
P0.3.2a: C2, C7 semantic validation (symbol/scope/type/def-use)
P0.3.2b: C3, C4 CFG validation (reachability/terminator/edge targets)
VM:      C7 VerificationModel completion (Property, immutability, metadata)
P0.3.8:  C8 CanonicalModel + CHC AST + serializer
P0.3.9:  C9 SolverAdapter + CandidateCertificate
P0.3.10: C10 EvidenceValidator + C11 soundness gate
P0.3.11: C8 determinism + C9/C10 integration tests (parallel throughout)
```