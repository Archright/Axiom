# SSOT Registry Unification (DEBT#256)

**Status**: Analysis Complete — Validation Invariants Proposed  
**Date**: 2026-07-05  
**Related**: DEBT#256, AGENTS.md §0.3 (SSOT), AGENTS.md §0.4b (Skills SSOT)

---

## 1. Current State — Three Orthogonal Registries

The Axiom verification engine maintains three data-layer registries that serve distinct purposes. They are **NOT duplicates** — they are orthogonal concerns. The "dispersal" issue is the absence of compile-time cross-validation between them.

### 1.1 `data/axiom_registry.json` — Formal Axiom Definitions

**Purpose**: Z3 sort declarations + Lean theorem bindings for Nim types.  
**Schema**: `axiomId`, `nimSymbol`, `leanTheorem`, `leanType`, `nimSignature`, `leanSignature`, `axiomVersion`, `proofObligation`, `verified`, `sourceHash`, `leanTheoremSource`, `category`  
**Entries**: 30 (7 categories: acLengthNonNeg, acTypeCoercion, acArithmetic, acMemory, acEffectIsolation, acLogicOperator, acContainerOps)  
**Consumers**: `src/core/boundary/axiom_registry_loader.nim` (runtime loader), Lean proof pipeline, Z3 BMC solver  
**Role**: Canonical mapping from Nim stdlib symbols → formal verification artifacts (Z3 sorts + Lean theorems)

### 1.2 `data/axiom_catalog.json` — Verified Axiom-to-Nim Symbol Mappings

**Purpose**: Z3 sort declarations and Lean theorem definitions grouped by type name.  
**Schema**: `version`, `entries[].typeName`, `entries[].tier`, `entries[].sortDecl`, `entries[].axioms[].name`, `entries[].axioms[].formula`, `entries[].axioms[].lean`  
**Entries**: 2 type entries (JsonNode, string) with nested axiom arrays  
**Consumers**: `src/core/boundary/abstract_spec_registry.nim` (in-memory type→SMT lowering), `src/core/boundary/axiom_consistency_checker.nim` (cross-validation)  
**Role**: SMT-level type catalog — defines how Nim types map to Z3 sorts and what Lean theorems apply

### 1.3 `data/domain_layout.json` — Architecture Layer Definitions

**Purpose**: Domain-layer DAG matrix for architecture guard enforcement.  
**Schema**: `layers` (5 layers: L0→L4 with allowed_deps), `domains` (21 domains with import_path, layer, owner)  
**Consumers**: `src/core/trusted/architecture_invariants.nim` (compile-time guard), `config/strict.nims` (Invariant 9 cross-layer enforcement), `src/gate/runners/` (runtime gate checks)  
**Role**: Canonical source for import dependency rules — which layers can import which

### 1.4 Code-Level Registries (Indirection Layer)

| Module | Role | Relation to Data Registries |
|--------|------|----------------------------|
| `src/core/boundary/axiom_registry_loader.nim` | Runtime loader for `axiom_registry.json` | Reads 1.1 at runtime, provides typed access |
| `src/core/boundary/abstract_spec_registry.nim` | In-memory type→SMT lowering | Reads 1.2, provides compile-time type mapping |
| `src/core/boundary/axiom_consistency_checker.nim` | Cross-checks registry vs catalog | Validates 1.1 ↔ 1.2 consistency |

---

## 2. Overlap Analysis

### 2.1 overlap: axiomId ↔ typeName

`axiom_registry.json` entries have `axiomId` fields like `nim.string.len.isNat`, `nim.int.iso.lean.int`.  
`axiom_catalog.json` entries have `typeName` fields like `string`, `JsonNode`.

**Overlap**: Both reference the same Nim types (e.g., `string`) but at different abstraction levels:
- Registry: per-symbol mapping (30 individual symbols)
- Catalog: per-type grouping (2 types with multiple axioms each)

**No duplication**: They serve different consumers. Registry feeds the Lean proof pipeline; catalog feeds the SMT solver.

### 2.2 Gap: No Cross-Validation

The critical gap is that **no build-time check verifies consistency between the three registries**:

1. `axiom_registry.json` could reference a `nimSymbol` that doesn't exist in the Nim stdlib
2. `axiom_catalog.json` could define a `sortDecl` that conflicts with `axiom_registry.json`
3. `domain_layout.json` could define an `import_path` that doesn't match actual `src/` structure
4. Code-level registries could load stale data without any staleness detection

### 2.3 Cross-Reference Opportunities

- `axiom_registry.json` → `axiom_catalog.json`: Verify that every `leanTheorem` in the catalog has a corresponding entry in the registry
- `axiom_catalog.json` → `axiom_registry.json`: Verify that every `typeName` in the registry has a corresponding sort declaration in the catalog
- `domain_layout.json` → `src/`: Verify that every `import_path` resolves to an actual directory

