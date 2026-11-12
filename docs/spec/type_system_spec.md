# Type System — Liquid Inference & Context-Aware Type Inference — Specification

> DEBT#188 — Last updated: 2026-06-05

## Purpose

The type system subsystem provides **automatic refinement type inference** from Nim AST,
enriching raw Nim types with liquid (refinement) predicates. It consists of two cooperating
modules:

1. **Liquid Inference** — Scans function ASTs and assigns `RefinementType` predicates to
   variables (e.g., `x >= 0`, `i < n`).
2. **Context-Aware Type Inferencer (CATI)** — Merges liquid inference results with direct
   parameter lists to produce precise `ParamTypeInfo` for Lean theorem generation.

## Module Map

| File | Responsibility |
|------|---------------|
| `liquid_inference.nim` | Multi-pass AST scanner: collect declarations → widen loop vars → add loop bounds → infer mutations. Produces `InferenceState` with per-variable refinement types. |
| `context_aware_type_inferencer.nim` | **CATI**: bridges liquid inference with parameter lists. Runs `inferLiquidTypeEnv` and merges results into `ParamTypeInfo` entries. |

## Key Types

| Type | Module | Description |
|------|--------|-------------|
| `InferenceState` | `liquid_inference` | `env: LiquidTypeEnv` + `loopVars: seq[string]` + `mutatedVars: seq[string]` |
| `LiquidTypeEnv` | `refinement_types` | `Table[string, RefinementType]` — maps variable names to refinement types |
| `RefinementType` | `refinement_types` | Tagged union: `rtInt(predicate)`, `rtNat()`, `rtUnknown()`. Predicate is `SymSExpr`. |
| `SymSExpr` | `core/types/symbolic_types_expr` | Symbolic S-expression for predicates: `seVar`, `seConst`, `seEq`, `seGe`, `seLt`, `seAnd`, `seTrue`, etc. |
| `ParamTypeInfo` | `core/smart_search` | Parameter name + Nim type string + optional `RefinementType` from liquid inference |

## Inference Pipeline (Liquid Inference)

`inferLiquidTypeEnv(fnNode)` performs **4 sequential passes**:

| Pass | Operation | Result |
|------|-----------|--------|
| Pass 1 | `collectDeclarations` | Scan `var_section`/`let_section` for variable declarations. Constants → `rtInt(v == const)`, non-constants → `rtNat()`. Track `assignment` targets → `mutatedVars`. Track `for`/`while` loop variables → `loopVars`. |
| Pass 2 | Widen loop vars | Loop variables with exact constant (`v == 0`) → widen to `rtNat()` (non-negative). |
| Pass 3 | `addLoopBounds` | Extract upper bounds from loop conditions (`<`, `<=`). Combine with existing predicates via `sAnd`. |
| Pass 4 | Infer mutations | Mutated variables not in loop vars → default `rtNat()`. |

### Loop Bound Extraction

`extractLoopBound(loopNode)` handles two loop forms:

| Form | Extraction |
|------|-----------|
| `for i in 0 ..< n` | `(i, "<", n)` |
| `for i in 0 .. n` | `(i, "<", n)` (via infix_expression parsing) |
| `while x < n` | `(x, "<", n)` (condition node parsing with fallback to child elements) |

## CATI Entry Points

| Function | Description |
|----------|-------------|
| `buildCatiParamTypes(fnNode, directParams) → seq[ParamTypeInfo]` | Run liquid inference, merge refinement types into parameter list |
| `buildCatiParamTypesFromInfo(fnNode, directParams) → seq[ParamTypeInfo]` | Overload for pre-existing `ParamTypeInfo` entries |

## Liquid Inference Query Functions

| Function | Description |
|----------|-------------|
| `getRefinementType(state, varName) → RefinementType` | Look up refinement type for variable |
| `hasRefinementType(state, varName) → bool` | Check if variable has inferred type |
| `envToJson(state) → string` | Serialize environment to JSON |
| `envToInvariantCandidates(state) → seq[SymSExpr]` | Convert liquid predicates to loop invariant candidates |
| `envToLiquidSmtAsserts(state) → seq[string]` | Convert predicates to SMT-LIB2 assertion strings |

## Integration Points

- **`core/refinement_types`** — `RefinementType`, `LiquidTypeEnv` definitions, `rtInt`, `rtNat`, `rtUnknown` constructors
- **`core/types/symbolic_types_expr`** — `SymSExpr` symbolic expression type, `sVar`, `sConst`, `sAnd`, `sEq`, `sLt`, `sLe`, `sExprToString`, `substituteVarInPredicate`
- **`core/smart_search`** — `ParamTypeInfo`, `TranslatorContext` — CATI enriches these for Lean translation
- **`core/parsers/compiler/parser`** — Nim compiler AST navigation helpers for AST traversal
- **`core/safe_parsers`** — `safeParseInt` for exception-free integer parsing
- **`core/solver/types`** — `SymSExpr` shared between type system and solver subsystems
- **`translator/universal_assembler`** — Consumes `ParamTypeInfo` for Lean theorem parameter declarations

## Key Contracts

1. **Effect boundary**: All functions are `func` / `{.push noSideEffect.}`. No I/O, no raises.
2. **AST-driven**: All inference is derived from Nim compiler AST nodes — no heuristic string matching.
3. **Monotonic widening**: Pass 2 never narrows types — `rtInt(v == 0)` can only widen to `rtNat()`, never the reverse.
4. **Deterministic**: Identical AST → identical `InferenceState`. No randomness, no external calls.
5. **Conservative default**: Unrecognized variables default to `rtNat()` (non-negative), never `rtUnknown()` — preferring false positives over missed constraints.

## Known Limitations

- **Integer-only refinement**: `RefinementType` predicates operate on integer variables only. Float, string, and complex types default to `rtUnknown()`.
- **No inter-procedural analysis**: Inference is per-function. Cross-function constraints are not tracked.
- **Single loop bound**: Only the first matching loop bound per variable is used. Re-assignment in nested loops may lose precision.
- **No narrowing for mutations**: Mutated variables always get `rtNat()` even if the mutation constrains to a tighter range.
- **AST format dependency**: Assumes Nim compiler AST node structure. Other AST representations require adapter code.
