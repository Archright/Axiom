# Trivial Lean Router Specification

> **Module**: `src/sieve/trivial_lean_router.nim`
> **Tests**: `tests/trusted/test_trivial_lean_router.nim`
> **Version**: Refinement Typed IR v5

---

## 1. Overview

The Trivial Lean Router is a **Type-Level Encoding Sieve** that pre-classifies IR functions suitable for Lean kernel verification via `rfl` (definitional equality).

**Design rationale**: For simple constrained functions, encoding pre/post-conditions as refinement types in Lean allows the kernel to accept the definition directly — no tactics (`bv_decide`, `omega`), no BMC, no Z3. If the Lean kernel type-checks the refined definition, `rfl` verification suffices.

**TCB (Trusted Computing Base)**: AST scanner + Lean kernel only. No external tactics.

**Pipeline**:
```
IRFuncDef → classifyTypeLevel → irToLeanRefinedModule → checkLeanSource (LSP)
                                                         ↓
                                              Lean kernel acceptance?
                                                yes → vpTypeLevelEncoding (done)
                                                no  → fall through to Z3 BMC
```

---

## 2. classifyTypeLevel Filter

```nim
func classifyTypeLevel*(f: IRFuncDef): bool {.raises: [].}
```

Pure, side-effect-free classification function. Returns `true` if the function is eligible for type-level encoding; `false` otherwise.

### 2.1 Input

| Parameter | Type | Description |
|-----------|------|-------------|
| `f` | `IRFuncDef` | Deserialized IR function definition with params, body, pre-conditions, and recursion flag |

### 2.2 Output

`bool` — `true` = eligible for Lean type-level encoding; `false` = defer to Z3 BMC.

### 2.3 Classification Rules

The filter applies four rejection rules in sequence. If **any** rule triggers, the function is classified as `tlComplex` (Z3 BMC).

| # | Rule | Condition | Rationale |
|---|------|-----------|-----------|
| 1 | **No constraints** | `f.preConditions.len == 0` AND no `p.constraint.isSome` for all params | Type-level encoding requires refinement-typed input. Without constraints, there is nothing to encode at the type level. |
| 2 | **Recursive** | `f.isRecursive == true` | Recursive functions require termination proofs that go beyond `rfl`. Lean kernel may not accept the definition without a `decreasing_by` clause. |
| 3 | **irCall** (external call) | Body contains `irCall` node | External function calls introduce opaque dependencies the kernel cannot unfold. |
| 4 | **irLoop** | Body contains `irLoop` node | Loops require unbounded iteration reasoning beyond type-level encoding. |
| 5 | **boMul** (multiplication) | Body contains `irBinOp` with `binOp == boMul` | Nonlinear arithmetic (multiplication) cannot be encoded in refinement types for `BitVec`. |

**Additionally rejected** (via recursive `hasComplexNode` traversal):
- `irRecCall` — recursive self-calls

**Recursion into sub-expressions**: The filter traverses `irLet` bindings, `irIf` branches, and `irCase` branches (including default) to detect complex nodes at any depth.

**Accepted expressions** (leaf nodes): `irLit`, `irVar`, `irBinOp` (except `boMul`), `irUnaryOp`.

### 2.4 Example — Positive

```nim
# Constrained parameter with simple body → passes
let constraint = makeBinOp(boLt, makeVar("x"), makeLit(100))
let f = makeFuncDef("clamp", @[makeConstrainedParam("x", constraint)],
                    makeVar("x"))
classifyTypeLevel(f) == true
```

### 2.5 Examples — Negative

| Scenario | Reason |
|----------|--------|
| No constraints on any param, no pre-conditions | Rule 1 |
| `isRecursive = true` | Rule 2 |
| Body contains `irCall` to external function | Rule 3 |
| Body contains `boMul` | Rule 5 |

---

## 3. routeToTypeLevel Pipeline

```nim
proc routeToTypeLevel*(f: IRFuncDef,
                       lspClient: LeanLspClient): TypeLevelRouterVerdict {.raises: [Exception].}
```

