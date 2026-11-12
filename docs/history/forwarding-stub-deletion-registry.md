# Forwarding Stub Deletion Registry

> Append-only registry of deleted forwarding stub modules.
> Purpose: Prevent accidental restoration by future session agents.
> Authority: AGENTS.md §1.3b Forwarding Stub Design Principle, §2.1 Annals Write-Back.

## Batch 1 — 2026-06-10: Topology Engine Relocation Stubs

**Commit**: `refactor(topology): delete topology engine forwarding stubs after consumer migration`  
**Authority**: AGENTS.md §1.3b, Context7 `/nim-lang/nim` — *"When exporting a module, all its definitions are forwarded. Use `except` to exclude specific symbols if needed."* (Nim Manual). Forwarding stubs are a transient compatibility mechanism, not a permanent architecture layer.  
**Reason**: Topology engine was relocated from `src/core/` root to `src/core/topology/` per P1 compact topology.json. The single consumer (`src/cli/commands/topology_cli.nim`) was migrated to import from `core/topology/xxx` directly. Retaining stubs would violate the "Stub에는 비즈니스 로직을 넣지 마라" principle and create a duplicate module surface.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `src/core/topology_policy.nim` | Relocated to `src/core/topology/policy.nim`; consumer migrated | LOW — restore only if a new consumer cannot use `core/topology/policy` |
| `src/core/topology_lock.nim` | Relocated to `src/core/topology/lock.nim`; consumer migrated | LOW |
| `src/core/topology_explain.nim` | Relocated to `src/core/topology/explain.nim`; consumer migrated | LOW |
| `src/core/topology_suggest.nim` | Relocated to `src/core/topology/suggest.nim`; consumer migrated | LOW |
| `src/core/topology_declaration.nim` | Relocated to `src/core/topology/declaration.nim`; consumer migrated | LOW |
| `src/core/topology_manifest.nim` | Relocated to `src/core/topology/manifest.nim`; consumer migrated | LOW |

**DO NOT RESTORE** without: (a) proving `core/topology/xxx` import path is infeasible for a new consumer, AND (b) `bin/procedure_gate` pass after restoration.

---

## Batch 2 — 2026-06-10: Logic Module Relocation Stubs

**Commit**: `refactor(core): delete smt_logic and axiom_verification_context forwarding stubs`  
**Authority**: AGENTS.md §1.3b, Context7 `/nim-lang/nim` — module re-export pattern (`import foo/bar; export bar`) is intended for temporary redirection, not as a stable dependency.  
**Reason**: Real implementations already live under `src/core/logic/`. All consumers import directly from `core/logic/xxx` after migration. Root-level stubs served only as backward-compatibility shims.

| File | Deletion Reason | Restoration Risk |
|------|-----------------|------------------|
| `src/core/smt_logic.nim` | Relocated to `src/core/logic/smt_logic.nim`; no active consumers of root-level path | LOW |
| `src/core/axiom_verification_context.nim` | Relocated to `src/core/logic/axiom_verification_context.nim`; consumers migrated | LOW |

**Migrated Consumers**:
- `src/core/types/pipeline_core_types.nim`: `core/axiom_verification_context` → `core/logic/axiom_verification_context`
- `src/verification/universal_pipeline.nim`: `core/axiom_verification_context` → `core/logic/axiom_verification_context`
- `src/verification/batch_uap_orchestrator.nim`: `core/axiom_verification_context` → `core/logic/axiom_verification_context`

**DO NOT RESTORE** without: (a) proving `core/logic/xxx` import path is infeasible, AND (b) `bin/procedure_gate` pass after restoration.
