# Change Manifest Contract

**Status**: Normative contract declaration (plan-approved 2026-08-30)
**Created**: 2026-08-30
**Related**: `docs/spec/change_governance_contract.md`, `docs/spec/manifest_atomicity.md`, `AGENTS.md` §-1

---

## 1. Purpose / Scope

This document declares the **normative schema for distributed change manifests** in the Axiom repository. It defines the structure of a change identity document and the rules for composing manifests into a DAG. It is a schema contract **declaration only** — it does not implement a validator or a DAG engine.

This document complements two existing contracts without duplicating them:

- **`docs/spec/change_governance_contract.md`** — governs *what kind of change* a manifest entry represents (ChangeClass, authority, rebaseline). This document governs *how manifest entries are structured and composed*. The two documents share no overlapping schema definitions.
- **`docs/spec/manifest_atomicity.md`** — governs the *write pattern* for `feature_manifest.json` (temp+fsync+rename). This document governs the *content schema* for `config/changes/*.toml`. The atomic write pattern applies to manifest files by physical convention but is out of scope for this contract's semantic definitions.

### What this document does NOT do (SHALL NOT)

- **Implement a validator or DAG engine.** This document is a schema declaration, not executable logic.
- **Duplicate ChangeClass or authority definitions.** Those live in `change_governance_contract.md` §3 and §4. This document references them only for context.
- **Define a new product feature.** This document is a **guardrail** for the CI-optimization vertical slice; it is not itself part of the product surface.
- **Define atomic write semantics.** The temp+fsync+rename pattern is the concern of `manifest_atomicity.md` and remains unchanged.

---

## 2. Identity Model: PR / Commit / Change

The manifest schema operates on a **three-tier identity model** that must not be conflated:

| Tier | Meaning | Manifest Role |
|---|---|---|
| **PR** (Pull Request) | Transport mechanism — the carrier that moves a change through review. Transient, repository-scoped, numeric ID. | **Never appears in a manifest.** PR numbers are transport addresses, not stable change identities. |
| **Commit** | Implementation record — a specific snapshot of code changes in the Git DAG. Identified by SHA-256 OID. Immutable but replaceable (force-push, rebase). | Appears only in `base_commit` as **observational/diagnostic/validation metadata**. It is not a stable identity, not a dependency reference, and not a dependency key. |
| **Change** | Semantic identity — the conceptual unit of work that persists across PRs and commits. Stable, human-meaningful, repository-scoped. | **The primary key of a manifest entry.** Identified by `id` (a stable string). Dependencies reference changes by `id` only. |

**Invariant**: `depends_on` references stable change identity (`id`) only. PR numbers and commit SHAs are **forbidden** as dependency targets. Violation = validator rejection (fail-closed).

---

## 3. Manifest Schema

### 3.1 Schema Definition

Each change manifest is a TOML document located at `config/changes/<change-id>.toml`. The `<change-id>` filename matches the `id` field (convention, not enforced by this schema — the validator enforces it).

```toml
[id]           string        — stable change identity (required)
[base_ref]     string        — the branch or ref this change targets (required)
[base_commit]  string        — OBSERVATIONAL ONLY: the commit OID at the time of manifest creation. Diagnostic/validation metadata. NOT a stable identity. (required)
[semantic_surface]  array of strings — the set of semantic surfaces this change touches. Each entry is a surface token. (required)
[depends_on]   array of strings — stable change `id` values only. No PR numbers, no commit SHAs. Empty array means no dependencies. (required)
[conflicts_with] array of strings — stable change `id` values that cannot coexist with this change. See §4 for semantics. (required)
```

### 3.2 Field Semantics

#### `id`

The stable change identity. A string that is unique within the manifest directory (`config/changes/`). Conventionally short, descriptive, and stable across PRs and commits. Examples: `ci-runner-pool`, `merge-boundary-foundation`, `ci-v6-validation`, `merge-gate-controller`.

This is the **only** field used as a dependency or conflict target. It is the anchor of the DAG.

#### `base_ref`

The branch or ref this change is declared against. For CI-optimization manifests, this is typically `main`. For feature branches, it is the target branch name. This field is **observational** — it does not gate or enforce anything by itself.

#### `base_commit`

The Git commit OID (SHA-1 or SHA-256) observed at manifest creation time. This field is **strictly diagnostic/validation metadata**:

- It allows a validator to detect stale manifests (commit OID no longer on the target branch).
- It does **NOT** serve as a dependency key, a conflict key, or a stable identity.
- It does **NOT** participate in DAG composition.
- A manifest without a valid `base_commit` is still structurally valid but may be flagged as stale by the validator.

This follows the same observational-purpose discipline as `base_ref` but is more volatile (commits rotate; refs are more stable).

#### `semantic_surface`

An array of surface tokens representing the semantic concepts this change touches. Surface tokens are opaque strings — the manifest does not define a controlled vocabulary, but the validator may enforce token naming conventions. Examples: `ci-trigger`, `runner-infrastructure`, `merge-controller`, `merge-boundary`, `push-trigger`.

The surface set is used for:
1. **Conflict detection** — two changes with overlapping `semantic_surface` entries that list each other in `conflicts_with` are detected by the validator.
2. **Dependency inference** — a change whose `semantic_surface` intersects with another's may be inferred as a dependency, but this inference is advisory only; explicit `depends_on` is authoritative.

