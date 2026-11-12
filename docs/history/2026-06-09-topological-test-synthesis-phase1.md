# Topological Test Synthesis — Phase 1 (tools/ Prototype)

**Date:** 2026-06-09  
**SSOT Authority:** AGENTS.md §0.2 (First-Principles Elegance), §1.2 (Layer Structure), §1.3 (DRY)  
**Decision Record:** Context7-verified review of Gemini's "DAG Topological Test Synthesis" proposal

---

## Problem
Issue B: 189 untested modules in `src/core/`. Human batch scheduling is non-deterministic and creates mock-assumption debt.

## Solution: 2-Phase Stabilization Strategy

### Phase 1 — `tools/` Prototype (Current)
Build `tools/discover_test_debt.nim` as a compile-and-run batch script.

**Rationale (AGENTS.md §0.2, §1.6):**
- During the 10-week transitional period, Pure/IO heuristic rules will mutate frequently.
- Keeping volatile logic outside the official CLI surface eliminates parser synchronization cost and prevents premature CLI namespace pollution.

### Phase 2 — `src/cli/` Promotion (Future)
After stabilization (no rule changes for 2+ consecutive weeks) and 189-module debt zero:
- Promote to `ax discover debt`
- Register in `cli_surface_generated.nim`
- Delete `tools/discover_test_debt.nim` (SSOT Write-Back)

---

## Context7 Verification Results

| Gemini Claim | Verdict | Rationale |
|-------------|---------|-----------|
| Extend nimtry with Discovery Pass | ❌ Rejected | SoC breach — Gate Layer must remain read-only (AGENTS.md §1.2) |
| Bind Nim compiler/ast API | ❌ Rejected | Overkill; `compiler/` API raises `[Exception, OSError, KeyError, ValueError]`, violating §0.6 `{.raises: [].}` default |
| Use `generate-pbt-tests` (built-in) | ✅ Validated | SSOT alignment; no external dependency, no ARC/ORC risk |
| Layer-based auto-batching | ✅ Validated | DAG topological sort is deterministic (Nim modulegraphs.html) |
| Immediate CLI promotion | ❌ Rejected | Premature; violates §0.2 elegance (stabilize first, promote later) |

---

## Files Created

- `src/core/import_graph.nim` — Shared graph builder extracted from `dag_enforcement_gate.nim` (DRY)
- `tools/discover_test_debt.nim` — Topological layer discovery + tier classification heuristic

## Files Modified

- `src/gate/runners/dag_enforcement_gate.nim` — Refactored to use `import_graph.nim`

---

## Execution Results (2026-06-09)

```
[dag-gate] PASS: src/core/ is a DAG (236 modules scanned, 0 cycles)
[discover] Total layers: 22
[discover] Total Tier1=114 Tier2=110
```

Layer distribution (top 5):
- Layer 0: 39 modules (Tier1=20, Tier2=19)
- Layer 1: 32 modules (Tier1=20, Tier2=12)
- Layer 2: 24 modules (Tier1=12, Tier2=12)
- Layer 3: 20 modules (Tier1=11, Tier2=9)
- Layer 4: 19 modules (Tier1=10, Tier2=9)

---

## Restoration Risk

**Low.** `import_graph.nim` is shared infrastructure. `tools/discover_test_debt.nim` is explicitly transient (Phase 1 only). Deletion is planned as part of Phase 2.

## Next Steps

1. Run `tools/discover_test_debt.nim` weekly to regenerate `tests/auto_generated/batch_manifest.json`
2. Enhance `bin/generate-pbt-tests` to consume batch manifest algebraic properties
3. After 189-module debt reaches zero and heuristic stabilizes, execute Phase 2 promotion