I/O boundary proc that orchestrates the full routing pipeline.

### 3.1 TypeLevelRouterVerdict

```nim
type
  TypeLevelLayer* = enum
    tlTypeLevelEncoding  ## Lean kernel accepted — rfl verification suffices
    tlComplex            ## Rejected — delegate to Z3 BMC

  TypeLevelRouterVerdict* = object
    layer*: TypeLevelLayer
    leanSource*: string    ## Generated Lean source code
    compiled*: bool        ## true if Lean kernel accepted AND axiom set is safe
    axiomsUsed*: seq[string]  ## Axiom names captured from `#print axioms` (P3b)
    error*: string         ## Error message if rejected
```

### 3.2 Pipeline Steps

| Step | Action | Failure Mode |
|------|--------|-------------|
| 1 | `classifyTypeLevel(f)` — pre-processing filter | Returns `tlComplex` immediately (overhead = 0) |
| 2 | `irToLeanRefinedModule(f)` — generate Lean source with refinement-typed parameters | N/A (pure function) |
| 2b | **Sorry gate** — reject `tlComplex` if source contains `sorry`/`sorryAx` (P3b defense-in-depth) | Fail-open: fall through to Z3 |
| 3 | `checkLeanSourceWithAxioms(-, uri, name, source)` — LSP type-check via EOF barrier **+ `#print axioms` round-trip** | Fail-open: any exception → fall through to Z3 |
| 4 | Construct `TypeLevelRouterVerdict` (incl. `axiomsUsed`) | — |

**URI format**: `file:///trivial_router_{f.name}.lean` (ephemeral, virtual file for LSP).

### 3.3 EOF Barrier Protocol

The EOF barrier ensures the Lean LSP server has **fully elaborated** the file before diagnostics are collected:

1. **didOpen** — inject source into LSP workspace
2. **EOF hover** — send `textDocument/hover` request to the **last character of the last line**
3. **Spin-poll** — wait for hover future to complete (up to 500 cycles × 10ms = **5 seconds**)
4. **Collect diagnostics** — drain accumulated `publishDiagnostics` notifications
5. **didClose** — clean up virtual file

The hover request at EOF coordinates acts as a synchronization barrier: the LSP server must elaborate the entire file before responding to the hover request at the end.

---

## 4. LSP Protocol

### 4.1 checkLeanSource

```nim
proc checkLeanSource*(client: LeanLspClient; uri: string; source: string): bool
```

Full LSP interaction cycle for type-checking a Lean source string.

**Returns**: `true` if no diagnostics (verification passed); `false` if any Error or Warning diagnostics present.

**Protocol sequence**:
```
Client                          Lean LSP Server
  │                                  │
  ├─ textDocument/didOpen ──────────►│  (inject source)
  │                                  │  (elaborate file)
  ├─ textDocument/hover (EOF) ──────►│  (sync barrier)
  │◄── hover response ──────────────┤
  │                                  │
  │  (collect pending diagnostics)   │
  │◄── textDocument/publishDiagnostics ┤  (if any errors/warnings)
  │                                  │
  ├─ textDocument/didClose ─────────►│  (cleanup)
  │                                  │
```

### 4.2 getAccumulatedDiagnosticsFor

```nim
proc getAccumulatedDiagnosticsFor*(client: LeanLspClient; uri: string): seq[JsonNode]
```

Drains all pending `publishDiagnostics` notifications from the LSP client message buffer, filtered by:

| Filter | Condition |
|--------|-----------|
| Method | `"textDocument/publishDiagnostics"` |
| URI | Matches the requested `uri` |
| Severity | `<= 2` (Error = 1, Warning = 2) |

**Best-effort**: `pollMessages()` failures are silently caught — diagnostics collection is resilient to channel/lock errors.

**Side effect**: Consumed notifications are removed from `client.notifications`; non-matching notifications are preserved in the buffer.

### 4.3 Timeout Behavior

