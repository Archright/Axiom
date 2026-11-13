# Repository State Model

**Status**: NORMATIVE  
**Created**: 2026-08-18  
**Version**: v1  
**Related**: AGENTS.md §5 SSOT Locations, `docs/spec/filesystem_contract.md`, `docs/spec/hermetic_gate_framework.md`

---

## Overview

This document defines the **Repository State Model** — a four-class taxonomy governing every artifact within the Axiom repository tree. It establishes what constitutes canonical input, how derived artifacts are produced, which items participate in canonical execution semantics, and where external inputs enter the system.

The model serves three purposes:

1. **Classification** — Every artifact receives exactly one class assignment.
2. **Persistence Policy** — Independent of class, each artifact receives a persistence directive (TRACKED / IGNORED / REGENERATED).
3. **Invariant Enforcement** — Clean checkout, canonical path uniqueness, and closed execution boundaries derive from this model.

### Classification Axes

Two independent axes govern artifact classification:

| Axis | Values | Purpose |
|------|--------|---------|
| **Class** | CANONICAL · DERIVED · EPHEMERAL · EXTERNAL | Semantic role in canonical execution |
| **Persistence** | TRACKED · IGNORED · REGENERATED | Git lifecycle and disk presence policy |

Persistence is NOT a subclass of Class. The same Class may map to different Persistence values depending on artifact identity. Each artifact receives an explicit pair `(class, persistence)` — never inferred from directory membership alone.

---

## §1. Classification Definitions

### 1.1 CANONICAL

Meaningful input representing approved, stable state. Requirements:

- Exactly one authoritative identity (single source of truth).
- Reproducible and auditable — any consumer can verify the artifact matches its canonical form.
- Not necessarily tracked in git; "canonical" describes semantic authority, not git mechanics.

Canonical artifacts define the input space for deterministic verification. Any deviation from canonical form invalidates reproducibility guarantees.

### 1.2 DERIVED

Produced deterministically from CANONICAL input via a declared process. Requirements:

- The regeneration procedure (command + arguments + input sources) MUST be documented alongside the artifact.
- Given identical CANONICAL inputs and the declared process, output must be bit-for-bit reproducible.
- Derivation chain is traceable: DERIVED → CANONICAL(s) → ... → root canonical inputs.

### 1.3 EPHEMERAL

Generated during execution lifecycle. Characteristics:

- Does NOT participate in canonical semantics.
- Exists only for the duration of runtime operations.
- Discarding and regenerating carries no correctness impact.
- May improve performance but cannot alter verification outcomes.

### 1.4 EXTERNAL

Supplied from outside the repository tree with precise identity (version, hash, or equivalent). Sub-classified by provenance:

| Sub-class | Description | Examples |
|-----------|-------------|----------|
| PRODUCT_DEPENDENCY | Third-party binary/library fetched by the project with hash verification | Z3 solver (`vendor/z3`) |
| ENVIRONMENT_DEPENDENCY | Toolchain/runtime installed by the user in standard locations | Lean 4.x, elan, Nim 2.2.10, `~/.cache/nim` |

External artifacts are NOT stored in the repository tree (unless explicitly exempted). Their identity is verified at fetch/install time, not committed to git.

---

## §2. Artifact Classification Table

Each row specifies `(class, persistence)` for a concrete artifact or well-defined group. Directory-level shorthand is avoided — classification is per-artifact.

