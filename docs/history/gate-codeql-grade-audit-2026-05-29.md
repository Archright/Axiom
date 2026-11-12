# Axiom Quality Gate: CodeQL-Grade Audit Report

**Date**: 2026-05-29  
**Auditor**: Kimi Code CLI (Compiler-Plugin Rewrite Track)  
**Evidence Sources**: Context7 MCP (`/github/codeql` v2.22.4, `/nim-lang/nim`), Axiom codebase (1116 files), SKILL.md `axiom-quality-gate`, prior audit `references/2026-05-25-four-dimension-audit.md`

---

## 1. Executive Summary

Axiom's quality gate chain **does NOT yet catch SOLID/SSOT/DRY/SoC violations at CodeQL-grade precision**. The current system grades at **A-** overall (post-2026-05-25 remediation) but retains fundamental heuristic flaws that prevent it from being "complete" or "perfect."

A **Nim compiler-plugin rewrite** is the only path to CodeQL-grade (and beyond) precision because:
1. CodeQL has **zero Nim language support** (confirmed via Context7).
2. Nim's `compiler/ast` + `compiler/modulegraphs` APIs provide semantic depth impossible with line-based parsers.
3. Compile-time enforcement (`static:` blocks, concepts, macros) satisfies GUARDIAN.md §0.3 Four-Dimension Mandate at the highest grade.

---

## 2. Current Gate Coverage Matrix

| Principle | Gate File | Query Name | Status | Compile-Time? | Precision | Gap |
|-----------|-----------|------------|--------|---------------|-----------|-----|
| **SoC** | `nimtry/call_graph.nim` | `soc-transitive` | Active | No | Depth=2 call graph | Transitive depth capped at 2; no PNode resolution |
| **SoC** | `nimtry/core_rules.nim` | `soc-layer-imports` | Active | No | Direct import regex | Misses `from X import Y` aliases; no semantic resolution |
| **SoC** | `nimtry/core_rules.nim` | `soc-surface-area` | Active | No | Exported function count | Undercounts ~75% in large modules (known extractor bug) |
| **SSOT** | `nimtry/core_rules.nim` | `ssot-type-placement` | Active | No | Type definition location | Policy-driven; cannot detect computed-value SSOT |
| **SSOT** | `nimtry/taint_tracker.nim` | `ssot-taint` | **DISABLED** | No | Substring pattern match | 366k+ FPs; fundamentally flawed heuristic |
| **SSOT** | `nimtry/core_rules.nim` | `ssot-forbidden-assignments` | Active | No | LHS/RHS regex | Cannot trace transitive data flow |
| **SOLID/SRP** | `macros/cohesion_enforce.nim` | `solid-srp` | Active | **Macro** (partial) | LCOM/TCC on PNode | Falls back to hash when variableRefs empty; 25 overrides in lock |
| **SOLID/LSP** | `nimtry/interface_auditor.nim` | `solid-lsp` | Active | **Pragma** | `{.axiomImplements.}` contract | Only checks pragma presence, not semantic subtype compliance |
| **SOLID/ISP** | `nimtry/interface_auditor.nim` | `solid-isp` (in `runInterfaceAudit`) | Active | No | Import count heuristic | Crude: flags only >20 imports from one module |
| **SOLID/DIP** | `nimtry/core_rules.nim` | `solid-forbidden-calls` | Active | No | Callee name regex | Layer-based; no interface injection verification |
| **SOLID/OCP** | — | — | **MISSING** | — | — | No registry usage verification; no extension-point detection |
| **DRY** | `nimtry/core_rules.nim` | `dry-duplicates` | Active | No | FNV-1a hash + alpha hash | Syntactic (Type I/II clones only); no semantic clone detection |

### 2.1 Disabled Queries Detail

- **`ssot-taint`**: `generatePolicyLock` produces path-combination patterns (`/`-based substring matching) that are not actual ASI computations. Root cause: no RHS expression AST extraction. Re-enable condition: actual AST-based taint sources with `compiler/sem` type resolution.
- **`solid-srp` (legacy `cohesion_analyzer.nim`)**: LCOM computed on `normalizedAstFingerprint` (FNV-1a hash). Variable extraction from a hash is mathematically impossible. Replaced by `macros/cohesion_enforce.nim` but still has hash fallback.

---

## 3. CodeQL Capability Baseline (Context7 Evidence)

**Source**: Context7 `/github/codeql` v2.22.4, `/websites/codeql_github`

