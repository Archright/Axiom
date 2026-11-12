# Algebraic Module Split Pattern

**Created**: 2026-07-05
**Authority**: AGENTS.md §0.3 (SRP), §0.6 (Static First Enforcement), Invariant 10
**Enforcement**: `config/strict.nims` Invariant 10 (500-line gate)

## Problem

Files over 500 lines violate Single Responsibility Principle (AGENTS.md §0.3).
Invariant 10 in `config/strict.nims` blocks new violations but 16 grandfathered
files still need splitting. The challenge is migrating these files without breaking
existing importers.

## Pattern

### Structure

```
module_name.nim             # Parent: re-exports everything (backward compat)
  module_name_types.nim     # Type definitions only
  module_name_func.nim      # Pure func layer (no I/O, no side effects)
  module_name_proc.nim      # Stateful proc layer (I/O boundary)
```

### Parent Module

```nim
# module_name.nim
import module_name_types
import module_name_func
import module_name_proc
export module_name_types, module_name_func, module_name_proc
```

The parent module maintains backward compatibility: all existing `import module_name`
statements continue to work unchanged. New code should import sub-modules directly.

### Constraints

| Sub-module | Allowed | Forbidden | Pragma |
|---|---|---|---|
| `_types.nim` | `type` definitions, `const`, `converter` | `func`, `proc`, `macro`, `template` | `{.push raises: [].}` |
| `_func.nim` | `func` declarations, pure computations | `proc`, I/O, `{.sideEffect.}`, mutable state | `{.push raises: [].}` |
| `_proc.nim` | `proc` declarations, I/O boundary | Bare I/O without `{.axiomEffect: IoEffect.}` | `{.push raises: [CatchableError].}` |

### Parent Module Constraints

- Parent contains **only** `import`/`export` statements, pragma wrappers, and comments
- No `func`, `proc`, `type`, `const`, `let`, `var` definitions in parent
- Parent is a **pure forwarding module** (zero logic)
- This classifies the parent as a "hub stub" per `docs/spec/facade_deprecation_policy.md`

### Layering Rules

- `_types.nim` has **no dependencies** on other sub-modules (leaf)
- `_func.nim` may import `_types.nim` only
- `_proc.nim` may import `_types.nim` and `_func.nim`
- Parent imports all three; nothing else imports the parent in new code

```
     ┌─────────────┐
     │ parent.nim  │  (re-exports all)
     └──────┬──────┘
            │
   ┌────────┼────────┐
   │        │        │
   ▼        ▼        ▼
 _types  _func    _proc
 (leaf)   │        │
          └────┬───┘
               ▼
            _types
```

## Migration Steps

1. **Extract types** into `_types.nim`
   - Move all `type` blocks and related `const` values
   - Add `{.push raises: [].}` pragma
   - Verify: `nim check module_name_types.nim`

2. **Extract pure functions** into `_func.nim`
   - Move all `func` declarations that have no I/O
   - Add `{.push raises: [].}` pragma
   - Add `import module_name_types` if type references exist
   - Verify: `nim check module_name_func.nim`

3. **Extract stateful procs** into `_proc.nim`
   - Move all `proc` declarations
   - Add `{.axiomEffect: IoEffect.}` to each proc performing I/O
   - Add `{.push raises: [CatchableError].}` pragma
   - Import `_types.nim` and `_func.nim` as needed
   - Verify: `nim check module_name_proc.nim`

4. **Create parent re-export module**
   - Replace original file content with pure import/export forwarding
   - Verify: `nim check module_name.nim`

5. **Verify all importers compile**
   - Run `nim c -d:axiom_gateway_build src/cli/main.nim`
   - All existing `import module_name` statements must still resolve

6. **Remove grandfather exception** from Invariant 10
   - Delete the file's entry from `grandfatherExceptions` in `config/strict.nims`
   - Verify: `nim c -d:axiomStrict` passes without flagging the split file

## Grandfathered Files (Invariant 10)

These 16 files exceed 500 lines and are exempt from Invariant 10 until split.
Priority order by line count (highest first):

| # | File | Location | Split Priority |
|---|---|---|---|
| 1 | `orchestrator_hook_part2.nim` | `src/gate/` | High |
| 2 | `unified_gate_runner.nim` | `src/gate/` | High |
| 3 | `orchestrator_hook_part1.nim` | `src/gate/` | High |
| 4 | `documentation_first_gate.nim` | `src/gate/` | High |
| 5 | `architecture_config_gate.nim` | `src/gate/` | High |
| 6 | `debt_scan_gate.nim` | `src/gate/` | Medium |
| 7 | `logging_policy_gate.nim` | `src/gate/` | Medium |
| 8 | `codec_codegen.nim` | `src/core/` | Medium |
| 9 | `gate_memo.nim` | `src/gate/` | Medium |
| 10 | `shell_ast_analyzer.nim` | `src/gate/` | Medium |
| 11 | `semantic_boundary_guard.nim` | `src/gate/` | Medium |
| 12 | `dependency_rules_gate.nim` | `src/gate/` | Medium |
| 13 | `nim_check_runner.nim` | `src/gate/runners/` | Low |
| 14 | `nimtry_cli.nim` | `src/gate/nimtry/` | Low |
| 15 | `pipeline_orchestrator.nim` | `src/engine/` | Low |
| 16 | `task_schema.nim` | `src/core/` | Low |

### Split Recommendation per File

- **Gate runners** (items 2, 4, 5, 6, 7, 10, 11, 12, 13): Split into `_types.nim` + `_func.nim`
  (gate runners are mostly pure logic with no I/O boundary)
- **Core modules** (items 8, 16): Full 3-way split (_types, _func, _proc)
- **Infrastructure** (items 1, 3, 9, 14, 15): Assess per-file; most are orchestration
  modules that may need `_types.nim` + `_proc.nim` only

## Automation

The `tools/facade_eliminator.nim` tool handles import rewriting when splitting.
Use it after extraction to update all importers of the new sub-modules.

For the parent re-export module, the split tool pattern ensures zero breakage:
existing `import module_name` continues to resolve through the parent's `export`.

## References

- AGENTS.md §0.3: Business-Only Test Scope, SRP
- AGENTS.md §0.6: Static First Enforcement
- `config/strict.nims` §Invariant 10: File Length Gate
- `docs/spec/facade_deprecation_policy.md`: Hub stub classification
- `tools/facade_eliminator.nim`: Automated import rewriting
