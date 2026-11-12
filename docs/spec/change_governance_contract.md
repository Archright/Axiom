# Change Governance Contract

**Status**: Normative contract declaration (plan-approved 2026-08-18)
**Created**: 2026-08-18
**Related**: AGENTS.md §-1, `data/debt_registry.json`, `docs/spec/audit_tooling_contract.md`, `docs/spec/productization_contract.md`

---

## 1. Purpose / Scope

This document declares the **normative contract for change classification and ratification boundaries** in the Axiom repository. It is a governance state machine **declaration only** — it does not implement one.

### What this document does NOT do (SHALL NOT)

- **Implement a governance state machine.** This document is a contract declaration, not an executable specification.
- **Modify `data/debt_registry.json`.** The registry remains the sole SSOT for debt entries; this document does not alter its schema, content, or update procedures.
- **Rewrite audit baselines.** `docs/history/audit_baseline_*.json` files are produced by the existing ratification pipeline and are not affected by this contract.
- **Change CLI or gate semantics.** No existing subcommand (`--audit-dir-doc`, `--ratify`, `--rerun`, `--validate`, etc.) behavior is redefined here.
- **Define a new product feature.** This document is a **guardrail**, not a product. It exists to protect the productization vertical slice (see below).

### Productization vertical slice relationship

The Axiom v1 product contract (`docs/spec/productization_contract.md`) defines the committed vertical slice: `ax prove` crash safety, runtime isolation, canonical result determinism, certificate provenance, CLI exit-state contract, VKD projection, and golden slice. This governance contract is a **boundary protector** for that slice — it classifies what kinds of changes require what authority, but it is not itself part of the product surface.

---

## 2. Normative vocabulary

| Term | Definition |
|---|---|
| **ChangeClass** | The primary classification of a proposed change: one of `FIX`, `DECISION`, `MIGRATION`, `EXPANSION`, or `CLEANUP`. |
| **CleanupSemantics** | A secondary axis orthogonal to ChangeClass: `OPERATIONAL` (no semantic meaning change) or `SEMANTIC` (gate/contract meaning is altered). |
| **AuthorityDomain** | The decision-making domain that governs a change: `PRODUCT_CONTRACT`, `ARCHITECTURE`, `GOVERNANCE`, `DATA_MODEL`, `OPERATIONS`, or `IMPLEMENTATION`. |
| **RebaselineRequired** | Boolean predicate (see §5) that is `true` when a change demands a new canonical baseline. |
| **Baseline** | A ratified `audit_baseline_*.json` attestation produced by `--ratify`, representing a frozen snapshot of the registry at a point in time. |
| **ImpactClosure** | The canonical (declarative) minimum set of formal dependencies affected by a change (see §7). |
| **Ratification** | The existing procedure of running `--audit-dir-doc` → `--rerun` → `--ratify` to produce a RATIFIED baseline attestation (see §8). |

---

## 3. Change classification

### 3.1 ChangeClass and CleanupSemantics

```
ChangeClass := FIX | DECISION | MIGRATION | EXPANSION | CLEANUP
CleanupSemantics := OPERATIONAL | SEMANTIC   (separate axis)
Rule: CLEANUP ∧ SEMANTIC ⇒ MIGRATION and the same change-control applies
```

The `CleanupSemantics` dimension is independent of `ChangeClass`. A `CLEANUP` change that alters gate semantics (e.g., deleting a large bin/ output set whose removal changes what the gate considers "clean") is not a `CLEANUP` — it is a `MIGRATION` and must follow the `MIGRATION` change-control path.