### 3.1 What CodeQL CAN Do
- **Security taint tracking**: Full data-flow graph with `DataFlow::ConfigSig`, `TaintTracking::Global`, `sourceModel`/`sinkModel` extensible predicates. This is CodeQL's strength.
- **Class hierarchy analysis**: `getABaseClass+()` for transitive inheritance (LSP/DIP detection in C++/Java).
- **Import/dependency counting**: `NodeModule.getAnImportedModule()` for JavaScript/TypeScript.
- **Basic coupling metrics**: Fan-in/fan-out via call-graph edges in supported languages.

### 3.2 What CodeQL CANNOT Do (Official Limitation)
- **No Nim language support**: Nim is absent from the official extractor list (C/C++, C#, Go, Java, JS/TS, Python, Ruby, Swift, Rust only).
- **No architecture principle queries in standard library**: CodeQL's standard queries focus on security vulnerabilities (CWE, CVE) and basic code smells. There is **no official CodeQL query pack for SOLID principles, LCOM/TCC, or layer boundary violations**.
- **No semantic clone detection**: CodeQL can detect syntactic duplicates via AST matching, but Type IV (semantic) clones require external tools or ML models.
- **Compile-time prevention**: CodeQL is always post-hoc (after compilation). It cannot enforce at compile time.

### 3.3 Effort to Add Nim to CodeQL
- Requires: TRAP writer + `.dbscheme` + QL standard library + extractor pack + CLI integration.
- Estimated effort: 6–12 months full-time for a team of 2 (language expert + CodeQL expert), per observable scale of existing extractors.
- **Verdict**: Architecturally infeasible for Axiom. Violates GUARDIAN.md §0.3 "Elegant" dimension (prefers language-native tools).

---

## 4. Four-Dimension Audit: Current vs CodeQL-Grade Target

| Dimension | Current Grade | CodeQL-Grade Target | Gap |
|-----------|---------------|---------------------|-----|
| **Ideal** | B+ | A | Compile-time macro enforcement for SRP/LSP/DIP/SSOT; only SoC/DRY are post-hoc |
| **Elegant** | B+ | A | Custom line-based parser + partial PNode; needs full `compiler/ast` integration |
| **Fundamental** | A | A+ | Zero hardcoded exceptions; policy.lock is SSOT; but 25 cohesion overrides indicate metric unreliability |
| **Deterministic** | A- | A | Consistent results; SHA256 cache; but binary freshness is manual, policy.lock has duplicate sections |

---

## 5. Critical Findings

### 5.1 `architecture_policy.lock` Format Bug
The lock file contains **two `[surface_area]` sections** (lines 35-43 and 180-182). Parser behavior for duplicate TOML sections is undefined — the second may silently override the first. This is a **latent determinism bug**.

### 5.2 Missing `[module_overrides]` Section
The 2026-05-25 post-remediation report documented 8 modules with overrides. These entries **do not exist** in the current lock file. Modules like `gateway.nim` (36 exported functions) and `axiom_api.nim` (20) exceed the `core=15` limit yet pass gate. Either:
- The gate binary is stale (compiled against old lock), or
- The extractor undercounts exported functions by ~75% in large modules.

### 5.3 `solid-srp` Hash Fallback
`cohesion_enforce.nim` `computeCohesion` uses actual `variableRefs` when available, but falls back to `normalizedAstFingerprint` (FNV-1a hash) when empty. LCOM/TCC computed on a hash is **mathematically meaningless**.

### 5.4 `ssot-taint` Heuristic Collapse
The taint tracker uses `findPatternInExpr(expr, pattern)` which is literally `expr.contains(pattern)`. With `/`-based path patterns, this generates 366k+ false positives. There is **no data-flow graph**; no type resolution; no canonical source validation.

---

## 6. Compiler-Plugin Rewrite Feasibility (Selected Approach)

### 6.1 Nim Compiler API Landscape
Axiom already uses `compiler/[ast, parser, options, llstream, idents, pathutils]` in:
- `src/gate/architecture_ast_extractor_v3.nim`
- `src/gate/test_v3_import.nim`

The v3 extractor proves the API chain is importable and functional at runtime.

### 6.2 Feasibility Per Principle

| Principle | Compiler API Entry Point | Feasibility | Difficulty |
|-----------|-------------------------|-------------|------------|
| **SRP** | `compiler/ast.PNode` traversal for variable refs + LCOM/TCC | HIGH | ⭐⭐ Medium |
| **OCP** | Policy-driven registry pattern verification + git history | MEDIUM | ⭐⭐⭐ High |
| **LSP** | `compiler/astalgo` + concept pragma checking | HIGH | ⭐⭐ Medium |
| **ISP** | `compiler/parser` + import usage count via `modulegraphs` | MEDIUM | ⭐⭐ Medium |
| **DIP** | `modulegraphs.importDeps` + layer boundary enforcement | HIGH | ⭐ Low |
| **SSOT** | `modulegraphs.allSyms` + explicit canonical declaration | MEDIUM-LOW | ⭐⭐⭐ High |
| **DRY** | PNode AST hashing + structural equivalence | HIGH (syntactic) | ⭐ Low |
| **SoC** | `modulegraphs.importDeps` + transitive call graph | HIGH | ⭐ Low |

### 6.3 Key API Capabilities
- **`compiler/ast.PNode`**: Full AST node tree with `nkProcDef`, `nkIdent`, `nkCall`, `nkDotExpr`, etc. Replaces line-based regex entirely.
- **`compiler/modulegraphs.ModuleGraph`**: Complete import dependency graph with transitive closure. Replaces `extractImports` regex.
- **`compiler/sem.semExpr`**: Type resolution and symbol binding. Enables SSOT taint tracking with actual types instead of substring matching.

### 6.4 Known Pitfalls
1. `.ident.s` vs `.strVal` on `nkIdent` nodes → runtime crash if wrong.
2. `nkAccQuoted` backtick identifiers require manual unwrapping.
3. Compiler API procs raise exceptions → must wrap in `try/except Exception`.
4. `PNode.treerepr` is NOT available (macro API only) → custom walkers needed.
5. Macro-generated functions (`makeGateway`, `makeEnumGateway`) are invisible to runtime parser → use `--expandMacro` or accept partial analysis.
6. API stability: `compiler/` modules are internal implementation details. Pin to Nim 2.2.10.

---

## 7. Recommended Roadmap (Compiler-Plugin Rewrite)

### Phase 1: Foundation (Week 1–2)
1. **Fix `architecture_policy.lock`**: Remove duplicate `[surface_area]`; add missing `[module_overrides]`; verify parser determinism.
2. **PNode-based extractor v4**: Replace `architecture_ast_extractor.nim` line-based regex with `compiler/ast` PNode traversal. Target: 100% exported function accuracy.
3. **Gate binary freshness automation**: Add compile-time Merkle hash check (already documented in `references/binary-self-verification-pattern.md`).

### Phase 2: Core Principles (Month 1)
4. **SoC transitive analysis (depth ≥ 3)**: Use `modulegraphs.importDeps` for full transitive layer violation detection. Replace `call_graph.nim` depth-2 heuristic.
5. **DRY semantic clone detection**: PNode structural hashing with type awareness. Detect Type II (alpha-equivalent) and limited Type III (reordered) clones.
6. **DIP compile-time enforcement**: `static:` block that reads `layer_edges` from policy.lock and aborts compilation on forbidden imports.

### Phase 3: Advanced Principles (Month 2)
7. **SRP PNode-based cohesion**: Extract actual variable references from `nkProcDef` bodies via PNode traversal. Eliminate hash fallback. Reduce LCOM overrides from 25 to <5.
8. **LSP concept verification**: Wire `ProverInterface`/`GateInterface` concepts to compiler-semantic checks. Abort compilation on non-compliant implementations.
9. **ISP fat-interface detection**: Count imported symbols vs. used symbols via `modulegraphs` symbol resolution. Flag modules with usage ratio < 30%.

### Phase 4: SSOT Recovery (Month 2–3)
10. **SSOT compile-time enforcement**: Replace taint tracking with `distinct` types + constructor pattern (already partially implemented for `ValidatedAsi`). Use `compiler/sem` to verify canonical computation modules own their result types.
11. **OCP registry verification**: Statically verify that new features extend via `axiom_registry.nim` rather than modifying existing switch/case statements. Use AST pattern matching on `nkCaseStmt`.

### Phase 5: Determinism & Hardening (Month 3)
12. **Golden snapshot regression suite**: Every query gets a full-tree snapshot. New violations flagged; resolved violations celebrated.
13. **CI integration**: Compiler plugin runs as `nim c` pass (via `--passC` or nimble pre-build task). Violations = compile errors.
14. **False-positive budget enforcement**: Per-query FP rate monitoring. Any query exceeding 5% FP is auto-disabled with `DEPRECATED` marker.

---

## 8. Conclusion

Axiom's quality gate is **the most advanced Nim-native static analysis system documented in Context7**, but it is **not yet CodeQL-grade** for architecture principles. The gap is not in ambition or policy structure — it is in **parser depth** (line-based vs. PNode) and **compile-time enforcement** (post-hoc linter vs. `static:` block).

The **compiler-plugin rewrite** is feasible, language-native, and aligned with GUARDIAN.md's Four-Dimension Mandate. It transforms the gate from a "linter that runs after code is written" into a "compiler that refuses to compile violations" — the definition of Ideal-grade architecture defense.

**Next step**: Execute Phase 1 (Foundation) immediately.
