# Axiom ACI Refactoring — Residual Heavy Candidates Report
## Generated: 2026-05-15 | ASI: 0.1471 | 7 refactorings completed

---

## Executive Summary

After 7 automated refactorings (all verified by Wave Y Translation Validation certificates), **29 functions** remain at ACI ≥ 70. Of these, **8 are "heavy"** (ACI > 100) and require manual design review. The remaining 21 medium/light candidates (ACI 70–99) have diminishing ROI for automated extraction — their complexity stems from inherent domain logic rather than structural violations.

---

## Heavy Candidate #1: `verifyCertificates`
| Property | Value |
|----------|-------|
| **File** | `src/verification/analyzer.nim` |
| **Lines** | 403 (L595–997) |
| **ACI** | **165** |
| **Violation** | **God Function** — 14 distinct responsibilities |
| **Difficulty** | High |

### Responsibility Breakdown
1. Virtual DB load/sync (L620–628)
2. Symbolic GC mark-and-sweep (L630–677)
3. Certificate loading from disk (L678–689)
4. Hydration loop — incremental verification (L695–730)
5. Cross-module call canonicalization (L731–733)
6. Architecture principles gate (L740–743)
7. Axiom linkage gate (L744–751)
8. Vault index loading (L753–759)
9. Global influence gate (L762)
10. Physical ASI guard (L768–775)
11. Type integrity gate (L788–799)
12. **Symbolic invariant analysis** (L803–960, ~160 lines — complete sub-pipeline)
13. Semantic integrity gate (L962–969)
14. Audit + DB persistence (L972–997)

### Key Issue
The 160-line symbolic invariant analysis block (L803–960) contains: AST parsing with per-file caching, CFG construction, loop header detection, Z3+Lean 4 invariant synthesis, audit event emission, and Lean 4 cross-validation with cache. **This alone is larger than 3 other functions in the violator list combined.**

### Suggested Strategy
1. Extract `runSymbolicInvariantPipeline()` — the 160-line sub-pipeline (L803–960)
2. Extract `loadAndHydrateCertificates()` — certificate loading + hydration
3. Extract `applyGateChain()` — gates 6-13 as a pipeline
4. Extract `emitGateAuditEvents()` — the 4 repeated audit emission blocks (L776, L789, L972, L983)
5. `verifyCertificates` becomes ~60-line orchestrator

---

## Heavy Candidate #2: `extractBoundaries`
| Property | Value |
|----------|-------|
| **File** | `src/core/boundary_extractor.nim` |
| **Lines** | 395 (L611–1004) |
| **ACI** | **129** |
| **Violation** | **God Function** — 20+ concerns, 10 exit paths, nested 41-line `isTrivialConstraint` |
| **Difficulty** | High |

### Responsibility Breakdown
1. NodeId parsing + source loading (L611–639)
2. AST parse attempt (L640–643)
3. ACI-based SOLID gate (L654–672)
4. Wave X conservative guard (L675–689)
5. Function-def extraction from AST (L690–731)
6. Regex fallback path (L732–742)
7. Zero-param tautology generation (L733–746)
8. Var-param impurity detection (L748–760)
9. External I/O impurity detection (L762–779)
10. C FFI detection (L780–784)
11. SMT/Lean constraint generation (L786–849)
12. Opaque-type tautology (L850–865)
13. **Nested `isTrivialConstraint`** (L870–910, 41 lines — prevents reuse)
14. Triviality filtering (L912–931)
15. Large-function gate (L926)
16. All-trivial tautology (L933–970)
17. Information gain computation (L972–979)
18. Hint construction (L980–1004)

### Key Issue
**10 distinct exit paths** scattered across the function. ACI check can return at L671, Wave X guard at L688, function-not-found at L731, zero-param at L746, opaque-type at L865, large-function at L926, all-trivial at L970, and the final hint construction at L1004. This makes the function nearly impossible to test in isolation.

### Suggested Strategy
1. Convert to **Pipeline pattern** — each stage returns `Option[BoundaryExtractionResult]`, chain with `??`
2. Lift `isTrivialConstraint` to module scope (already attempted — automated extraction corrupted file due to deeply nested structure)
3. Unify 3 tautology builders (zero-param L733–746, opaque-type L850–865, all-trivial L933–970) into `buildTautologyHint(kind, params)`
4. Extract `detectImpurityFlags()` — combining var-param + external I/O + FFI

---

## Heavy Candidate #3: `sanitizeLeanSource`
| Property | Value |
|----------|-------|
| **File** | `src/translator/universal_assembler.nim` |
| **Lines** | 178 (L27–204) |
| **ACI** | **117** |
| **Violation** | **SRP** — 20+ sanitization concerns, 60+ magic strings, 4 char-level manual parsers |
| **Difficulty** | High (Unicode risk) |

