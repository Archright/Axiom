# Query No-Obligation Debt Analysis

> **Status**: Analysis document (read-only, no code changes)
> **Date**: 2026-08-13
> **Scope**: P3 — 16 `cnaNoObligations` kernel symbols classified by causeClass
> **Related**: [VKD — Verified Kernel Density](./verification_density.md), [Proof Integrity](../core/proof/proof_integrity.nim)

---

## 1. Overview

The VKS (Verifiable Kernel Scope) contains 23 symbols (`K \ E = 40 - 17 = 23`).
Of these, 5 are `certGreen` (verified), 2 are `certRed` (failed), and **16 are `certYellow` with no canonical certificate** — they are classified as `cnaNoObligations` by the CHC/Spacer backend.

`cnaNoObligations` means the CHC builder found **no safety obligations and no semantic obligations** to prove. The query would vacuously return `unsat` and prove nothing (§0.9 Anti-Theater). This is a **semantics gap, not a capability gap**.

The 16 no-obligation symbols are **logically separate from VKD 6** (the 5 `certGreen` + 1 `certYellow` with `canonicalCertificate`). No-obligation is a distinct proof-debt category managed independently from the VKD numerator.

### Key Distinction

| Category | Count | Meaning |
|----------|-------|---------|
| `certGreen` (VKD molecule) | 5 | Deep-verified, passes CHC + Lean |
| `certRed` | 2 | CHC returned a failure (firstBoolCore, firstIntCore) |
| `certYellow` / `cnaNoObligations` | **16** | CHC returned `cbNotApplicable(cnaNoObligations)` — no obligations to prove |
| Exempt (not in VKS) | 17 | Kernel-exempt symbols |

---

## 2. The 16 No-Obligation Symbols

All 16 symbols are drawn from `data/vks_topology.json` where `buildStatus == "certYellow"` and `canonicalCertificate` is absent. Cross-referenced against `data/verification_scope.lock` (`kernel_symbols`) and `data/baseline.json` (`kernelTotal: 40`, `kernelVerified: 5`).

| # | Symbol | Module | Source File |
|---|--------|--------|-------------|
| 1 | `axiomSpecToJsonNode` | `vault_manager_spec.nim` | `src/core/vault/vault_manager_spec.nim` |
| 2 | `normalizedEntries` | `gate_rules_normalization.nim` | `src/gate/gate_rules_normalization.nim` |
| 3 | `initModuleClassificationCache` | `gate_rules_module_classifier.nim` | `src/gate/gate_rules_module_classifier.nim` |
| 4 | `applyCallDepthCheck` | `gate_rules_architecture.nim` | `src/gate/gate_rules_architecture.nim` |
| 5 | `hasVaultEntry` | `sorter_core_index_table.nim` | `src/core/sorter/sorter_core_index_table.nim` |
| 6 | `findTopologyMetricIndex` | `topology_engine.nim` | `src/core/topology/topology_engine.nim` |
| 7 | `findTopologySymbolIndex` | `topology_engine.nim` | `src/core/topology/topology_engine.nim` |
| 8 | `findTopologyNodeContext` | `topology_engine.nim` | `src/core/topology/topology_engine.nim` |
| 9 | `timeoutDiagnosisForNode` | `orchestrator_topology_worker.nim` | `src/core/orchestrator/orchestrator_topology_worker.nim` |
| 10 | `addNodeExecutionStat` | `orchestrator_vault.nim` | `src/core/orchestrator/orchestrator_vault.nim` |
| 11 | `addDepthExecutionStat` | `orchestrator_vault.nim` | `src/core/orchestrator/orchestrator_vault.nim` |
| 12 | `addNodeReport` | `orchestrator_vault.nim` | `src/core/orchestrator/orchestrator_vault.nim` |
| 13 | `enqueueParallelWorkItem` | `orchestrator_api.nim` | `src/core/orchestrator/orchestrator_api.nim` |
| 14 | `skipJsonValue` | `json_scan_skip.nim` | `src/core/json/json_scan_skip.nim` |
| 15 | `generateOverflowDefines` | `ir_to_smt_chunk3.nim` | `src/core/trusted/private/ir_to_smt_chunk3.nim` |
| 16 | `generateOverflowAssertions` | `ir_to_smt_chunk3.nim` | `src/core/trusted/private/ir_to_smt_chunk3.nim` |