| Component | Timeout | Behavior |
|-----------|---------|----------|
| Hover spin-poll | 500 cycles × 10ms = **5 seconds** | Failure silently caught; diagnostics still collected |
| pollMessages | No explicit timeout | Best-effort; exceptions swallowed |
| Overall | **~5 seconds** | Fail-open on any error |

### 4.4 Fail-Open Semantics

The entire LSP interaction is wrapped in `try/except CatchableError`. If **any** error occurs (hover timeout, channel failure, protocol error), the router returns `compiled = false` and the function falls through to Z3 BMC. This ensures the type-level encoding path **never blocks** the verification pipeline.

### 4.5 Axiom-Aware Verification Gate (P3b)

**Purpose**: Defense-in-depth against a type-level definition silently depending on `sorryAx` or any axiom outside the approved allowlist. The type-level path is sorry-free by construction (emits only `def` with `(h_pre : Prop)` refinement-typed params), but a hypothetical code-generator regression must not sneak an unsafe axiom past the kernel check.

**Two-layer gate**:

1. **Source-substring gate** (`routeToTypeLevel`, `src/sieve/trivial_lean_router.nim`): before any LSP interaction, reject (`tlComplex`) if the generated Lean source text contains `"sorry"` or `"sorryAx"`. Cheap, deterministic, and runs even when the LSP is unavailable.
2. **LSP `#print axioms` round-trip** (`checkLeanSourceWithAxioms`, `src/verification/lean_lsp_protocol.nim`): after the standard EOF-barrier compile check passes, a fresh virtual doc is opened containing the source plus `#print axioms <defName>`. The same EOF-hover barrier is used to force elaboration, then the Info(3) `publishDiagnostics` notification carrying the axiom report (`'<name>' depends on axioms: [a, b]`) is captured and parsed.

**Axiom validation policy**:

```nim
LeanAxiomAllowlist = {Classical.choice, Quot.sound, propext, funext}
```

`compiled = false` (→ fall through to Z3 BMC) if **any** of the following hold:

| Condition | Meaning |
|-----------|---------|
| Axiom set contains `sorryAx` / `Lean.sorryAx` | Shadow-certificate / hole dependency |
| Axiom set contains an axiom outside `LeanAxiomAllowlist` | Unapproved foundational dependency |
| **No axiom report captured at all** | Uncertainty — cannot confirm sorry-free ⇒ fail-open (NOT-verified) |
| Hover barrier times out / round-trip raises | Protocol failure ⇒ `err` ⇒ router falls through |

**Fail-open safety**: every uncertainty path resolves to NOT-verified, never to a silent PASS. The captured axiom set is surfaced on `TypeLevelRouterVerdict.axiomsUsed` for auditability.

**Verified behavior (Lean 4.29.0 LSP, empirical)**: `#print axioms` output arrives as an **Info(severity 3)** `publishDiagnostics` message, e.g. `'pick' depends on axioms: [Classical.choice]` or `'clamp' does not depend on any axioms`. `by sorry` produces both a severity-2 `declaration uses sorry` warning and `depends on axioms: [sorryAx]`. The existing `getAccumulatedDiagnosticsFor` filters severity ≤ 2, so a dedicated `getAccumulatedAxiomDiagnosticsFor` (which retains Info messages) is required for the round-trip.

---

## 5. Integration with ir_pipeline_runner

### 5.1 Stage 1.5: Type-Level Encoding Fast-Path

The trivial lean router is invoked as **Stage 1.5** in the IR verification pipeline, positioned between IR deserialization (Stage 1) and Z3 BMC (Stages 2–4).

**Source**: `src/verification/batch_uap/ir_pipeline_runner.nim` (lines 81–96)

```
Stage 1:   Deserialize IRFuncDef
Stage 1.5: routeToTypeLevel(funcDef, lspClient)  ← HERE
Stage 2:   IR → SMT (Z3 BMC)
Stage 3:   Z3 check-sat
Stage 4:   Result assembly
```

### 5.2 Provenance Tracking

```nim
type VerificationProvenance* = enum
  vpNone                ## Unverified
  vpZ3Bmc               ## Z3 BMC (check-sat unsat)
  vpTypeLevelEncoding   ## Lean kernel type-level encoding (trivial_lean_router)
  vpDual                ## Both Z3 + Lean passed
```