| Artifact / Path | Class | Persistence | Rationale |
|-----------------|-------|-------------|-----------|
| `src/**/*.nim` (all source modules) | CANONICAL | TRACKED | Primary semantic input |
| `tests/**/*.feature`, `tests/**/*.nim` | CANONICAL | TRACKED | Business scenarios and test harnesses |
| `config/*.json`, `config/*.toml`, `config/*.nims` | CANONICAL | TRACKED | Policy, thresholds, gate definitions |
| `config/policy/**/*` | CANONICAL | TRACKED | Policy rules |
| `config/templates/**/*` | CANONICAL | TRACKED | Template definitions |
| `data/baseline.json` | CANONICAL | TRACKED | Baseline measurements (canonical computed value) |
| `data/universe_merkle.lock` | CANONICAL | TRACKED | Universe lock — single canonical path (§4) |
| `data/debt_registry.json` | CANONICAL | TRACKED | Debt registry |
| `data/artifacts/**/*` (golden/reference) | CANONICAL | TRACKED | Reference fixtures |
| `data/scenarios/**/*` | CANONICAL | TRACKED | Scenario definitions |
| `data/readiness/**/*` | CANONICAL | TRACKED | Readiness evidence |
| `data/reports/**/*` | CANONICAL | TRACKED | Generated reports (see §2.4) |
| `data/history/**/*` | CANONICAL | TRACKED | Historical records |
| `data/i18n/**/*` | CANONICAL | TRACKED | Localization data |
| `data/benchmarks/**/*` | CANONICAL | TRACKED | Benchmark definitions |
| `data/golden/**/*` | CANONICAL | TRACKED | Golden reference outputs |
| `data/archive/**/*` | CANONICAL | TRACKED | Archived evidence |
| `data/debt/**/*` | CANONICAL | TRACKED | Debt records |
| `docs/**/*.md` | CANONICAL | TRACKED | All specifications, guides, ADRs |
| `docs/spec/certified_patterns/**/*` | CANONICAL | TRACKED | Lean 4 verified patterns |
| `AGENTS.md`, `axiom.nimble`, `axiom.lock` | CANONICAL | TRACKED | Project metadata |
| `.github/workflows/*.yml` | CANONICAL | TRACKED | CI pipeline definitions — **RETIRED** (CI=0 cutover, 2026-09-20로 디렉터리 제거, 빈 상태) |
| `.github/**/*` | CANONICAL | TRACKED | GitHub configuration |
| `.gitignore`, `.editorconfig`, `.gitattributes` | CANONICAL | TRACKED | Repository-level config |
| `README.md` | CANONICAL | TRACKED | Project documentation |
| `src/.axiom_raises_probe/**/*` | CANONICAL | TRACKED | Probe fixtures |
| `proofs/GateInvariants/**/*` | CANONICAL | TRACKED | Formal proofs |
| `proofs/Generated/**/*` | CANONICAL | TRACKED | Generated proof artifacts |
| `proofs/IR/**/*` | CANONICAL | TRACKED | IR proofs |
| `proofs/*.lean`, `proofs/lake-manifest.json` | CANONICAL | TRACKED | Lean proof sources |
| `vendor/ed25519/**/*` | CANONICAL | TRACKED | Internal crypto library (no .git submodule) |
| `bin/ax*`, `bin/*_test` (compiled binaries) | DERIVED | IGNORED (REGENERATED) | Build outputs; regenerate via `nim c` |
| `build/aot_runner_test`, `build/ax_probe`, etc. | DERIVED | IGNORED (REGENERATED) | Compiled test/probe binaries |
| `build/nimcache/**/*` | DERIVED | IGNORED | Nim compiler cache |
| `build/certificates/**/*` | DERIVED | IGNORED | Certificate artifacts |
| `build/.aot_cache/**/*` | DERIVED | IGNORED | AOT compilation cache |
| `build/nimcache_pool/**/*` | DERIVED | IGNORED | Pool cache |
| `logs/**/*` | EPHEMERAL | IGNORED | Runtime logs (see §3.2 log rule) |
| `logs/ax_proof_state.json` | EPHEMERAL | IGNORED | Proof state snapshot |
| `logs/ax_prove_trajectory.jsonl` | EPHEMERAL | IGNORED | Prove trajectory log |
| `logs/global_symbol_graph.json` | EPHEMERAL | IGNORED | Symbol graph |
| `logs/hardening_audit.jsonl` | EPHEMERAL | IGNORED | Audit trail |
| `logs/lean_lsp_payloads.jsonl` | EPHEMERAL | IGNORED | LSP payload log |
| `logs/sim/**/*` | EPHEMERAL | IGNORED | Simulation logs |
| `logs/staged_certs/**/*` | EPHEMERAL | IGNORED | Staged certificates |
| `logs/evidence/**/*` | EPHEMERAL | IGNORED | Evidence logs |
| `logs/proof_vault/**/*` | EPHEMERAL | IGNORED | Proof vault logs |
| `.cache/**/*` | EPHEMERAL | IGNORED | Application cache |
| `.config/**/*` | EPHEMERAL | IGNORED | Runtime configuration cache |
| `.opencode/**/*` | EPHEMERAL | IGNORED | Editor session state |
| `.axiom/**/*` | EPHEMERAL | IGNORED | Runtime axiom state |
| `vendor/z3/**/*` | EXTERNAL / PRODUCT_DEPENDENCY | IGNORED | Z3 binary; fetch+hash verify at provision time. Tree absence permitted. |
| `~/.elan/**/*` | EXTERNAL / ENVIRONMENT_DEPENDENCY | N/A | Elan installer (user-local) |
| `~/.local/bin/z3` | EXTERNAL / ENVIRONMENT_DEPENDENCY | N/A | Z3 binary in PATH (user-local) |
| `~/.cache/nim/**/*` | EXTERNAL / ENVIRONMENT_DEPENDENCY | N/A | Nim compiler cache (user-local) |
| `~/.choosenim/**/*` | EXTERNAL / ENVIRONMENT_DEPENDENCY | N/A | Choosenim toolchain manager (user-local) |