> **Note**: `prepareParallelInputs` (`orchestrator_api.nim`) is a kernel symbol but is in the **exempt** list (`kernel_exempt_symbols`), not in VKS. It is excluded from this analysis.

---

## 3. CauseClass Assignment

Each symbol is assigned a `causeClass` based on source evidence. Classifications are conservative — where source evidence is insufficient for a definitive assignment, the symbol is marked `unknown, needs domain review`.

### CauseClass Definitions

| Class | Meaning | Source Criterion |
|-------|---------|-----------------|
| **A** | Property absence | Function has no verification property (no postconditions, no preconditions, no derived safety obligations). CHC correctly returns `cnaNoObligations` because there is nothing to prove. |
| **B** | Lowering gap | Function has a property but the CHC lowering cannot produce obligations from it. The property exists but the CHC encoder cannot handle it. |
| **C** | Contract undefined | Function should have a verification contract but none is defined. The contract synthesis pass produced an empty `ContractInfo`. |
| **D** | Scope misclassification | Function is classified as no-obligation but should be in proof mode (`expectedObligation: true`). The CHC result is correct (no obligations) but the scope classification is wrong. |

### Classification Table

| # | Symbol | causeClass | Evidence | Confidence |
|---|--------|-----------|----------|------------|
| 1 | `axiomSpecToJsonNode` | **A** | Pure serialization function. Returns `JsonNode`. No loops, no state mutations, no verification-relevant properties. `{.axiom, axiomImpl.}` pragma provides structural SMT specs (string lengths) but no behavioral property. `contract_synthesis` produces empty `ContractInfo` (no division/index/assert patterns, return type `JsonNode` is not in `irtEnum/irtVariant/irtBitVec64`). | High |
| 2 | `normalizedEntries` | **A** | Pure data transformation (`strip → filter → deduplicate`). No loops with verification-relevant state. Return type `seq[string]` — no implicit postcondition synthesized. | High |
| 3 | `initModuleClassificationCache` | **A** | Lock initialization (`initLock`). No verification properties. No loops, no return value. | High |
| 4 | `applyCallDepthCheck` | **A** | Architecture gate rule. Analyzes call graph and adds violations. No verification properties of its own — it is a meta-analysis function, not a verification target. | High |
| 5 | `hasVaultEntry` | **A** | Pure lookup in a `Table`. No loops, no state mutation. Return type `bool` — no implicit postcondition. | High |
| 6 | `findTopologyMetricIndex` | **A** | Pure lookup in topology analysis data structure. No loops with verification-relevant state. Return type `int` — no clamp pattern in body. | High |
| 7 | `findTopologySymbolIndex` | **A** | Pure lookup in topology analysis data structure. Same analysis as `findTopologyMetricIndex`. | High |
| 8 | `findTopologyNodeContext` | **A** | Pure lookup in topology analysis data structure. No verification properties. | High |
| 9 | `timeoutDiagnosisForNode` | **A** | Diagnostic/analysis function. Pure computation over timeout state. No verification properties. | High |
| 10 | `addNodeExecutionStat` | **A** | Statistics accumulator. Pure mutation of a report struct. No verification properties. | High |
| 11 | `addDepthExecutionStat` | **A** | Statistics accumulator. Same analysis as `addNodeExecutionStat`. | High |
| 12 | `addNodeReport` | **A** | Report construction. Pure data assembly. No verification properties. | High |
| 13 | `enqueueParallelWorkItem` | **A** | Orchestration function. Enqueues work items into a queue. No verification properties. | High |
| 14 | `skipJsonValue` | **A** | JSON scanning utility. Pure computation over string input. No verification properties. | High |
| 15 | `generateOverflowDefines` | **A** | SMT-LIB2 code generation helper. Produces overflow definition strings for the SMT backend. Not a verification target itself — it generates code for other functions' overflow properties. `contract_synthesis` produces empty `ContractInfo` (no division/index/assert patterns, return type `seq[string]`). | High |
| 16 | `generateOverflowAssertions` | **A** | SMT-LIB2 code generation helper. Produces overflow assertion strings for the SMT backend. Same analysis as `generateOverflowDefines`. | High |

### Summary

| causeClass | Count | Symbols |
|-----------|-------|---------|
| **A** (property absence) | 16 | All 16 symbols |
| **B** (lowering gap) | 0 | — |
| **C** (contract undefined) | 0 | — |
| **D** (scope misclassification) | 0 | — |

> **All 16 symbols are causeClass A** based on source evidence. Every symbol is a pure infrastructure/utility function with no verification-relevant properties. The CHC backend correctly returns `cnaNoObligations` because there are no obligations to prove.

