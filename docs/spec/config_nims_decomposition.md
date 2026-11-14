# config.nims Decomposition

## Overview

`config.nims` is decomposed into modular `config/*.nims` includes for maintainability. This document describes the task structure, hermetic pre-build blocks, and import encapsulation configuration.

## Include Order

The canonical include order in `config.nims`:

1. `config/paths.nims` — Build metadata, dependency injection, path switches
2. `config/lint.nims` — Import boundary lint
3. `config/effects.nims` — Compilation flags, warnings, effect system config
4. `config/strict.nims` — Strict mode, architecture invariants
5. `config/integrity.nims` — Immutable verification, merkle root, constraints
6. `config/vendors.nims` — Hermetic build, Z3 FFI, source scanner

## Task Structure

config.nims defines the following tasks via `task name, "description":`:

- `buildGateRunners` — Gate runner freshness check & gate binary build via external `sha256sum` (one `gorge()` call). `computeSourceHash(path)` concatenates the SHA-256 digests of the runner source plus the shared gate-infrastructure set for up-to-date detection; `.axiom/cache/binary_checksums.json` stores per-binary `sha256sum <bin>` checksums.
- `buildGates` — Manifest-driven gate builder. Reads `src/gate/manifest.d/_index.json` and compiles all registered gates.
- `genmanifest` — Generates feature manifest from `.feature` files.
- `buildPbtTools` — Builds PBT generator, seed parser, and forwarding stubs tool binaries.
- `buildAstInvariantChecker` — Builds native AST invariant checker binary.
- `contractTest` — Builds and runs Lean REPL contract tests.

## Hermetic Pre-Build (G2 Blocks)

The `config/integrity.nims` include (loaded via `include "config/integrity.nims"`) is referred to as the "hermeticPreBuild" block in architectural discussions. It handles:

- Immutable AGENTS.md/documentation integrity verification
- Merkle root computation at compile time
- Build environment fingerprinting
- Constraint validation against `docs/agents/core_rules.md`

The `config/vendors.nims` include provides Z3 version capture and source scanner hermetic config.

## Import Encapsulation Block

The import encapsulation gate is located at:
- **Gate runner**: `src/gate/runners/import_encapsulation_gate.nim` (immutable per AGENTS.md §-1)
- **Compile-time path injection**: `config/effects.nims` contains `switch("import", "core/trusted/env_types")` for global visibility
- **Enforcement layer**: `src/gate/runners/import_encapsulation_gate.nim` applies the import boundary rules at runtime during gate execution
- **Policy SSOT**: `src/gate/policy_schema.json` defines the shared policy schema

The import encapsulation gate verifies that domain layers import only authorized modules per the 4-layer domain architecture (Domain → Infrastructure → Presentation → Gate).

## Compile-Time Blocks

Additional compile-time blocks in config.nims:

- `bootstrapImportRules` — Auto-generates `src/generated/import_rules_static.nim` from `data/import_rules.json` if missing
- `manifestCacheInvalidation` — Detects changes in `src/gate/manifest.d/` JSON files and forces recompilation of `gate_codegen.nim`
- `manifestIndexAutoSync` — Scans `manifest.d/` and auto-syncs `_index.json` on every `nim c` run
- [REMOVED] `signIntegrityResidueGuard` — was removed (2026-07). The `AXIOM_INTERNAL_BYPASS` rename has been completed and the full-tree scan caused build timeouts. No residue guard is active.