### §2.4 Notes on Specific Artifacts

**`data/reports/`**: Reports are CANONICAL because they represent committed measurement outcomes. They are generated from canonical inputs via documented procedures, placing them conceptually in a `canonical/generated` sub-category — but classification remains CANONICAL regardless of generation method.

**`data/universe_merkle.lock`**: Single canonical path for universe merkle state. No legacy variants at repository root. See §4.

**`vendor/ed25519/`**: Classified as CANONICAL because it is an internal cryptographic library maintained directly in-tree. Unlike `vendor/z3`, it does NOT use a `.git` submodule — changes are committed directly. This is intentional: ed25519 correctness is part of Axiom's trust boundary.

**`vendor/z3/`**: Classified as EXTERNAL/PRODUCT_DEPENDENCY. The directory may be absent; Z3 is fetched and verified at provision time. Hash verification is mandatory.

---

## §3. Persistence Policies

Persistence operates independently of Class. Three policies exist:

### 3.1 TRACKED

Artifact is committed to git. Changes require review. Represents stable, reviewed state.

### 3.2 IGNORED

Artifact is listed in `.gitignore` (or equivalent exclusion mechanism). Never committed.

**Critical Rule — `logs/**` Exclusion**: The glob pattern `logs/**` MUST NEVER appear in any `.gitignore` exception or tracked-artifact whitelist. No file under `logs/` shall ever be tracked, regardless of name or content. This is a hard invariant — violation = gate failure.

### 3.3 REGENERATED

DERIVED artifacts that are IGNORED but expected to be regenerated on demand. The regeneration command MUST be documented at the artifact's location or in the consuming module's docstring.

Example: `build/validator_test` → regenerate via `nim c -r build/validator_test` (or equivalent build target).

---

## §4. Canonical Path Uniqueness

Every canonical artifact has exactly ONE authoritative path in the repository tree. Duplicate paths for the same logical entity are prohibited.

| Logical Entity | Canonical Path | Legacy Paths |
|----------------|---------------|--------------|
| Universe merkle lock | `data/universe_merkle.lock` | None permitted at root |
| Baseline measurements | `data/baseline.json` | — |
| Debt registry | `data/debt_registry.json` | — |
| Gate topology spec | `src/gate/topology_spec.nim` | — |
| Environment variable enum | `src/core/trusted/env_types.nim` | — |