> **Uncertainty note**: CauseClass D (scope misclassification) cannot be ruled out without checking the runtime `RuntimeAxiomEntry.expectedObligation` registry. The `expectedObligation` field defaults to `false` in `axiom_pragmas_types.nim:55`, but the runtime registry is populated dynamically. If any of these 16 symbols should have `expectedObligation: true`, they would be reclassified as D. This requires domain review.

---

## 4. NoObligationRecord Schema

The following schema defines the canonical structure for recording no-obligation debt entries. This is a **documentation schema only** — no code changes are proposed.

```
NoObligationRecord
├── symbol           string          # Fully qualified symbol name (e.g., "src/core/vault/vault_manager_spec.nim::axiomSpecToJsonNode")
├── scope            string          # VKS scope identifier (e.g., "kernel")
├── causeClass       enum {A, B, C, D, unknown}
│   ├── A  property absence         # No verification property exists for this symbol
│   ├── B  lowering gap             # Property exists but CHC lowering cannot produce obligations
│   ├── C  contract undefined       # Verification contract is not defined (should exist but is missing)
│   ├── D  scope misclassification  # Symbol should be proof-mode but classified as no-obligation
│   └── unknown  needs domain review
├── evidence         string          # Source-level evidence for the classification (file:line reference)
├── requiredProof    string          # What proof would be needed to resolve this debt (e.g., "BMC fallback", "design plan", "contract synthesis")
├── blocking         bool            # Whether this no-obligation blocks VKD progression (currently false — no-obligation is not a VKD failure)
├── owner            string          # Responsible party or team for resolution
├── status           enum {open, under_review, resolved, wont_fix}
├── relatedDebtId    string?         # Optional DEBT# reference in data/debt_registry.json
└── lastVerifiedAt   string?         # ISO 8601 timestamp of last verification
```

### Schema Rationale

- **`symbol`**: Fully qualified path ensures uniqueness across the 40-symbol kernel namespace.
- **`causeClass`**: The four-class taxonomy (A/B/C/D) plus `unknown` provides a conservative classification framework. The `unknown` value is the default when source evidence is insufficient.
- **`blocking`**: Set to `false` for all 16 symbols because `cnaNoObligations` is explicitly **not** a VKD failure per §0.9 Anti-Theater. The VKD numerator counts only `certGreen` symbols.
- **`requiredProof`**: Documents what kind of proof effort would be needed to resolve the debt, distinguishing between mechanical fixes (BMC fallback) and design-level decisions (contract synthesis).

---

## 5. Source Evidence

### 5.1 CHC Build Result (`chc_build_result.nim`)

```nim
ChcNotApplicableReason* = enum
  cnaNoObligations  ## Vacuous — a query with no `error` rule proves nothing (§0.9). Not a capability issue.
  cnaNoProperty     ## Function carries no property to check on a well-formed model.
```

The `cnaNoObligations` reason is returned when `buildObligations(vm)` produces zero safeties and `sem.obligations` is empty. This means the function has no postconditions, no preconditions, and no derived safety properties.

### 5.2 IR Loop to CHC (`ir_loop_to_horn.nim:294-296`)

```nim
let derived = buildObligations(vm)
if derived.safeties.len == 0 and sem.obligations.len == 0:
  return chcBuildNotApplicable(cnaNoObligations)
```

This is the exact code path that classifies all 16 symbols as `cnaNoObligations`.

### 5.3 Contract Synthesis (`contract_synthesis.nim:306-313`)

```nim
func synthesizeContracts*(funcDef: var IRFuncDef) {.raises: [].} =
  funcDef.preConditions.add(collectDivisionGuards(funcDef.body))
  funcDef.preConditions.add(collectIndexGuards(funcDef.body))
  funcDef.preConditions.add(collectAssertGuards(funcDef.body))
  if funcDef.postConditions.len == 0:
    funcDef.postConditions.add(collectPostconditions(funcDef))
```

If a function has no division/index/assert patterns and its return type is not enum/variant/BitVec64 with a clamp pattern, `synthesizeContracts` produces an empty contract, leading to `cnaNoObligations`.

### 5.4 Pipeline Runner (`ir_pipeline_runner.nim:503-505`)

```nim
let reason = if chcBuild.kind == cbNotApplicable and
                chcBuild.notApplicableReason == cnaNoObligations:
  makeNoObligation()
else:
  makeNotEncodable()
```

