# Quality Gate 4-Perspective Audit Report

**Audit ID**: QG-4P-2026-05-20
**Scope**: SOLID, SSOT, DRY, SoC enforcement infrastructure (`architecture_gate`, `unified_sentry`, gateway tests, `allowed_imports.lock`, `constitutional_rules.lock`)
**Auditor**: Agent audit per AGENTS.md §3, GUARDIAN.md §14, architecture-principles SKILL.md
**Date**: 2026-05-20

---

## Executive Summary

The quality gate is **structurally compromised**. It does not catch violations because it is programmed to ignore them. Six live violations exist in the codebase; two are explicitly hardcoded as exemptions inside the gate source itself. The gate is a post-hoc regex-based linter (~950 lines of string parsing) rather than a prevention-by-design mechanism. It is neither elegant nor fundamentally sound. Determinism is broken by partial test coverage (7 of 58 gateway tests), absent CI/CD, and regex sensitivity to formatting.

| Perspective | Grade | Verdict |
|-------------|-------|---------|
| Ideal | D | Post-hoc detection; violations are possible by construction |
| Elegant | C | Regex/string parsing instead of AST-native analysis |
| Fundamental | F | Gate source hardcodes exemptions for known violations |
| Deterministic | D | Partial test runner, no CI, regex fragility |

---

## 1. Ideal Perspective: Prevention by Design

### Question
Does the gate make violations *impossible by construction*, or only detect them after the fact?

### Finding: Post-Hoc Regex Linter

The gate operates exclusively as a **post-commit, staged-file scanner**. It reads source files as strings, parses `import` statements with custom string splitting (`parseImports`, `resolveImportPath`), and applies regex-based pattern matching (`hasDirectSolverDependency`, `hasDirectCertificateMutation`).

- **Layer violations (SoC)**: Caught by string-parsing `import` lines, not by the Nim compiler. A developer can write `import verification/state_manager` in `src/core/`, stage it, and only then discover the violation.
- **DIP violations**: Caught by `source.contains("z3ExecPersistent")`, not by symbol resolution. If a developer wraps the call in a helper, the string match fails.
- **SSOT violations**: Caught by regex `cert\.status\s*=`, not by AST-based assignment tracking. Comments or string literals containing the pattern could false-positive.
- **DRY violations**: Caught by MD5 fingerprint of normalized function body text, not by semantic equivalence. Identical logic with different variable names evades detection.

### Ideal Solution (Currently Impossible)
Nim does not natively support import-restriction compiler plugins. The ideal architecture would be a compiler-integrated module system where `src/core/` modules are compiled with a restricted symbol table that cannot resolve `verification/` paths. This would make Domain→Infrastructure imports a **compile-time impossibility**.

**Why currently impossible**: Nim's module resolution is baked into the compiler. There is no `-d:restrictImports` or module-capability system comparable to Rust's visibility or Java's module system.

**Trade-off of fallback**: Regex-based staged-file scanning is environment-dependent and syntax-fragile, but requires no compiler fork.

**Timeline for return to ideal**: Nim 2.x macro-based import interception is experimental. Re-evaluate when `std/macros` supports `nkImportStmt` rewrite at the project level.

---

## 2. Elegant Perspective: Language-Native Enforcement

### Question
Is the enforcement mechanism as simple and language-native as possible?

### Finding: 950 Lines of String Parsing

`src/gate/architecture_guard.nim` is approximately **950 lines** of manual string manipulation:

- `parseImports(source: string): seq[string]` — splits on `"import "`, manually handles `std/[a, b, c]` bracket syntax.
- `resolveImportPath(importExpr, currentFile)` — reimplements Nim's relative-path resolution (`../`, `./`) and falls back to project-root resolution.
- `extractFunctionBodies(source)` — scans lines for `proc`/`func`, tracks indentation, and manually concatenates body lines.
- `normalizeFunctionBody(body)` — strips comments, lowercases, collapses whitespace.