Functions verified via type-level encoding receive provenance `vpTypeLevelEncoding`.

### 5.3 Integration Code

```nim
# Stage 1.5: Type-Level Encoding Fast-Path
if lspClient != nil:
  try:
    let routerVerdict = routeToTypeLevel(funcDef, lspClient)
    if routerVerdict.compiled:
      return IrPipelineResult(
        funcName: entry.name,
        irDigest: computeIrDigest(funcDef),
        leanSource: routerVerdict.leanSource,
        crossValidation: CrossValidationResult(consistent: true),
        z3Sat: false,
        provenance: vpTypeLevelEncoding,
        success: true
      )
  except CatchableError:
    discard  # LSP failure → fall through to existing pipeline
```

### 5.4 Fail-Open to Z3 BMC

Any error in Stage 1.5 causes an implicit fall-through to Stages 2–4 (Z3 BMC):

| Failure Point | Fallback |
|---------------|----------|
| `lspClient == nil` | Stage 1.5 skipped entirely |
| `classifyTypeLevel` returns `false` | `routeToTypeLevel` returns `tlComplex`; no early return |
| `irToLeanRefinedModule` error | Caught by `except`; fall through |
| Source contains `sorry`/`sorryAx` (P3b gate) | `routeToTypeLevel` returns `tlComplex`; no early return |
| `checkLeanSourceWithAxioms` returns `false` (incl. unsafe/uncertain axiom set) | `routerVerdict.compiled == false`; no early return |
| Any `CatchableError` | Caught by `except`; fall through to Z3 |

**Guarantee**: The type-level encoding path is strictly additive — it can only **short-circuit** verification (early return on success), never **block** it (always falls through on failure).

---

## 6. Dependencies

| Module | Role |
|--------|------|
| `core/trusted/axiom_ir` | `IRFuncDef`, `IRExpr`, `IRFuncParam` types |
| `core/trusted/ir_to_lean` | `irToLeanRefinedModule()` — IR to Lean source generation |
| `core/lean_lsp_types` | `LeanLspClient` type |
| `verification/lean_lsp_protocol` | `checkLeanSourceWithAxioms()`, `checkLeanSource()`, `getAccumulatedAxiomDiagnosticsFor()` |

---

## 7. Test Coverage

| Test Case | Category | Expected |
|-----------|----------|----------|
| Constrained non-recursive simple function | classifyTypeLevel positive | `true` |
| No constraints | classifyTypeLevel negative | `false` |
| Recursive function | classifyTypeLevel negative | `false` |
| External function call (irCall) | classifyTypeLevel negative | `false` |
| Nonlinear operation (boMul) | classifyTypeLevel negative | `false` |
| preConditions without param constraints | classifyTypeLevel positive | `true` |
| irToLeanRefinedModule — constrained param | Lean output | Contains `def`, `(h_x :`, `< 100` |
| irToLeanRefinedModule — preConditions | Lean output | Contains `(h_pre0 :`, `< 100` |
| Constraint serialization roundtrip | Serialization | Preserves constraint and param structure |
| preConditions serialization roundtrip | Serialization | Preserves pre-conditions |
| Backward-compatible deserialization (v4) | Compatibility | Old format deserializes without constraints |

---

## 8. Design Invariants

1. **Zero overhead on rejection**: `classifyTypeLevel` is a pure `func` with no I/O. Complex functions are rejected in O(n) AST traversal with no allocation.
2. **Fail-open everywhere**: LSP errors never block the pipeline. The router is strictly a fast-path optimization.
3. **No tactics in TCB**: Verification relies solely on the Lean kernel's type-checker (definitional equality / `rfl`). No `bv_decide`, `omega`, or custom tactics.
4. **Deterministic classification**: Identical `IRFuncDef` input always produces the same routing decision.
5. **`{.raises: [].}` on filter**: `classifyTypeLevel` is guaranteed exception-free, ensuring it can never introduce runtime failures into the classification path.
