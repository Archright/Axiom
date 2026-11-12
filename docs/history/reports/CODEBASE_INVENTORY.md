# Axiom_Enterprise Codebase Inventory Report

Generated: 2026-05-26

## Scope: src/ | tests/ | scripts/ (.nim, .py, .md, .cfg, .toml, .nims, .sh)

---

## 1. TODO Markers

### 1.1 `src/cli/commands/heal_parsing.nim:18`
```
## TODO: Remove after all consumers migrate to AxHealFlags.
```
Type: TODO — migration reminder for type alias.

### 1.2 `src/core/trusted/cbor.nim:35`
```
    path: ReasoningPath(),  ## TODO: path restoration logic
```
Type: TODO — Text: "path restoration logic" — incomplete implementation.

### 1.3 `tests/features/steps/mcp_steps.nim:2`
```
## Replaces all TODO stubs with deterministic JSON contract assertions.
```
Type: Commentary (not a code TODO, but references previously existing TODO stubs).

### 1.4 `tests/features/steps/workflow_steps.nim:2`
```
## Replaces all TODO stubs with deterministic state-machine assertions.
```
Type: Commentary (same pattern).

---

## 2. FIXME Markers

NONE found in project source code.

---

## 3. HACK / WORKAROUND Markers

### 3.1 `src/gate/macros/cohesion_enforce.nim:9`
```
# Phase 2 fix: `..<` → `while` (Nim 2.x type inference bug workaround)
```
Type: WORKAROUND — Nim 2.x compiler type inference bug workaround.

### 3.2 `src/gate/macros/cohesion_enforce.nim:42-43`
```
  # while loop instead of `..<` range — workaround for Nim 2.x type inference
  # bug where `for i in 0 ..< n` produces "expression '' has no type"
```
Type: WORKAROUND — Inline code workaround for same Nim compiler bug.

---

## 4. XXX Markers

NONE found in project source code (only `\\uXXXX` escape references in comments).

---

## 5. DEPRECATED Markers

### 5.1 `src/core/tree_sitter_bridge.nim:4`
```
## DEPRECATED: Use core/parsers/tree_sitter/* modules directly.
```
Type: DEPRECATED — re-export shim module.

### 5.2 `src/core/metrics.nim:15`
```
{.push warning[Deprecated]: off.}
```
Type: DEPRECATED — suppresses deprecated warnings for legacy functions.

### 5.3 `src/core/metrics.nim:61-125`
Lines 61, 62, 67, 68, 72, 73, 81, 82, 91, 92, 103, 104, 112, 113, 124, 125:
```
func computeAsi*(...): float {.raises: [], deprecated: "Use computeInformationGainWeightedAsi for canonical ASI".} =
  ## DEPRECATED: Legacy flat coverage formula. Use computeInformationGainWeightedAsi.
```
Type: DEPRECATED — 8 legacy ASI calculation functions all deprecated in favor of `computeInformationGainWeightedAsi`.

### 5.4 `src/core/smt_to_lean_translate.nim:216`
```
## Deprecated: use buildLeanProofScriptFromTrace (structural) instead.
```
Type: DEPRECATED — legacy heuristic translator function.

### 5.5 `src/core/smt_to_lean_translate.nim:250`
```
  ## Removes trailing semicolons and deprecated Lean 3 patterns.
```
Type: DEPRECATED — code comment about deprecated Lean 3 patterns (not the function itself).

### 5.6 `src/core/file_utils.nim:2`
```
{.push warning[Deprecated]: off.}
```
Type: DEPRECATED — suppresses deprecation warning for `std/md5` import.

### 5.7 `src/gate/macros/cohesion_enforce.nim:6`
```
# This replaces the deprecated cohesion_analyzer.nim which computed LCOM
```
Type: DEPRECATED — reference to replaced module.

### 5.8 `src/gate/macros/cohesion_enforce.nim:78`
```
  ## This replaces the deprecated hash-based checkCohesion from cohesion_analyzer.nim.
```
Type: DEPRECATED — documentation reference.

