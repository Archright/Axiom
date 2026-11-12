# Refinement Typed IR Specification (v5)

> **Status**: Implemented (2026-07-02)
> **Source**: `src/core/trusted/axiom_ir.nim`, `src/core/trusted/ir_to_lean.nim`,
> `src/verification/batch_uap/ir_pipeline_runner.nim`, `src/verification/cross_validation.nim`,
> `src/sieve/trivial_lean_router.nim`

---

## 1. Overview

Refinement Typed IR extends the Axiom Core IR with **proof-carrying preconditions**
embedded directly in the function definition. Preconditions travel with the IR through
serialization, pipeline routing, and final verification — eliminating the need to
reconstruct them from source analysis.

The key insight: a function with preconditions `(x > 0)` embedded as IR nodes
can be emitted as a Lean 4 definition with `(h_x : x > 0)` proof parameters.
The Lean kernel then type-checks the definition. If it accepts it, the body is
**definitionally well-typed** — no explicit proof script needed, just `rfl`.

```
Nim AST → Axiom IR (with constraints) → Lean refined def → Lean kernel type-check → rfl
                                    ↘ Z3 BMC fallback (complex functions)
```

### Design Principles

1. **Proof-Carrying Code**: Preconditions are data, not metadata — serialized and
   hashed as part of the IR digest.
2. **Fail-Safe**: Any error in the type-level path triggers fallback to Z3 BMC.
   No property is silently dropped.
3. **TCB Minimization**: The type-level path only trusts the AST scanner
   (`classifyTypeLevel`) and the Lean kernel. Z3 is excluded from this path.

---

## 2. IR Extensions

### 2.1 `IRFuncParam.constraint`

```nim
IRFuncParam* = object
  name*: string
  ty*: IRType
  constraint*: Option[IRExpr]  ## precondition predicate (refinement type)
```

An optional refinement predicate attached to a single parameter. When present,
the Lean backend emits an additional `(h_<name> : <prop>)` proof parameter.
The `Option[IRExpr]` uses Nim's `std/options` — `some(expr)` for constrained
params, `none(IRExpr)` for unconstrained.

**Nim `Option` pattern**: `Option[T]` is a sum type with `Some(val)` / `None` variants.
Pattern matching uses `isSome`/`get` accessors (not case discrimination), which is
the idiomatic Nim approach for option types.

### 2.2 `IRFuncDef.preConditions`

```nim
IRFuncDef* = object
  name*: string
  params*: seq[IRFuncParam]
  retType*: IRType
  body*: IRExpr
  isRecursive*: bool
  preConditions*: seq[IRExpr]  ## function-level preconditions
```

Function-level preconditions — predicates that apply to the function as a whole
(as opposed to parameter-level constraints). Each is emitted as a separate
`(h_preN : <prop>)` proof parameter in the Lean output.

### 2.3 Serialization Format (Backward-Compatible)

**Parameter serialization**: `[name:TYPE|CONSTRAINT,...]`

The `|` delimiter separates the type from the optional constraint. The constraint
is only serialized when `isSome`.

```
# Unconstrained:
[x:BV64,y:BV64]

# Constrained:
[x:BV64|(boGt,V(x:BV64),L(0)),y:BV64|(boLt,V(y:BV64),L(100))]
```

**Function-level serialization**: `,preconds=[expr1,expr2,...]`

Appended after `,rec=true|false` in the canonical `FUNC(...)` format.

```
FUNC(safeDiv([n:BV64|(boGt,V(n:BV64),L(0)),d:BV64|(boGt,V(d:BV64),L(0))]):BV64=
  BIN(boDiv,V(n:BV64),V(d:BV64)),rec=false,preconds=[BIN(boNot,BIN(boEq,V(d:BV64),L(0)))])
```

**Backward compatibility**: Deserialization treats missing `|CONSTRAINT` as
`none(IRExpr)` and missing `preconds` as an empty `seq[IRExpr]`. Old serialized
IR without these fields deserializes without error.

### 2.4 Nim Object Variant Pattern

The `IRExpr` type uses Nim's discriminated union (object variant) pattern:

```nim
IRExpr* {.acyclic.} = ref object
  case kind*: IRExprKind
  of irLit:
    litVal*: int64     ## signed domain [-2^63, 2^63-1] — canonical signed reading
    litU64*: uint64    ## u64 domain [2^63, 2^64-1] (work/u64-add-2026-11-02)
  of irVar:
    varName*: string
    varType*: IRType
  # ... other branches
```

The `kind` field (of enum `IRExprKind`) is the **discriminator**. Accessing a field
not belonging to the active variant branch raises `FieldDefect`. The `{.acyclic.}`
pragma prevents cyclic reference counting overhead — all `IRExpr` trees are acyclic
by construction.