**Example**: bulk-deleting a large unmanaged generated-artifact set under `bin/` (previously catalogued at ~1,046 artifacts by the directory-audit scan, DEBT#419 lineage) alters what the gate treats as "clean" — the semantic scope of tracked artifacts. That is `MIGRATION`, not `CLEANUP`, regardless of how "cleanup-like" the operation appears.

### 3.2 ChangeClass table

| ChangeClass | Meaning | Example |
|---|---|---|
| **FIX** | Defect removal that preserves existing contracts. | Correct a misclassified debt entry; fix a registry JSON schema violation. |
| **DECISION** | Policy or contract meaning decision. | Change a severity threshold in `config/audit_rules.json`; redefine a `BUDGET#` metric's derivation rule. |
| **MIGRATION** | Canonical identity or structure change. | Rename a `DEBT#` identifier; change the `debt_registry.json` schema version; bulk-delete entries that alter the gate's semantic scope. |
| **EXPANSION** | TCB or product scope enlargement. | Add a new gate runner to the trusted codebase; extend the product contract surface (e.g., add `ax status` as a primary command). |
| **CLEANUP** | Output artifact housekeeping (operational only). | Remove stale `tmp/audit_*` bundles; rotate `docs/audit/` reports; prune orphaned files that do not affect gate semantics. |

---

## 4. Authority matrix

| AuthorityDomain | decision_required | Typical trigger |
|---|---|---|
| `PRODUCT_CONTRACT` | Architect approval | Any change to `docs/spec/productization_contract.md` or the v1 CLI surface (`ax prove`, `ax report` exit codes, JSON schema). |
| `ARCHITECTURE` | Architect approval | Changes to `src/gate/runners/import_encapsulation_gate.nim`, `config.nims` importEncapsulation block, or `config/decision_binding.waiver.toml`. |
| `GOVERNANCE` | Architect approval | Changes to this document or the `data/debt_registry.json` schema/semantics. |
| `DATA_MODEL` | Architect approval | Changes to `data/debt_registry.json` entry structure, `data/debt_ledger.json` schema, or `config/policy/policy_revisions.json` structure. |
| `OPERATIONS` | Lead reviewer | Changes to `docs/history/audit_baseline_*.json` generation pipeline, `tmp/` bundle layout, or audit bundle tooling (`tools/debt_engine.nim` non-semantic changes). |
| `IMPLEMENTATION` | None (standard review) | Routine crash fixes, non-semantic bug fixes in `src/` that do not alter gate meaning or product contract. |

### Immutable files (AGENTS.md §-1)

The following files are **immutable without explicit human architect approval** — this is not a new authority but a direct reference to the existing absolute rule:

> "The following files are **immutable without explicit human architect approval**: `src/gate/runners/import_encapsulation_gate.nim` + `config.nims` importEncapsulation block, `.github/workflows/ci.yml`, `AGENTS.md`."
> — AGENTS.md §-1

(§-1 인용은 문서 작성 시점(2026-09-02) 기준. `ci.yml`은 CI=0 cutover, 2026-09-20로
AGENTS.md §-1 목록에서 제거·삭제됨 — 현행 §-1 보호 대상은 `import_encapsulation_gate.nim` +
`config.nims` importEncapsulation block + `AGENTS.md`.)

This document does **not** redefine or extend that list. It references it as the authoritative source. Any change to those files requires the human architect's explicit instruction; no authority matrix entry in this document overrides that requirement.

---

## 5. Rebaseline predicate

A single canonical predicate determines whether a new baseline is required:

```
RebaselineRequired :=
  canonicalIdentityChanged ∨
  policyRevisionChanged ∨
  contractChanged ∨
  authoritativeEvidenceChanged ∨
  scopeChanged
```

`RebaselineNotRequired := (RebaselineRequired = false)`. No independent negative rule is redeclared — drift prevention is handled by the absence of any positive condition.

| Identifier | Meaning (one line) |
|---|---|
| `canonicalIdentityChanged` | The canonical identity of a tracked entity (e.g., `DEBT#` identifier, `BUDGET#` metric name) has been added, removed, or renamed. |
| `policyRevisionChanged` | The `config/policy/policy_revisions.json` revision chain has a new patch that materially alters policy semantics. |
| `contractChanged` | The product contract (`docs/spec/productization_contract.md`) or this governance contract has been amended. |
| `authoritativeEvidenceChanged` | The authoritative evidence source (`data/debt_registry.json`) has been mutated in a way that changes what is asserted as true. |
| `scopeChanged` | The set of files, domains, or commands covered by the audit/tracking system has expanded or contracted. |

---

## 6. Baseline immutability

- A **ratified baseline** (`--ratify` output) is **append-only** — new baselines are added alongside existing ones; no baseline is ever overwritten or deleted.
- A successor baseline **must carry `parentBaselineId`** (lineage) linking it to its predecessor. The current storage structure (`docs/history/audit_baseline_*.json` as flat files) is unchanged — lineage is a logical attribute, not a storage-schema requirement.
- This declaration is consistent with the current state: `data/debt_registry.json` remains the SSOT, and baselines are projections of it, not replacements.

---

## 7. ImpactClosure

### 7.1 Canonical ImpactClosure (declarative)

`ImpactClosure` is the **canonical** (declarative) definition: the minimum set of formal dependencies that a change corrects within the formal dependency model. This model will be implemented as a static dependency graph in a future phase. **This section defines the term only; no graph structure is asserted yet.**

### 7.2 Current Operational Impact Chain (observed, not formal)

> **This chain is what is currently observed in the implementation. It is NOT the formal dependency graph.** The formal dependency graph is a future tool implementation target. Do not treat this observed chain as a static specification of formal dependencies.

The observed chain, verified from current code:

1. **Registry entry edit** — a change to `data/debt_registry.json` (the SSOT) is the entry point.
2. **`--validate` runs Part C checks** — `tools/debt_engine.nim` `cmdValidate()` executes:
   - **[3/6] Ledger ↔ Registry budget sync** (`checkLedgerRegistrySync`, `tools/debt_engine.nim:961-978`) — detects BUDGET# metric drift between the ledger and the registry's live open/closed counts.
   - **[4/6] Markdown ↔ Registry consistency** (`checkMarkdownSync`, `tools/debt_engine.nim:1029-1040`) — detects discrepancies between the registry and `docs/DEBT_REGISTRY.md` header counts (total entries, open count, closed count).
3. **Part D DRIFT** — `tools/debt_engine.nim:1137-1190` compares live evaluator projections against ledger committed values. Mismatches are reported as `DRIFT`.
4. **Part D.1 ERROR disposition** — `tools/debt_engine.nim:1213-1214` sets `hasErrorDisposition = true` when any metric has `disposition=ERROR` in `config/policy/policy_dispositions.json`. At `tools/debt_engine.nim:1323-1326`, this causes `quit(1)` — a **non-zero exit** that fails the validation run.
5. **Ratification VERIFY checks** — `bin/debt_engine --ratify` runs in-process verification (`tools/debt_engine.nim:3030-3150`):
   - VERIFY-01 (`tools/debt_engine.nim:2327-2376`): `input_digest` recomputation and manifest comparison.
   - VERIFY-02 (`tools/debt_engine.nim:2379-2411`): 4 canonical files digest comparison.
   - VERIFY-03a (`tools/debt_engine.nim:2416-2465`): `review_annotations` usage restricted to existence check.
   - VERIFY-03b (`tools/debt_engine.nim:2468-2512`): annotation removal → canonical outputs byte-identical.
   - VERIFY-04 (`tools/debt_engine.nim:2516-2596`): `new_debts` affected_paths ⊆ finding paths.
   - VERIFY-05 (`tools/debt_engine.nim:2603-2618`): report coverage (omission=0).
   - VERIFY-06 (`tools/debt_engine.nim:2622-2695`): registry files[] ⊆ canonical_findings paths.
   - VERIFY-07 (`tools/debt_engine.nim:2700-2711`): `--validate` in-process, passed==total.
   - VERIFY-08 (`tools/debt_engine.nim:2716-2744`): rerun/ subdir byte-identical to bundle.
   - VERIFY-09 (`tools/debt_engine.nim:2749-2841`): worktree vs pre-snapshot diff, approved set only.
   - Plus `report_counts.json` omission check (`tools/debt_engine.nim:3061-3070`).

On full VERIFY-01..09 pass, `--ratify` writes attestation to `baseline_manifest.json` (bundle dir) and `docs/history/audit_baseline_<date>.json` (`tools/debt_engine.nim:3137-3145`), with `"status": "RATIFIED"`.

---

## 8. Ratification

This section **documents the existing ratification procedure** — it does not invent a new one.

### 8.1 Procedure

The current ratification sequence is:

```
1. make audit-dir-doc                      # default: non-mutating dry-run (produces bundle in tmp/audit_20260817)
2. bin/debt_engine --audit-dir-doc --rerun # re-evaluates with frozen freeze_time; byte-diff canonical outputs
3. bin/debt_engine --ratify                # runs in-process VERIFY-01..09 + report_counts; writes attestation on full pass
```

Each step is mandatory and sequential:

- **Step 1** (`--audit-dir-doc`): The default invocation (no `--apply`, `--rerun`, or `--project-only` flag) is **non-mutating** — it produces the bundle and observations but does not write registry entries. Confirmed at `tools/debt_engine.nim:1939`: `## --audit-dir-doc full run (dry-run registry)`. Registry mutation requires `--apply` (`tools/debt_engine.nim:1940`).
- **Step 2** (`--audit-dir-doc --rerun`): Reuses the frozen `freeze_time` from the prior bundle's `meta.json`, re-evaluates all rules, and byte-compares the 4 canonical output files against the original bundle. Confirmed at `tools/debt_engine.nim:1941` and `tools/debt_engine.nim:2250-2277` (rerun branch).
- **Step 3** (`--ratify`): Runs all 10 in-process checks (VERIFY-01..09 + `report_counts.json` omission check). On full pass, writes the attestation with `"status": "RATIFIED"` to `baseline_manifest.json` and `docs/history/audit_baseline_<date>.json`. On any failure, exits `1` (`tools/debt_engine.nim:3056-3059, 3063-3070, 3150`).

### 8.2 What `--ratify` verifies (current scope)

`--ratify` performs 10 in-process checks (no external log parsing):

| Check | What it verifies | Location |
|---|---|---|
| VERIFY-01 | `input_digest` recomputation matches manifest | `tools/debt_engine.nim:2327-2376` |
| VERIFY-02 | 4 canonical files digest matches manifest | `tools/debt_engine.nim:2379-2411` |
| VERIFY-03a | `review_annotations` used only as existence check | `tools/debt_engine.nim:2416-2465` |
| VERIFY-03b | Annotation removal → canonical outputs byte-identical | `tools/debt_engine.nim:2468-2512` |
| VERIFY-04 | `new_debts` affected_paths ⊆ finding paths | `tools/debt_engine.nim:2516-2596` |
| VERIFY-05 | Report coverage: omission=0 | `tools/debt_engine.nim:2603-2618` |
| VERIFY-06 | Registry files[] ⊆ canonical_findings paths | `tools/debt_engine.nim:2622-2695` |
| VERIFY-07 | `--validate` in-process: passed==total | `tools/debt_engine.nim:2700-2711` |
| VERIFY-08 | Rerun outputs byte-identical to bundle | `tools/debt_engine.nim:2716-2744` |
| VERIFY-09 | Worktree vs pre-snapshot: no unapproved mutation | `tools/debt_engine.nim:2749-2841` |
| report_counts | `docs/audit/report_counts.json` omitted==0 | `tools/debt_engine.nim:3061-3070` |

All checks must pass for `--ratify` to write the attestation and exit `0` (`tools/debt_engine.nim:3147-3150`).

---

## 9. References and territory confirmation

### 9.1 Phase 2: machine-readable policy (deferred)

A `config/change_policy.json` or similar machine-readable policy file is **not introduced now**. Such a file is only justified when there is an actual machine consumer that requires deterministic policy parsing for decision-making. At that point, the relationship between this document (human-readable contract) and the JSON file (machine projection) must be decided — this document will not pre-declare that relationship. The current SSOT for policy is `config/policy/policy_revisions.json` (`config/policy/policy_revisions.json:1-5`), which is consumed by `tools/sync_policy.nim` and `tools/debt_engine.nim` for disposition resolution.

### 9.2 Target architecture (future)

The long-term target architecture is:

```
data/debt_registry.json (SSOT) → decision log → projection (baseline attestation)
```

This is aspirational. **The current SSOT is `data/debt_registry.json`** and this document does not change that. The registry remains the authoritative source of truth for all debt entries; baselines are projections of it, not replacements.

### 9.3 Determinism grounding (reference)

Nim's `std/json` preserves object key insertion order on parse and serialize — output ordering is caller-controlled, enabling deterministic canonical JSON when keys are sorted before serialization (`tools/debt_engine.nim:2117`). The `sha256String` function (`tools/sha256_native.nim:189`) provides a type-checked, pure SHA-256 implementation with no external dependencies, used throughout the codebase for canonical digest computation (`tools/debt_engine.nim:652-657`, `tools/hermetic_build.nim:559`). These stdlib properties are the determinism foundation for all audit projections and attestation digests.

### 9.4 Cross-references

- **AGENTS.md §-1**: Immutable file list (absolute rule).
- **`docs/spec/productization_contract.md`**: v1 product contract and vertical slice definition.
- **`docs/spec/audit_tooling_contract.md`**: Ratified SSOT for the `--audit-dir-doc` subsystem (VERIFY-01..09, `--ratify` pipeline).
- **`docs/spec/decision_binding_framework.md`**: Decision binding and governance linter framework.
- **`data/debt_registry.json`**: Canonical SSOT for debt entries.
- **`config/policy/policy_revisions.json`**: Policy revision chain SSOT.
- **`tools/debt_engine.nim`**: Implementation of audit, validate, and ratify commands.