The pipeline explicitly distinguishes `cnaNoObligations` (vacuous, not a capability gap) from other `cbNotApplicable` reasons (encoding failures).

---

## 6. Cross-References

| Data Source | Path | Relevance |
|-------------|------|-----------|
| VKS topology | `data/vks_topology.json` | Source of truth for the 16 certYellow symbols |
| Verification scope lock | `data/verification_scope.lock` | Kernel symbols list (40) and exempt symbols (17) |
| Baseline metrics | `data/baseline.json` | `kernelTotal: 40`, `kernelVerified: 5`, `vksTotal: 23` |
| Debt registry | `data/debt_registry.json` | DEBT#264+ entries; P1.2 post-fix results (Pass 17, Fail 2, Skip 16) |
| Proof integrity | `src/core/proof/proof_integrity.nim` | `NoObligationClass` enum and `classifyNoObligation` proc |
| CHC build result | `src/core/trusted/private/chc_build_result.nim` | `cnaNoObligations` / `cnaNoProperty` definitions |
| IR loop to HORN | `src/core/trusted/private/ir_loop_to_horn.nim` | `cnaNoObligations` return path |
| Contract synthesis | `src/core/trusted/contract_synthesis.nim` | `synthesizeContracts` — how contracts are auto-generated |
| Axiom pragmas | `src/core/trusted/axiom_pragmas_types.nim` | `expectedObligation` field (default `false`) |
| Pipeline runner | `src/verification/batch_uap/ir_pipeline_runner.nim` | `cnaNoObligations` → `makeNoObligation()` path |

---

## 7. Debt Registry Registration

This analysis identifies 16 no-obligation symbols as proof debt. Per §0.9c, these should be registered in `data/debt_registry.json` with category prefix `Theater/` if they are determined to be theater, or as standard debt entries if they represent genuine unverified proof obligations.

**Current status**: All 16 are classified as causeClass A (property absence), which means they are **not theater** — they are legitimate no-obligation results from functions with nothing to prove. They should be registered as standard debt entries (not Theater/) with a `requiredProof` of "design plan: determine if these infrastructure functions should have verification properties."

---

## 8. Open Questions

1. **Should any of these 16 symbols have `expectedObligation: true`?** This requires domain review of the orchestration and infrastructure layer to determine if any are misclassified as no-obligation (causeClass D).

2. **Should `cnaNoProperty` be used instead of `cnaNoObligations` for some symbols?** The `cnaNoProperty` reason exists in `chc_build_result.nim` but is not currently returned by the CHC builder. If the builder is updated to distinguish "no property" from "no obligation," some symbols may be reclassified.

3. **Can contract synthesis be extended for these symbols?** If any of these infrastructure functions should have verification properties, `contract_synthesis.nim` could be extended to synthesize appropriate pre/postconditions.

---

## Appendix: NoObligationRecord JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft/2020-12/schema",
  "title": "NoObligationRecord",
  "description": "Canonical record for a kernel symbol classified as cnaNoObligations (no safety obligations derived by CHC).",
  "type": "object",
  "required": ["symbol", "scope", "causeClass", "evidence", "requiredProof", "blocking", "owner", "status"],
  "properties": {
    "symbol": {
      "type": "string",
      "description": "Fully qualified symbol name (modulePath::functionName)"
    },
    "scope": {
      "type": "string",
      "description": "VKS scope identifier (e.g., 'kernel')"
    },
    "causeClass": {
      "type": "string",
      "enum": ["A", "B", "C", "D", "unknown"],
      "description": "Classification of why the symbol has no obligations"
    },
    "evidence": {
      "type": "string",
      "description": "Source-level evidence for the classification"
    },
    "requiredProof": {
      "type": "string",
      "description": "What proof effort is needed to resolve this debt"
    },
    "blocking": {
      "type": "boolean",
      "description": "Whether this blocks VKD progression (always false for cnaNoObligations)"
    },
    "owner": {
      "type": "string",
      "description": "Responsible party or team"
    },
    "status": {
      "type": "string",
      "enum": ["open", "under_review", "resolved", "wont_fix"],
      "description": "Resolution status"
    },
    "relatedDebtId": {
      "type": ["string", "null"],
      "description": "Optional DEBT# reference"
    },
    "lastVerifiedAt": {
      "type": ["string", "null"],
      "format": "date-time",
      "description": "ISO 8601 timestamp of last verification"
    }
  }
}
```