# Topology _part File Staleness Audit

## Date
2026-07-25

## Policy Reference
`topology_policy.json` → `transitional_max_age_days: 14`

## Detection Patterns
- `"*_part*.nim"` (from topology_policy.json `transitional_detection.patterns`)

## Scan Results

34 `_part*.nim` files found under `src/`:

| Count | Pattern | Location |
|-------|---------|----------|
| 2 | `*_part1.nim` | `src/cli/private/` |
| 2 | `*_part1.nim`, `*_part1_part1.nim` | `src/core/boundary/` |
| 2 | `*_part1.nim`, `*_part2.nim` | `src/core/judge/` |
| 2 | `*_part1.nim`, `*_part2.nim` | `src/core/policy/` |
| 2 | `*_part1.nim`, `*_part2.nim` | `src/core/symbol_graph/` |
| 2 | `*_part1.nim`, `*_part2.nim` | `src/core/translator/` |
| 1 | `*_part1.nim` | `src/core/verified_axioms/` |
| 4 | `*_part1.nim`, `*_part2.nim`, `*_part3_part1.nim`, `*_part3_part2.nim` | `src/gate/nimtry/` |
| 4 | `*_part1.nim`, `*_part2.nim` | `src/gate/runners/private/` |
| 2 | `*_part1.nim`, `*_part2.nim` | `src/ui/` |
| 4 | `*_part1.nim`, `*_part2.nim` | `src/verification/` (root) |
| 4 | `*_part1.nim`, `*_part2.nim`, `*_part3.nim` | `src/verification/` (pipeline_*) |
| 3 | `*_part1.nim`, `*_part2.nim` | `src/verification/orchestrator/private/` |
| 2 | `*_part1.nim`, `*_part2.nim` | `src/verification/` (proof_synthesis_*) |

## Staleness Verdict

**No stale files detected.**

Oldest `_part*.nim` file timestamp: 2026-07-24 (1 day old at audit time).
All files are within the 14-day transitional window.

## Note
No files were deleted or modified. This is a documentation-only audit per topology_policy.json transitional detection policy.