### 5.9 `src/gate/nimtry/cohesion_analyzer.nim:3`
```
# cohesion_analyzer.nim — DEPRECATED
```
Type: DEPRECATED — entire module is deprecated, kept for reference only.

### 5.10 `src/gate/nimtry/taint_tracker.nim:3`
```
# taint_tracker.nim — DEPRECATED
```
Type: DEPRECATED — entire module is deprecated, replaced by distinct ValidatedAsi type.

### 5.11 `src/gate/nimtry/query_engine.nim:14`
```
# DEPRECATED imports — disabled queries:
```
Type: DEPRECATED — comment about disabled/deprecated imports.

### 5.12 `scripts/deprecated/promote_green_to_verified_axiom.nim`
Directory: `scripts/deprecated/` — entire script deprecated by virtue of location.

### 5.13 `scripts/deprecated/backfill_winning_strategies.nim`
Directory: `scripts/deprecated/` — entire script deprecated by virtue of location.

### 5.14 `tests/unit/metrics_validated_asi_test.nim:75`
```
  test "deprecated computeAsi still works but is deprecated":
```
Type: DEPRECATED — test for deprecated function.

---

## 6. TEMPORARY Markers

### 6.1 `src/cli/cst_cli.nim:325`
```
  ## to the certificates actually present so that temporary test fixtures
```
Type: TEMPORARY — comment about temporary test fixtures.

### 6.2 `src/cli/commands/submit_proof.nim:86`
```
  # Create a temporary artifact path
```
Type: Workflow step (not a code quality marker).

### 6.3 `src/cli/commands/submit_proof.nim:136`
```
  # Create a temporary Nim file with the submission script
```
Type: Workflow step (not a code quality marker).

### 6.4 `src/core/lean_replay.nim:7`
```
## Creates temporary .lean file, runs `lean --typecheck`, returns result.
```
Type: Documentation of function behavior (not a marker).

---

## 7. KLUDGE Markers

NONE found in project source code.

---

## 8. BUG Markers (standalone)

NONE found in project source code.

---

## 9. `when false:` Blocks (Dead Code)

### 9.1 `src/cli/wf_runners.nim:245-279`
```nim
when false:
  proc registerAxWorkflowCliCommands*(registry: var CliCommandRegistry) =
    registerCommand(registry, cliCommandEncodeSemanticPayload, proc(args: seq[string]) =
      cmdEncodeSemanticPayload()
    )
    registerCommand(registry, cliCommandVerifySemanticPayload, proc(args: seq[string]) =
      cmdVerifySemanticPayload(args)
    )
    registerCommand(registry, cliCommandScan, proc(args: seq[string]) =
      let result = runAxScanShortcutCli(args)
      ...
    )
    registerCommand(registry, cliCommandProve, proc(args: seq[string]) =
      let result = runAxProveShortcutCli(args)
      ...
    )
    registerCommand(registry, cliCommandVerify, proc(args: seq[string]) =
      cmdVerifyWorkflow(args)
    )
    registerCommand(registry, cliCommandReport, proc(args: seq[string]) =
      let result = runAxReportShortcutCli(args)
      ...
    )
```
Type: Dead code — whole proc for registering CLI workflow subcommands permanently disabled. 35 lines of dead Nim code.

---

## 10. Commented-Out Code Blocks

### 10.1 `src/gate/nimtry/query_engine.nim:15-16`
```nim
# import ./taint_tracker   (replaced by distinct ValidatedAsi)
# import ./cohesion_analyzer (replaced by AST-based cohesion_enforce)
```
Type: Commented-out imports — 2 lines.

### 10.2 `src/gate/nimtry/query_engine.nim:158-164`
```nim
  # result.add(NimtryQuery(
  #   name: "ssot-taint",
  #   rule: "SSOT",
  #   severity: "error",
  #   checker: proc(allFacts: seq[ModuleFacts]; policy: ArchitecturePolicy): seq[ArchitectureViolation] {.raises: [].} =
  #     checkTaintViolations(allFacts, policy)
  # ))
```
Type: Commented-out code — disabled NimtryQuery registration for SSOT taint tracking. 7 lines.