### Concern Breakdown
1. Header zone `:=` → `:` replacement (char-level loop)
2. Header zone `where` → comment, semicolon expansion
3. Body import capture + dedup
4. Body colon artifact stripping (char-level loop)
5. Bracket artifact removal
6. Type erasure (`Type)`, `Type }`)
7. Nim operator → Lean operator (3 replacements)
8. Special char normalization (`·`→`.`, `λ`→`fun`, `→`→`->`, `=>`→`->`)
9. Reserved word escape (7 words)
10. Quarantine embedded declarations
11. Quarantine duplicate typeclass instances
12. `where` keyword removal
13. Type synonym normalization (`List`→`NimSeq`, `Option`→`NimOption`)
14. Typeclass call erasure
15. Reflexivity injection for incomplete `match`
16. Duplicate prelude removal (5 prefixes)
17. Variable relocation
18. Namespace isolation (3 identifiers)
19. Parenthesis balance enforcement (char-level loop)
20. Trailing semicolon fix
21. Dangling `else` fix
22. Assignment normalization (char-level loop)

### Key Issue
Contains Unicode characters (α, λ, →, ∧, ∨, ∈, ·) in string literals. Python-based automated extraction corrupted these, causing Nim string literal parse errors. The 4 char-level manual parsers (header `:=`, body colon, parenthesis balance, assignment normalization) each use different approaches to the same problem.

### Suggested Strategy
1. **Strategy pattern with replacement table**: `seq[(pattern, replacement, zone)]` — collapses ~40 individual `replace` calls
2. Extract `sanitizeBodyLine(line, capturedImports, seenImports): string`
3. Extract `sanitizeHeaderLine(line): string`
4. Manual refactoring only — automated tools risk Unicode corruption

---

## Heavy Candidate #4: `saveHint`
| Property | Value |
|----------|-------|
| **File** | `src/cli/commands/heal_injection.nim` |
| **ACI** | **112** |
| **Status** | Not yet explored |

---

## Heavy Candidate #5: `assemblePrimitiveProof`
| Property | Value |
|----------|-------|
| **File** | `src/core/smt_to_lean_bridge.nim` |
| **ACI** | **110** |
| **Status** | Not yet explored |

---

## Heavy Candidate #6: `tryLeanstralSelfCorrection`
| Property | Value |
|----------|-------|
| **File** | `src/cli/commands/heal_leanstral.nim` |
| **ACI** | **108** |
| **Status** | Previously modified in Wave X.3 (+50% conservative timeout). Complex Leanstral model interaction logic. |

---

## Heavy Candidate #7: `extractPathConditions`
| Property | Value |
|----------|-------|
| **File** | `src/core/boundary_extractor.nim` |
| **ACI** | **105** |
| **Status** | Not yet explored. Same file as `extractBoundaries` — possible shared patterns. |

---

## Heavy Candidate #8: `analyzeVariableIntervalsAtLoopHeader`
| Property | Value |
|----------|-------|
| **File** | `src/verification/abstract_provider.nim` |
| **ACI** | **103** |
| **Status** | Not yet explored |

---

## Medium/Light Candidates (21 functions, ACI 70–99)

These functions have lower ROI for structural refactoring. Their complexity stems from:
- Inherent domain logic (AST traversal, SMT expression manipulation, Lean type translation)
- Algorithmic complexity (Z3 interaction, CFG construction, liquid type inference)
- Already modular but long (tree-sitter bridge, CLI command handlers)

Recommended action: **accept current complexity** unless specific bugs or feature work requires touching these functions. The cost of refactoring outweighs the benefit at this ACI range.

---

## Completed Refactorings (for cross-reference)

| # | Function | ACI (before) | Strategy | Certificate |
|---|----------|-------------|----------|-------------|
| 1 | `extractContractFromAst` + `extractContractFromNimBodyText` | 167+116 | `addPrecondition` extraction | `tkExtractMethod` |
| 2 | `convertExpressionToSmtLean` | 172 | `InfixOps` table (17→1) | `tkTableDriven` |
| 3 | `runNegativeInvariantSearch` | 162 | 5 vulnerability check helpers | `tkStructuralDecomp` |
| 6 | `extractContractFromNimBodyText` | 116 | 7 rule extraction | `tkStructuralDecomp` |
| 7 | `parseAxProofReportFromJson` | 134 | 5 parse helpers | `tkStructuralDecomp` |
| 8 | `runUAPCliJson` + `runILoopCliJson` | 115+73 | `nextArgOrErr` helper | `tkExtractMethod` |
| 10 | `runRecertifyLeanCli` | 163 | `processEvidenceFile` | `tkExtractMethod` |