---

## 3. Proposed Unification Strategy

### 3.1 No Merge Required

These registries should **NOT** be merged into a single file. They serve different consumers, have different update frequencies, and have different validation requirements:

| Registry | Update Frequency | Consumer | Validation |
|----------|-----------------|----------|------------|
| `axiom_registry.json` | Per-proof addition | Lean pipeline | Compile-time hash check |
| `axiom_catalog.json` | Per-type addition | SMT solver | Compile-time schema check |
| `domain_layout.json` | Per-architecture change | Import guard | Compile-time path check |

### 3.2 Unification via Validation Layer

Instead of merging files, unify through a **compile-time validation gate** that cross-checks all three:

```
┌─────────────────────────────────────────────────┐
│              config/strict.nims                  │
│         (Invariant 13: Registry Coherence)       │
│                                                  │
│  1. Load data/axiom_registry.json               │
│  2. Load data/axiom_catalog.json                │
│  3. Load data/domain_layout.json                │
│  4. Cross-validate:                              │
│     a. Every catalog typeName has ≥1 registry   │
│        entry with matching nimSymbol prefix     │
│     b. Every registry leanTheorem appears in    │
│        at least one catalog axiom               │
│     c. Every domain_layout import_path exists   │
│     d. No orphaned entries in either registry   │
│  5. Fail build if any check fails               │
└─────────────────────────────────────────────────┘
```

---

## 4. Proposed Validation Invariants (for `config/strict.nims`)

### Invariant 13: Registry Coherence Check

**Location**: `config/strict.nims`, inside `when defined(axiomStrict):` block  
**Trigger**: Every `nim c` with `-d:axiomStrict` (activated by `-d:axiom_gateway_build`)  
**Scope**: `data/axiom_registry.json`, `data/axiom_catalog.json`, `data/domain_layout.json`

**Checks**:

1. **Schema Validation**: Each registry file conforms to its declared schema version
2. **Cross-Registry Referential Integrity**: 
   - Every `typeName` in `axiom_catalog.json` has ≥1 corresponding `nimSymbol` prefix in `axiom_registry.json`
   - Every `leanTheorem` in `axiom_registry.json` has a matching definition in `axiom_catalog.json`
3. **Path Existence**: Every `import_path` in `domain_layout.json` resolves to an existing `src/` directory
4. **No Orphaned Entries**: No entry in any registry references a Nim symbol that doesn't exist in the codebase

**Implementation Pattern** (NimScript):

```nim
# ── Invariant 13: Registry Coherence ──
# Cross-validates axiom_registry.json, axiom_catalog.json, and domain_layout.json
# to ensure no stale or inconsistent entries.
block:
  # Load and parse all three registries
  # Cross-validate referential integrity
  # Fail build if any check fails
```

### Invariant 14: Domain Layout Path Check

**Location**: `config/strict.nims`, inside `when defined(axiomStrict):` block  
**Trigger**: Every `nim c` with `-d:axiomStrict`  
**Scope**: `data/domain_layout.json` → `src/`

**Checks**:

1. Every `domains[].import_path` resolves to an existing directory under `src/`
2. No `src/` directory exists that isn't listed in `domain_layout.json`
3. `layers[].allowed_deps` references only defined layer names

---

## 5. CI Wiring

The gorge/staticExec ban (Invariant 11) and the proposed registry coherence checks (Invariants 13-14) require `-d:axiomStrict` to activate. The CI build must include this flag.

**Current Gap**: `.circleci/continue.yml` builds `bin/axiom` with `nim c -d:release` — no `-d:axiom_gateway_build`.

**Required Change**: Add `-d:axiom_gateway_build` to the CI build command in the `quality-audit` job:

```yaml
# Before:
command: "nim c -d:release -o:bin/axiom src/cli/main.nim"
# After:
command: "nim c -d:release -d:axiom_gateway_build -o:bin/axiom src/cli/main.nim"
```

This activates all architecture invariants including the gorge ban and the new registry coherence checks.

---

## 6. Migration Roadmap

| Phase | Action | Effort |
|-------|--------|--------|
| Phase 1 | Wire `-d:axiom_gateway_build` into CI build | ✅ Done |
| Phase 2 | Implement Invariant 13 (Registry Coherence) in `config/strict.nims` | 1 day |
| Phase 3 | Implement Invariant 14 (Domain Layout Path Check) | 0.5 day |
| Phase 4 | Add `data/debt_registry.json` entry for tracking | 0.5 day |
| Phase 5 | Update AGENTS.md §1 with registry validation policy | 0.5 day |

---

## 7. Summary

The three registries are **orthogonal concerns** that should remain separate files. Unification is achieved through a **validation layer** (Invariants 13-14) that cross-checks consistency at compile time, rather than through file merging. The CI must activate `-d:axiom_gateway_build` to ensure these checks run on every build.