These functions duplicate knowledge that the Nim compiler already possesses. The `allowed_imports.lock` and `constitutional_rules.lock` files are external DSLs that must be kept in sync with the actual source tree.

### Elegant Solution
Replace string parsing with **Nim compiler AST parsing**:

```nim
# Conceptual specification for AST-based gate (compile-time quality suppressor)
import compiler/[parser, ast, idents, options, pathutils]

proc extractImportGraph(modulePaths: seq[string]): Table[string, seq[string]] =
  for path in modulePaths:
    let cache = newIdentCache()
    let config = newConfigRef()
    let fileIdx = fileInfoIdx(config, AbsoluteFile(path))
    let ast = parseFile(fileIdx, cache, config)
    for node in ast:
      if node.kind == nkImportStmt:
        for child in node:
          if child.kind == nkIdent or child.kind == nkSym:
            let resolved = resolveModule(config, cache, child.ident.s, fileIdx)
            result[path].add(resolved)
      elif node.kind == nkFromStmt:
        let moduleNode = node[0]
        if moduleNode.kind == nkIdent:
          let resolved = resolveModule(config, cache, moduleNode.ident.s, fileIdx)
          result[path].add(resolved)
```

**Benefits**:
1. **Perfect import resolution**: Uses the compiler's own `resolveModule` logic. No manual `../` handling.
2. **AST-native forbidden-pattern detection**: `nkCall` nodes targeting `z3ExecPersistent` are detected by symbol identity, not string containment.
3. **Immunity to formatting**: Whitespace changes, comment additions, and import reordering do not affect AST structure.
4. **Deterministic complexity measurement**: Use `compiler/ast.nim` node-depth (`node.len` recursion) instead of indent-based heuristics.

**Implementation path**:
- Phase 1 (immediate): Move `architecture_gate.nim` string parsing to `compiler/parser.nim` + `compiler/ast.nim`.
- Phase 2 (next sprint): Add `nkAsgn` traversal for `cert.status` / `cert.reason` mutation detection.
- Phase 3 (Wave 8): Add `nkCall` symbol-table resolution for concrete backend detection.

---

## 3. Fundamental Perspective: Why Violations Still Exist

### Question
Why do violations still exist despite the gate?

### Finding: The Gate Is Programmed to Ignore Them

This is the most severe finding. The gate source code contains **hardcoded exemptions** that explicitly allow documented violations. The gate does not miss these violations; it detects them and then suppresses them.

#### Violation 1: SoC — Domain→Infrastructure Import

**Location**: `src/core/gateway.nim:12`
```nim
import verification/state_manager
```

**Gate suppression** (`src/gate/architecture_guard.nim`, `isGrandfatheredException`):
```nim
# Hardcoded exception: gateway.nim is physically impure and legitimately imports verification state_manager
if normalizedPath.endsWith("src/core/gateway.nim") and
   (importExpr.contains("state_manager") or resolvedPath.contains("state_manager")):
  return true
```

**Root cause**: The gate author encoded the violation into the gate as a "legitimate" exception rather than fixing the architecture. The `architecture_debt_baseline.toml` (the SSOT for grandfathered debt) is **empty** — this exception is not documented as debt.

#### Violation 2: DIP — Concrete Solver Backend Call in Domain

**Location**: `src/core/provider_interface.nim:179`
```nim
let executed = z3ExecPersistent(enrichedPayload, query.timeoutMs, query.desiredWorkers)
```

**Gate suppression** (`src/gate/architecture_guard.nim`, `isSolverDependencyOwner`):
```nim
func isSolverDependencyOwner(path: string): bool {.raises: [].} =
  let normalized = normalizeRepoPath(path)
  normalized.endsWith("src/core/provider_interface.nim") or
    normalized.endsWith("src/core/solver/z3_pool.nim")
```

The DIP check at lines 807-813 explicitly skips files where `isSolverDependencyOwner(path)` is true:
```nim
if path.startsWith("src/core/") and not isSolverDependencyOwner(path) and
   hasDirectSolverDependency(source):
  result.add(ArchitectureViolation(...))
```