### 10.3 `src/gate/architecture_ast_extractor_v3.nim:5-14`
```nim
#   import compiler/[ast, parser, options, llstream, idents, pathutils]
#   newConfigRef() → ConfigRef
#   llStreamOpen(string) → PLLStream
#   openParser(p, AbsoluteFile, PLLStream, IdentCache, ConfigRef)
#   parseAll(p) → PNode
#   PNode: .kind, .safeLen, .info, .strVal, .intVal, [i] accessor
#   nkProcDef, nkFuncDef, nkEmpty, nkStmtList, nkWhenStmt
#   Not available (NimNode-only, not PNode):
#   .treerepr, .treeRepr — std/macros NimNode API only
#   v3 MVP: accurate exported function counting. Fingerprint deferred.
```
Type: Commented-out code / research notes — compiler API exploration notes. 10 lines.

---

## 11. Summary Statistics

| Category | Count |
|---|---|
| TODO markers | 2 (code) + 2 (commentary) |
| FIXME markers | 0 |
| HACK markers | 0 |
| WORKAROUND markers | 2 |
| XXX markers | 0 |
| DEPRECATED markers | 13 (across 7 files) |
| TEMPORARY markers | 0 (actual code issues) |
| KLUDGE markers | 0 |
| BUG markers | 0 |
| `when false:` blocks | 1 (35 lines of dead code) |
| Commented-out code blocks | 3 (19 lines total) |

### Key Files with Most Issues

| File | Issues |
|---|---|
| `src/core/metrics.nim` | 8 DEPRECATED function declarations |
| `src/gate/macros/cohesion_enforce.nim` | 2 WORKAROUND markers |
| `src/gate/nimtry/query_engine.nim` | 2 commented-out imports + 7-line commented-out code block + DEPRECATED import comment |
| `src/cli/wf_runners.nim` | 1 `when false:` block (35 lines dead code) |
| `src/cli/commands/heal_parsing.nim` | 1 TODO marker |
| `src/core/trusted/cbor.nim` | 1 TODO marker (incomplete Korean comment) |
| `src/core/tree_sitter_bridge.nim` | 1 DEPRECATED header |
| `src/core/smt_to_lean_translate.nim` | 1 DEPRECATED function documentation |
| `src/gate/nimtry/cohesion_analyzer.nim` | Entire file DEPRECATED |
| `src/gate/nimtry/taint_tracker.nim` | Entire file DEPRECATED |
| `scripts/deprecated/` | 2 scripts in deprecated directory |

### Dead Code Estimation

- **`when false:` block**: ~35 lines of completely unreachable code in `wf_runners.nim`
- **Commented-out code**: ~19 lines across 3 blocks
- **DEPRECATED files (keep for reference)**: 2 files (cohesion_analyzer.nim, taint_tracker.nim)
- **DEPRECATED scripts (untracked)**: 2 scripts (promote_green_to_verified_axiom.nim, backfill_winning_strategies.nim)

### Action Items (by Priority)

1. **HIGH** — `src/core/trusted/cbor.nim:35`: Incomplete TODO with Korean text — path restoration logic never implemented.
2. **MEDIUM** — `src/cli/commands/heal_parsing.nim:18`: TODO to remove `AxHealShortcutArgs` alias after consumers migrate.
3. **MEDIUM** — `src/cli/wf_runners.nim:245-279`: Dead code under `when false:` — either remove or re-enable.
4. **LOW** — `src/core/metrics.nim`: 8 deprecated functions; consider removing if no external consumers.
5. **LOW** — `src/gate/nimtry/query_engine.nim:158-164`: Commented-out SSOT taint tracking query; decide to delete or re-enable.
6. **INFO** — `src/gate/architecture_ast_extractor_v3.nim:5-14`: Research notes in comments could be moved to docs/.