#### `depends_on`

An array of stable change `id` values that this change depends on. The dependency relationship is a **precedence constraint**: the depended-on change must be acknowledged (ratified/validated) before this change can be validated.

**Rules**:
- Only stable change `id` values are permitted. PR numbers (e.g., `14`), commit SHA fragments (e.g., `abc123`), and other non-`id` references are **forbidden**. A validator encountering such a reference must reject the manifest (fail-closed).
- The empty array `[]` is valid and means the change has no dependencies.
- Circular dependencies are detected by the validator as a DAG composition error (fail-closed).
- `depends_on` ≠ `conflicts_with`. A dependency is a precedence constraint; a conflict is a coexistence prohibition. See §4.

#### `conflicts_with`

An array of stable change `id` values that are **semantically incompatible** with this change. The conflict relationship means:

- **Simultaneous coexistence is impossible**: both changes cannot be applied to the same codebase state.
- **Surface overlap**: the two changes touch the same `semantic_surface` tokens in a way that creates incompatibility.
- **Ordering requirement**: the two changes must not be applied in either order — one must come before the other, or they must be mutually exclusive.
- **Semantics collision**: the semantic effects of the two changes would produce contradictory or undefined behavior.

**Explicit semantics of `conflicts_with`**:
1. **conflict is NOT dependency.** A change listed in `conflicts_with` is NOT a dependency. The two changes are mutually exclusive, not sequentially ordered.
2. If change X declares `conflicts_with = [Y]` and change Y declares `depends_on = [X]`, the validator must reject both manifests — a change cannot both conflict with and depend on the same change. This is a fail-closed inconsistency.
3. Symmetry is NOT required: `A conflicts_with B` does not imply `B conflicts_with A` in the schema, but the validator MUST treat the relationship as symmetric for DAG composition purposes.
4. Conflicts are resolved by the authority matrix (see `change_governance_contract.md` §4), not by the manifest schema itself. The manifest records the conflict; the governance layer decides resolution.

---

## 4. Distributed Manifest Convention

### 4.1 File Location

Manifests live at `config/changes/<change-id>.toml`. The directory `config/changes/` is the manifest root.

### 4.2 Composition

The manifest set is composed by **directory enumeration**: the validator scans `config/changes/*.toml`, parses each file, and builds a DAG from the `depends_on` and `conflicts_with` edges.

```
config/changes/
├── ci-runner-pool.toml
├── merge-gate.toml
├── change-A.toml
└── change-B.toml
```

The DAG is:
- **Nodes**: manifest entries, keyed by `id`.
- **Edges**: `depends_on` → precedence edges; `conflicts_with` → exclusion edges.
- **Validation**: the validator checks for (a) unknown IDs referenced in `depends_on` or `conflicts_with`, (b) cycles in the `depends_on` graph, (c) self-conflict (an `id` listing itself), and (d) conflict-dependency inconsistency (`depends_on` and `conflicts_with` sharing an entry).

### 4.3 TOML-per-Entity Precedent

This document follows the existing project precedent of one-TOML-per-entity in the `config/` tree (e.g., `config/gates.manifest.toml`, `config/decision_binding.waiver.toml`, `config/gates.waiver.toml`). The `config/changes/` directory extends this convention to change manifests.

---

## 5. Fail-Closed Design

The manifest schema is **fail-closed** by design:

| Condition | Validator Behavior |
|---|---|
| Unknown `id` referenced in `depends_on` or `conflicts_with` | REJECT — manifest is invalid |
| Cycle detected in `depends_on` graph | REJECT — manifests are invalid |
| Self-reference in `depends_on` or `conflicts_with` (`id` depends on or conflicts with itself) | REJECT — manifest is invalid |
| `depends_on` and `conflicts_with` share an entry (same `id` in both arrays) | REJECT — manifest is invalid |
| `base_commit` is not a valid hex OID | WARN — manifest is structurally valid but flagged as stale |
| `base_ref` does not match any known branch | WARN — manifest is structurally valid but flagged |
| `semantic_surface` is empty | WARN — manifest is structurally valid but may be incomplete |

**Key design principle**: The manifest schema itself does not enforce or prevent cycles, unknown IDs, or conflicts — it defines the rules. The **validator** is responsible for enforcing them. The schema defines what is valid; the validator decides what passes. Unknown or cyclic manifests are rejected, not silently ignored.

---

## 6. References

- **`docs/spec/change_governance_contract.md`**: Change classification (ChangeClass, CleanupSemantics), authority matrix, rebaseline predicate, ImpactClosure, ratification procedure. The manifest schema does not redefine any of these concepts.
- **`docs/spec/manifest_atomicity.md`**: Atomic write pattern (temp+fsync+rename) for `feature_manifest.json`. The manifest schema does not define write patterns; the atomic write convention applies to all `config/` TOML files by project convention.
- **AGENTS.md §-1**: Immutable files and absolute rules. The manifest schema does not modify any immutable file.
- **AGENTS.md §0.5c**: Debt and quirk markers. This document does not introduce any debt markers.
- **`docs/spec/productization_contract.md`**: v1 product contract. This document is a guardrail, not a product feature.
- **`tools/readiness_evaluator.nim`**: Readiness evaluation logic. The manifest schema does not interact with readiness evaluation.
- **`config/` convention**: One TOML per entity in the `config/` directory tree.
