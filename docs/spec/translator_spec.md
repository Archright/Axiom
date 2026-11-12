# Translator — SMT-LIB ↔ Lean Translation — Specification

> DEBT#188 — Last updated: 2026-06-05

## Purpose

The translator subsystem converts between Nim AST representations, SMT-LIB2 encodings, and
Lean 4 theorem source. It consists of two major components:

1. **Universal Mapper** — JSON AST → `UniversalTranslation` (language-neutral intermediate representation)
2. **Universal Assembler** — `TranslatorContext` / `SemanticHint` → Lean 4 source with strict zone ordering

This is the bridge between the frontend (source parsing) and the verification pipeline
(SMT solving + Lean kernel proof).

## Module Map

| File | Responsibility |
|------|---------------|
| `universal_mapper.nim` | Entry point — includes the two sub-modules below. Exports `UniversalTranslation` types. |
| `universal_mapper_parts/universal_mapper_part1.nim` | JSON AST parsing: `normalizeLanguage`, `sanitizeSymbol`, JSON field extraction helpers (`jsonString`, `jsonInt`). |
| `universal_mapper_parts/universal_mapper_part2.nim` | Translation assembly: variable/control-flow/function extraction from AST JSON into `UniversalTranslation`. |
| `universal_assembler.nim` | **ULA** (Universal Lean Assembler): sanitizes, normalizes, and assembles Lean 4 source from multiple inputs. Zone-based assembly. |

## Key Types

| Type | Module | Description |
|------|--------|-------------|
| `UniversalTranslation` | `core/logic/universal_translation_types` | Language-neutral IR: variables, control flow nodes, function metadata |
| `TranslatorContext` | `core/smart_search` | Context for function definition → Lean translation (param types, propositions) |
| `SemanticHint` | `core/smart_search` | Strategy hint for Lean proof generation (interval abstraction, tautology, etc.) |
| `ParamTypeInfo` | `core/smart_search` | Parameter name + Nim type + optional `RefinementType` from liquid inference |
| `LeanReplacementRule` | `universal_assembler` | Tuple `(needle, replacement)` for deterministic string-level Lean source normalization |
| `SemanticStrategy` | `core/smart_search` | Enum: `isIntervalAbstraction`, `isTautologyProof`, etc. |

## Universal Assembler — Zone Architecture

The assembler generates Lean 4 source with **strict zone ordering**:

| Zone | Content | Source |
|------|---------|--------|
| Zone 1 | Static imports (`import Std`) | `buildLeanPrelude()` |
| Zone 2 | Dynamic imports (captured from Leanstral output) | `sanitizeLeanSource` extraction |
| Zone 3 | Axiom prelude + variable declarations | `getExtendedAxiomPrelude()` + `buildLeanVarDecls()` |
| Zone 4 | Theorem declaration + proof body | `buildLeanTheoremDecl()` + `buildLeanProofBody()` |

Assembly: `assembleZones(staticImports, dynamicImports, axiomPrelude, varDecls, theoremDecl, proofBody)`.

## Entry Points

| Function | Module | Description |
|----------|--------|-------------|
| `mapUniversalTranslation(node, lang)` | `universal_mapper` | JSON AST → `UniversalTranslation` |
| `sanitizeLeanSource(source) → (string, seq[string])` | `universal_assembler` | Clean Lean source + capture stray imports for zone relocation |
| `buildUniversalLeanSource(ctx) → string` | `universal_assembler` | `TranslatorContext` → complete Lean 4 source |
| `buildUniversalLeanSource(nodeId, hint, smtlib2) → string` | `universal_assembler` | `SemanticHint` → complete Lean 4 source |
| `assembleZones(...)` | `universal_assembler` | Low-level zone assembly |
| `buildLeanTheoremDecl(name, params, prop, sig)` | `universal_assembler` | Generate `theorem <name> ... := by` declaration |
| `buildLeanProofBody(smtlib2, hint)` | `universal_assembler` | Generate proof body from SMT-LIB2 + semantic hint |
| `buildLeanPrelude()` | `universal_assembler` | Standard `import Std` header |

## Sanitization Rules

`sanitizeLeanSource` applies **17 rule sets** in deterministic order across three zones:

- **Header** (3 rules): `:=` → `:`, strip `where`, normalize `;`
- **Body** (10 rules): Type/bracket cleanup, operators (`%`→`mod`), special chars (`λ`→`fun`), reserved word prefixing, type synonyms (`List`→`NimSeq`), typeclass/namespace normalization
- **Structural** (4 rules): Parenthesis balance, prelude dedup, declaration quarantine, dangling `else` repair, `=`→`:=` normalization

## Integration Points

- **`core/axiom_ir`** — `AxiomIrNode` from frontend framework
- **`core/smart_search`** — `TranslatorContext`, `SemanticHint`, `ParamTypeInfo`
- **`core/smt_to_lean_bridge`** — SMT-LIB2 → Lean conversion helpers
- **`core/the_judge_lean`** — Lean proof assembly (`assemblePrimitiveProof`)
- **`core/the_judge_query`** — Query construction for Lean verification
- **`core/axiom_prelude`** — Extended axiom prelude for generated Lean files
- **`core/tautology_prover`** — Tautology proof generation
- **`verification/ast_to_lean_bridge`** — AST → Lean bridge functions

## Key Contracts

1. **Effect boundary**: All assembler functions are `func` / `{.push noSideEffect.}`. No I/O.
2. **Deterministic**: Identical input → identical Lean output. No randomness, no timestamps.
3. **Zone ordering**: `assembleZones` always produces Zone 1→2→3→4 ordering.
4. **Idempotent sanitization**: Re-applying `sanitizeLeanSource` to already-cleaned output is safe.
5. **Import capture**: Stray imports in the body are captured and relocated to Zone 2.

## Known Limitations

- **String-based normalization**: Lean source is cleaned via string replacement rules, not AST transformation. Edge cases with nested expressions may produce imperfect output.
- **Nim-centric type mapping**: `translateNimTypeToLean` handles only Nim primitives. Complex types require manual mapping.
- **Prelude collision**: Namespace prefixing (`ax_` prefix) is a heuristic, not a comprehensive solution for all Lean name collisions.