**Literal domain split (v1.2 — `work/u64-add-2026-11-02`).** The `irLit` branch is an
explicit TWO-PART literal representation. `litVal: int64` covers the signed domain
`[−2^63, 2^63−1]` (canonical signed reading); the separate u64-domain field `litU64`
covers `[2^63, 2^64−1]` — a value ≥ 2^63 is held ONLY in `litU64` and is never
reinterpreted into `litVal`. The wire encoding carries the split: the IR binary codec
adds tag `0x0F` = `irLitU64` (8 bytes, little-endian, direct) and invalidates the
legacy `0x01` literal tag whenever the value's high bit would be set (old decoders
fail closed on both the Nim and the Lean sides). The round-trip test matrix —
`−1`, `2^63−1`, `2^63`, `2^64−1` round-trip, `2^64` domain-violation reject — is the
machine check of the invariant. Source of truth: `src/core/trusted/axiom_ir.nim`.

---

## 3. VerificationProvenance

### 3.1 Enum Definition

```nim
VerificationProvenance* = enum
  vpNone              ## Unverified (sentinel)
  vpZ3Bmc             ## Verified by Z3 BMC (check-sat → unsat)
  vpTypeLevelEncoding ## Verified by Lean kernel type-level encoding
  vpDual              ## Verified by both Z3 + Lean (belt-and-suspenders)
```

Tracks which verification backend produced the result. This is an audit-trail
field on `IrPipelineResult`, not used for routing decisions.

### 3.2 `CertificateStatusBits.csbTypeLevelVerified`

The certificate status bitmask includes a dedicated bit for type-level verification:

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | `csbZ3Verified` | Z3 BMC returned unsat |
| 1 | `csbTypeLevelVerified` | Lean kernel accepted refined definition |
| 2 | `csbCrossValidated` | SMT and Lean outputs are structurally consistent |

A function verified via the type-level path gets `csbTypeLevelVerified` set,
even though no explicit Z3 call was made.

### 3.3 `CrossValidationStatus`

```nim
CrossValidationStatus* = enum
  cvsConsistent        ## Both backends produced valid, matching output
  cvsZ3Failed          ## SMT-LIB2 generation failed or empty
  cvsLeanFailed        ## Lean 4 generation failed or empty
  cvsBothFailed        ## Both backends failed
  cvsDiverged          ## Both produced output but structural checks disagree
  cvsTypeLevelSkipped  ## Type-level encoding bypassed the full pipeline
```

When a function is routed through the type-level fast path, cross-validation is
skipped entirely (`cvsTypeLevelSkipped`). This is correct because the Lean kernel
itself is the sole arbiter — there is no second backend to compare against.

---

## 4. Pipeline Integration

### 4.1 Stage 1.5: classifyTypeLevel → routeToTypeLevel

Inserted between Stage 1 (IR deserialization) and Stage 2 (SMT generation) in
`ir_pipeline_runner.nim`:

```
Stage 1:    Deserialize IR (deserializeIRFuncDef)
Stage 1.5:  classifyTypeLevel → routeToTypeLevel  ← NEW
Stage 2:    Generate SMT-LIB2 (irToSmtScript)
Stage 3:    Generate Lean 4 (irToLeanModule)
Stage 4:    Cross-validate + Z3 check-sat
```

**`classifyTypeLevel(f: IRFuncDef): bool`** — Pure pre-processing filter.
Returns `true` only when ALL of:

1. The function has at least one constraint (parameter-level or function-level).
2. The function is **not recursive** (`f.isRecursive == false`).
3. The body contains **no complex nodes**: no `irCall`, `irRecCall`, `irLoop`,
   and no `boMul` operations. (Simple arithmetic, comparisons, if/then/else,
   let-bindings, case matches, and boolean operations are permitted.)

**`routeToTypeLevel(f, lspClient): TypeLevelRouterVerdict`** — Full routing:

1. Pre-filter via `classifyTypeLevel`.
2. Generate refined Lean source via `irToLeanRefinedModule(f)`.
3. Submit to Lean 4 LSP for type-checking.
4. Return verdict: `compiled: true` → type-level path succeeds.

### 4.2 Lean Code Generation: `irToLeanRefinedModule`

The fast-path Lean code generator (`ir_to_lean.nim` §2) transforms preconditions
into proof parameters:

```nim
# Parameter-level constraint → (h_<name> : Prop)
refinedParamToLean(p):
  "(" & p.name & " : " & irTypeToLean(p.ty) & ")"
  # If constrained, appends:
  " (h_" & p.name & " : " & refinedExprToProp(p.constraint.get) & ")"

# Function-level precondition → (h_preN : Prop)
refinedPrecondToLean(pc, idx):
  "(h_pre" & $idx & " : " & refinedExprToProp(pc) & ")"
```

**`refinedExprToProp(e: IRExpr): string`** — Converts IR expressions to Lean
Prop syntax. Key operator mappings (IR → Lean Prop):

| IR Operator | Lean Prop |
|-------------|-----------|
| `boLt` | `<` |
| `boLtU` | `BitVec.ult` (무부호 — u64 도메인 전제 하; `rust_certified_subset.md` §4 boLtU 노트) |
| `boLe` | `≤` |
| `boEq` | `=` |
| `boAnd` | `∧` |
| `boOr` | `∨` |
| `uoNot` | `¬` |

**Example**:

```nim
# IR: func safeDiv(x: BV64 | x > 0, d: BV64 | d ≠ 0) : BV64
# Lean output:
# def safeDiv (x : BitVec 64) (d : BitVec 64)
#   (h_x : (x > 0)) (h_d : ¬(d = 0)) : BitVec 64 :=
#   (x /ₛ d)
```

### 4.3 Fail-Safe Behavior

The type-level path is **fail-open to Z3 BMC**. Any error triggers fallback:

```nim
# ir_pipeline_runner.nim — Stage 1.5
if lspClient != nil:
  try:
    let routerVerdict = routeToTypeLevel(funcDef, lspClient)
    if routerVerdict.compiled:
      return IrPipelineResult(..., provenance: vpTypeLevelEncoding, success: true)
  except Exception:
    discard  # LSP failure → fall through to standard pipeline
```

If the Lean kernel **rejects** the refined definition (`compiled: false`), the
router returns `tlComplex` and execution continues to the standard Z3+SMT path.
If the LSP client is unavailable (`nil`), Stage 1.5 is skipped entirely.

Failure modes that all fall through to Z3 BMC:

| Failure | Response |
|---------|----------|
| No LSP client | Skip Stage 1.5 |
| `classifyTypeLevel` returns false | Skip Stage 1.5 |
| Lean kernel rejects refined def | Fall through to Stage 2-4 |
| LSP communication exception | Fall through to Stage 2-4 |
| Z3 binary missing | Fail-safe: reject (`success: false`) |
| Z3 timeout (>30s) | Fail-safe: reject |

---

## 5. Trust Model

### 5.1 Trusted Computing Base (TCB)

The type-level path minimizes the TCB to exactly two components:

| Component | Role | TCB Boundary |
|-----------|------|-------------|
| **AST Scanner** (`classifyTypeLevel`) | Filters functions eligible for type-level encoding | Pure `func`, no I/O |
| **Lean Kernel** | Type-checks the refined definition | External trusted prover |

**Z3 is explicitly excluded** from the type-level path. No SMT-LIB2 script is
generated or checked. The entire verification is: "Lean kernel accepted this
definition → it is well-typed → body is definitionally correct → `rfl` suffices."

### 5.2 Why Z3 Is Excluded

The type-level encoding is strictly stronger than Z3 BMC for the functions it covers:

- **Lean kernel** reasons about dependent types and Prop-level obligations.
- **Z3 BMC** only checks satisfiability of a bounded model.
- A function that passes type-level encoding has a **type-theoretic guarantee**,
  not just an empirical one.

Functions too complex for the type-level path (recursion, calls, multiplication)
still fall back to Z3 BMC — the two paths are complementary, not competitive.

### 5.3 Property Preservation

| Property | Z3 BMC Path | Type-Level Path |
|----------|------------|----------------|
| Race condition freedom | ✓ (bounded check) | ✓ (if in Prop encoding) |
| Memory safety | ✓ (bounded check) | ✓ (if in Prop encoding) |
| Logic correctness | ✓ (check-sat) | ✓ (kernel type-check) |
| Termination | ✗ (needs manual proof) | ✗ (non-recursive only) |

### 5.4 Deterministic Root Resolution

All IR paths resolve through `.axiom_root` for workspace anchoring. The refined
IR inherits the same deterministic resolution as the base IR — no additional
trust assumptions are introduced.

---

## Appendix A: Complete Pipeline State Machine

```
                    ┌─────────────────────┐
                    │ Stage 1: Deserialize │
                    │ (deserializeIRFunc)  │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │ Stage 1.5: Route    │
                    │ classifyTypeLevel?  │
                    └────┬───────────┬────┘
                  Yes    │           │  No / error
                ┌────────▼──┐   ┌───▼─────────────┐
                │Refined Lean│   │ Stage 2: SMT    │
                │LSP check   │   │ (irToSmtScript) │
                └──┬─────┬──┘   └────────┬────────┘
              Pass │     │ Fail           │
          ┌────────▼┐ ┌─▼───────────┐ ┌──▼────────────┐
          │ vpType- │ │ Stage 2-4:  │ │ Stage 3: Lean │
          │ Level   │ │ Standard    │ │ (irToLeanMod) │
          │ success │ │ pipeline    │ └──────┬────────┘
          └─────────┘ └─────────────┘        │
                                      ┌──────▼────────┐
                                      │ Stage 4: CV + │
                                      │ Z3 check-sat  │
                                      └───────────────┘
```

## Appendix B: Source File Reference

| File | Role |
|------|------|
| `src/core/trusted/axiom_ir.nim` | `IRFuncParam.constraint`, `IRFuncDef.preConditions`, serialization/deserialization |
| `src/core/trusted/ir_to_lean.nim` | `refinedExprToProp`, `refinedParamToLean`, `irToLeanRefinedModule` (§2 fast path) |
| `src/sieve/trivial_lean_router.nim` | `classifyTypeLevel`, `routeToTypeLevel`, `TypeLevelLayer` enum |
| `src/verification/batch_uap/ir_pipeline_runner.nim` | `VerificationProvenance`, Stage 1.5 integration, fail-safe fallback |
| `src/verification/cross_validation.nim` | `CrossValidationStatus.cvsTypeLevelSkipped`, structural consistency |