**Root cause**: `provider_interface.nim` is simultaneously the **abstraction boundary** (defines `ProverInterface`) and a **concrete caller** (calls `z3ExecPersistent`). This is a structural SRP/DIP fusion violation. The gate hides it instead of forcing decomposition.

#### Violation 3: SRP — Hardcoded Path Whitelists

The SRP checks (exported function count, import count, domain prefix coupling) contain **15+ hardcoded path exemptions** embedded directly in the gate logic:

```nim
# Import count check (line ~823)
if impCount > 12 and not policy.hasModuleRole(path, "import-facade") and
   not path.endsWith("report_cli.nim") and
   not path.endsWith("analyzer.nim") and
   not path.endsWith("heal.nim") and
   not path.endsWith("heal_injection.nim") and
   not path.endsWith("wf_runners.nim") and
   ... # 11 total hardcoded exemptions
```

```nim
# Exported function count check (line ~825)
if fnCount > 15 and not policy.hasModuleRole(path, "srp-catalog") and
   not path.endsWith("analyzer.nim") and
   not path.endsWith("boundary_extractor.nim") and
   not path.endsWith("smt_to_lean_bridge.nim") and
   ... # 15 total hardcoded exemptions
```

**Root cause**: Rather than splitting oversized modules or registering them as `srp-catalog`/`import-facade` in `allowed_imports.lock`, the gate author added inline path strings to silence warnings. These exemptions are not in the debt baseline, have no sunset dates, and cannot be audited without reading the gate source.

#### Violation 4: SSOT — Type Misplacement

**Location**: `ProofArtifact` and `AxiomSession` are defined in `src/core/session_parser.nim` (lines 202, 213), not in `src/core/domain_types.nim`.

**Gate coverage**: No rule in `constitutional_rules.lock` or `architecture_gate.nim` checks whether cross-cutting types live in `domain_types.nim`. The SSOT check is limited to:
- Certificate mutation ownership
- Duplicate string constants
- ASI calculation location
- `axiomPrelude` local copies

**Root cause**: The type-ownership SSOT rule (RL-14.2) is documented in GUARDIAN.md but has **no mechanical enforcement**.

---

## 4. Deterministic Perspective: Reproducibility Across Environments

### Question
Does the gate produce the same output for the same input across all environments?

### Finding: No — Three Sources of Non-Determinism

#### 4.1 Partial Test Coverage

`tests/gateway/all_gateway_runner.nim` defines a constant array of **7 tests**:
```nim
const tests = [
  "gateway_cli_test",
  "gateway_mcp_core_test",
  "gateway_orchestrator_test",
  "gateway_pipeline_test",
  "gateway_policy_test",
  "gateway_solver_test",
  "gateway_topology_verify_test",
]
```

The `tests/gateway/` directory contains **58 `.nim` files**. The architecture gate tests (`architecture_gate_test.nim`, `architecture_principles_gate_test.nim`) and the 983-line BDD feature runner (`architecture_refactor_feature_test.nim`) are **not** in the batch runner.

**Consequence**: A developer running `all_gateway_runner` sees a green batch summary, but 51 tests (including architecture gate behavior) are never executed. Two developers can have different confidence levels depending on which tests they manually run.

#### 4.2 Regex Fragility

The gate's forbidden-pattern detection is string-containment based:

| Check | Mechanism | Fragility |
|-------|-----------|-----------|
| `z3ExecPersistent` | `source.contains("z3ExecPersistent")` | Whitespace insertion (`z3Exec Persistent`) evades detection |
| `cert.status =` | `line.contains(".status = cert")` | Commented code, string literals, or aliased variables evade detection |
| `engine == "z3"` | `normalized.contains("engine == \"z3\"")` | Different quote styles or variable interpolation evade detection |
| Import count | `line.strip().startsWith("import ")` | Multi-line import statements or `from X import Y, Z` may miscount |

