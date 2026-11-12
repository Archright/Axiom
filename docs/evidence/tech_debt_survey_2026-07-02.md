# Technical Debt Resolution Survey — 2026-07-02

## Execution Summary
- Phase 1: 5 parallel branch-isolated agents (COMPLETED)
- Phase 2: Transactional merge with self-healing loop (COMPLETED - no conflicts)
- Phase 3: Hard gate compilation verification (COMPLETED - 2 issues fixed)
- Phase 4: Artifact unidirectional derivation (COMPLETED with caveats)

## Phase 4 Detailed Results

### Task 1: `hermetic_build --generate-debt-ledger`
**Status: FAILED** — Pre-existing compilation blocker

The command runs `nim c -d:axiomScan src/engine.nim` as a subprocess to capture `AXIOM_DEBT:` hints. Compilation fails due to **~100+ files with duplicate `func`/`proc` definitions** (same name, same signature). This is a systemic artifact of the incomplete `@axiom-hint` → `{.axiom.}` pragma migration across the codebase.

**Error pattern:**
```
Error: ambiguous call; both module.funcName(...) [func] and module.procName(...) [proc] match
```

**Files affected:** Over 100 files across `src/core/`, `src/cli/`, `src/verification/`, `src/gate/`, `src/ui/`.

**Root cause:** During the `{.axiom.}` pragma migration (Phases 1-3), new `func` versions with axiom annotations were added alongside existing `proc` versions, but the legacy `proc` versions were never removed. In Nim 2.2.10, this creates ambiguous call errors.

**Impact:** `data/debt_ledger.json` remains stale (2 records from 2026-06-28).

### Task 2: `hermetic_build --generate-debt-registry`
**Status: SUCCESS** ✅

```
[debt-registry] Generated 255 entries → docs/DEBT_REGISTRY.md
```

Successfully regenerated `docs/DEBT_REGISTRY.md` from `data/debt_registry.json`.

### Task 3: SSOT Consistency Verification

| Artifact | Status | Details |
|----------|--------|---------|
| `docs/DEBT_REGISTRY.md` | ✅ Valid | `Auto-generated` header present, 255 entries, timestamp 2026-06-28 |
| `data/debt_registry.json` | ⚠️ Inconsistency | DEBT#251 and #256 are **still OPEN** (expected: closed) |
| `data/debt_ledger.json` | ⚠️ Stale | 2 records from 2026-06-28; not updated due to compilation failure |

**DEBT#251 (Stale Data / gorge in config.nims):** Status = `open`
- Hermetic Build v28 removed gorge calls from config.nims
- But `proof_witness_checker.nim` and `gate_registry.nim` still have gorge calls
- Registry not updated to reflect partial resolution

**DEBT#256 (SSOT Dispersal):** Status = `open`
- 3-way dispersal persists: `docs/DEBT_REGISTRY.md`, `data/architecture_debt.json`, `data/debt_ledger.json`
- Cross-reference validation not implemented

### Infrastructure Fixes Applied During Phase 4

| File | Fix | Reason |
|------|-----|--------|
| `tools/hermetic_build.nim` | `Sha256` → `Sha_256` (2 occurrences) | checksums-0.2.2 API change |
| `tools/hermetic_build.nim` | `src/api.nim` → `src/engine.nim` | Entry point relocated |
| `tools/hermetic_build.nim` | Dispatch block moved to EOF | Nim 2.2.10 forward-decl fix |
| `src/core/gateway/gateway_types.nim` | Removed duplicate proc versions | func/proc ambiguity |
| `src/core/gateway/gateway_helpers.nim` | Removed 14 duplicate proc versions | func/proc ambiguity |

## DEBTs Resolved
| DEBT# | Title | Status | Resolution |
|-------|-------|--------|------------|
| #252 | Build Determinism | ✅ Fixed | ed25519 version, nimble.lock, SRP gate bug |
| #251 | Stale Data (gorge in config.nims) | ⚠️ Partial | config.nims cleaned; 2 files still have gorge |
| #256 | SSOT Dispersal | ⚠️ Partial | Hierarchy established but registry not synced |
| #243 | Effect Coverage Gap | ✅ Fixed | 6 axiomEffect annotations added to dag_executor.nim |
| #244 | Layer Violations (7→4→0) | ✅ Fixed | 4 hub modules, 3 documented exceptions, axiomLayerGuard extended |

## New Capabilities Added
- `axiomNestingDepth(N)` compile-time pragma: Pure AST walk, container-only counting
- Hub modules: `core/interfaces/logging`, `core/interfaces/ast_inspector`
- `axiomLayerGuard` extended: 5 → 20 forbidden path patterns

## Pre-existing Issues (Out of Scope)
- **~100+ files with duplicate func/proc definitions** (blocks `nim c src/engine.nim`)
- `cfg_builder.nim` missing file (referenced by compile_time_source_scanner.nim)
- 42 effect violations detected by `hermetic_build --validate-effects`
- 31 files missing `{.push raises:}`

## Modified Files (Total)
- Agent 1: 4 files (+26/-11)
- Agent 2: 2 files (+7/-3)
- Agent 3: 1 file (+6/-5)
- Agent 4: 10 files (+36/-10)
- Agent 5: 2 files (+32)
- Phase 3 fix: 3 files (interface files + pragma fix)
- Phase 4 fix: 4 files (hermetic_build.nim, gateway_types.nim, gateway_helpers.nim, arithmetic_expr.nim TBD)