**Rule**: If a new path is needed for an existing logical entity, the old path MUST be migrated atomically. No coexistence period.

---

## §5. Clean Checkout Invariant

A fresh checkout of the repository MUST satisfy the following sequence to reach a fully operational state:

```
fresh checkout
    │
    ▼
1. Provision product dependencies
   └─► Fetch Z3 binary, verify hash against known-good value
       Command: tools/z3_precache.nim (or documented equivalent)
    │
    ▼
2. Validate environment contract
   └─► Nim 2.2.10+ available (via choosenim or NIM_EXE)
   └─► Lean 4.29+ available (via elan)
   └─► Z3 4.13+ accessible (via Z3_PATH or vendor/z3)
   └─► AXIOM_ROOT set and pointing to repository root
    │
    ▼
3. Validate layout and topology
   └─► Canonical paths exist (src/, config/, data/, docs/)
   └─► No unexpected files at canonical paths (uniqueness check)
   └─► .git/index present (repository integrity)
    │
    ▼
4. Canonical execution
   └─► Run gate suite: `axiom-gate commit` or equivalent
   └─► Verify deterministic output against baseline
    │
    ▼
5. Deterministic result
   └─► Verification result matches expected projection
   └─► Evidence artifacts produced in canonical locations
```

Failure at any step halts the invariant. Partial success does not satisfy the invariant.

---

## §6. Closed Execution Boundary

```
┌──────────────────────────────────────────────────────────────┐
│                    Repository Tree                           │
│                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐  │
│  │ State Model │───►│ Topology     │───►│ Dependency     │  │
│  │ (this doc)  │    │ Contract     │    │ Identity       │  │
│  └─────────────┘    └──────────────┘    └────────────────┘  │
│                            │                    │            │
│                            ▼                    ▼            │
│                     ┌──────────────┐    ┌────────────────┐  │
│                     │ Environment  │◄───│ External       │  │
│                     │ Contract     │    │ Inputs         │  │
│                     └──────────────┘    └────────────────┘  │
│                            │                                │
│                            ▼                                │
│                     ┌──────────────┐                         │
│                     │ Execution    │                         │
│                     │ (gates,      │                         │
│                     │  prove,      │                         │
│                     │  report)     │                         │
│                     └──────────────┘                         │
│                            │                                │
│                            ▼                                │
│                     ┌──────────────┐                         │
│                     │ Evidence     │                         │
│                     │ (certs,      │                         │
│                     │  logs,       │                         │
│                     │  trajectory) │                         │
│                     └──────────────┘                         │
└──────────────────────────────────────────────────────────────┘
```

All inputs flow from left to right. No backward edges. Evidence is terminal — it does not feed back into execution as input (evidence is output, not input).

---

## §7. Artifact Identity Manifest (Recommended Practice)

For complex projects with many artifacts, maintain an **artifact identity manifest** — a structured record with three fields per entry:

| Field | Type | Description |
|-------|------|-------------|
| `state_class` | string | One of: CANONICAL, DERIVED, EPHEMERAL, EXTERNAL |
| `persistence` | string | One of: TRACKED, IGNORED, REGENERATED |
| `authority` | string | Path to the canonical definition or procuring command |

This manifest is advisory (not machine-enforced) but recommended for auditability. Entries should be added when new artifact categories are introduced.

---

## §8. Prohibited Patterns

### 8.1 Partial/Partial-Set Shorthand

Expressions like "`src/ (some files)`", "`docs/ (except X)`", or "`data/ (mostly)`" are PROHIBITED. Classification is per-artifact, not per-directory. When a directory contains mixed-class artifacts, each artifact MUST be individually classified.

### 8.2 Implicit Inference from Directory Name

Directory membership does NOT imply class. `build/` artifacts are DERIVED, `logs/` artifacts are EPHEMERAL — but this is defined by this document, not by convention. Consumers MUST reference this document, not infer from path heuristics.

### 8.3 Coexistence of Canonical Paths

See §4. No dual paths for the same logical entity. Migration is atomic.