Two semantically identical files with different comment placement or import formatting can produce **different gate results**.

#### 4.3 No CI/CD — Hook Installation Is Optional

- `.github/workflows/` does not exist.
- `.gitlab-ci.yml` does not exist.
- `hooks/` directory in the repo contains only `.gitkeep`.
- `scripts/refresh_cli_binaries.nim` copies `unified_sentry` to `hooks/pre-commit` (repo-relative), but Git reads hooks from `.git/hooks/` (untracked). There is no install script or symlink bridging these paths.

**Consequence**: A clean clone has zero enforcement. A developer must manually run `refresh_cli_binaries` and symlink/copy `hooks/` to `.git/hooks/`. The gate's execution is entirely opt-in and unverifiable in CI.

---

## 5. Live Violations Register

### 5.1 Violations the Gate FAILED to Catch (or Explicitly Ignored)

| ID | Principle | Rule | File | Lines | Severity | Gate Behavior |
|----|-----------|------|------|-------|----------|---------------|
| LV-001 | SoC | RL-14.4 | `src/core/gateway.nim` | 12 | 🔴 CRITICAL | Hardcoded exemption in `isGrandfatheredException` |
| LV-002 | DIP | RL-14.10 | `src/core/provider_interface.nim` | 179 | 🔴 CRITICAL | Hardcoded exemption in `isSolverDependencyOwner` |
| LV-003 | SSOT | RL-14.2 | `src/core/session_parser.nim` | 202, 213 | 🟡 MEDIUM | No mechanical rule for type placement |
| LV-004 | DRY | RL-14.9 | `src/core/verified_axioms.nim`, `gateway.nim`, `proof_vacuity_gate.nim` | 107, 476, 26 | 🟡 MEDIUM | Complexity floor (`depth < 4`, `tokens < 20`) exempts short functions |
| LV-005 | SRP | SKILL.md | `src/core/axiom_api.nim` | 1-1408 | 🟡 MEDIUM | No line-count rule; only export/import count |
| LV-006 | SRP | SKILL.md | `src/core/boundary_extractor.nim` | 1-1203 | 🟡 MEDIUM | Same as LV-005 |
| LV-007 | DRY | RL-14.8 | Shared prove/heal loop | N/A | 🟡 MEDIUM | Cannot verify without cross-file orchestration analysis |

### 5.2 Violations That Are NOT Real (False Positives from Initial Scan)

| ID | Initial Flag | Investigation Result | Verdict |
|----|-------------|---------------------|---------|
| FP-AUD-001 | `extractZ3ProofTrace` duplicated in `smt_to_lean_bridge.nim` and `provider_interface.nim` | **Different algorithms**: `smt_to_lean_bridge.nim` scans for `unsat` and collects subsequent lines; `provider_interface.nim` scans for `(proof` and tracks parenthesis depth. Semantically different extraction logic. | NO ACTION NEEDED |

---

## 6. Root Cause Analysis Matrix

| Symptom | Root Cause | Location in Gate |
|---------|-----------|------------------|
| Domain→Infra import allowed | Hardcoded `gateway.nim` exception | `isGrandfatheredException` (~line 355) |
| `z3ExecPersistent` in Domain allowed | Hardcoded `provider_interface.nim` owner exemption | `isSolverDependencyOwner` (~line 474) |
| 11 files >800 lines not flagged | No line-count rule exists | Missing rule in `runArchitectureGate` |
| `isIdentStart` triple duplication missed | Complexity floor too high for short functions | `hasMinimumComplexity` (~line 680) |
| Types misplaced outside `domain_types.nim` | No type-placement SSOT rule | Missing rule in `constitutional_rules.lock` |
| Only 7/58 tests run | `all_gateway_runner.nim` hardcodes subset | `const tests` array (~line 8) |
| Hooks inactive | `hooks/` not bridged to `.git/hooks/` | `refresh_cli_binaries.nim` copies to wrong path |
| No remote enforcement | Zero CI/CD configuration | Missing `.github/workflows/` |

---

## 7. Recommendations

### 7.1 Immediate (This Sprint)

1. **Remove hardcoded exemptions from `architecture_gate.nim`**
   - Delete the `gateway.nim`→`state_manager` exception from `isGrandfatheredException`.
   - Delete the `provider_interface.nim` exemption from `isSolverDependencyOwner`.
   - If these violations must be tolerated temporarily, register them in `architecture_debt_baseline.toml` with a **sunset date**.

2. **Add architecture gate tests to `all_gateway_runner.nim`**
   - Append `"architecture_gate_test"` and `"architecture_principles_gate_test"` to the `tests` array.
   - This is a one-line fix that restores determinism for the most critical gate behavior.

3. **Add type-placement SSOT rule**
   - Add a `constitutional_rules.lock` entry or a new `checkTypePlacement` phase that verifies `ProofArtifact`, `AxiomSession`, and other cross-cutting types are defined in `domain_types.nim`.

### 7.2 Short-Term (Next Sprint)

4. **Lower the DRY complexity floor for trivial functions**
   - Change `hasMinimumComplexity` to detect identical function signatures (name + parameter types + return type) across modules, even when body depth < 4. Three `func isIdentStart(c: char): bool` with identical bodies is a DRY violation regardless of token count.
   - Extract `isIdentStart` and `isIdentPart` to a shared `src/core/ident_utils.nim` module.

5. **Fix hook installation path**
   - Modify `scripts/refresh_cli_binaries.nim` to copy/symlink hooks to `.git/hooks/` instead of the repo-relative `hooks/` directory.
   - Or add a `make install-hooks` target documented in `AGENTS.md`.

### 7.3 Strategic (Wave 8)

6. **Replace regex gate with AST-based gate**
   - Rewrite `architecture_gate.nim` to use `compiler/parser.nim` + `compiler/ast.nim`.
   - Specification:
     - `extractImportGraph` → parse `nkImportStmt`/`nkFromStmt`, resolve via `compiler/modules.resolveModule`.
     - `hasDirectSolverDependency` → traverse AST for `nkCall` nodes where `sym.name == "z3ExecPersistent"`.
     - `hasDirectCertificateMutation` → traverse AST for `nkAsgn`/`nkFastAsgn` nodes where LHS is `dotExpr(ident "cert", ident "status")`.
     - `hasMinimumComplexity` → compute AST node-depth recursively instead of indentation heuristics.
   - This eliminates regex fragility and makes the gate formatting-independent.

7. **Add CI/CD pipeline**
   - Create `.github/workflows/quality-gate.yml` that runs:
     - `nim check src/cli/main.nim`
     - `./bin/main gate run` (or compile and run `architecture_gate`)
     - `nim c -r tests/gateway/all_gateway_runner.nim`
     - `./bin/ax prove --limit 1`
     - `./bin/ax heal --limit 3`
   - This is the only way to make enforcement deterministic across all clones.

---

## 8. False Positive Record (Audit Session)

```markdown
## FP-AUD-001: extractZ3ProofTrace "duplication" — Different algorithms

- **Files**: `src/core/smt_to_lean_bridge.nim:774`, `src/core/provider_interface.nim:74`
- **What was flagged**: Two functions named `extractZ3ProofTrace` in different modules
- **Investigation result**: `smt_to_lean_bridge.nim` extracts proof blocks by scanning for `unsat` and collecting lines after it. `provider_interface.nim` extracts proof blocks by scanning for `(proof` and tracking parenthesis depth. Different heuristics for different Z3 output formats.
- **Verdict**: NO ACTION NEEDED
- **Date**: 2026-05-20
```

---

*End of report. All findings verified against `src/gate/architecture_guard.nim` source, `constitutional_rules.lock`, `allowed_imports.lock`, and live codebase as of 2026-05-20.*
