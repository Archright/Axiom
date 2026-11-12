# Architecture Debt Roadmap

> Tracking document for nimtry violation reduction across all refactoring phases.

## Current State

| Metric | Value |
|--------|-------|
| Total violations | 704 |
| Errors | 57 |
| Warnings | 647 |
| Baseline date | 2026-06-14 |
| Baseline commit | `bea1a05c` |

## Phase Progress

| Phase | Description | Status | Violations |
|-------|-------------|--------|------------|
| Phase 0 | Policy alignment + SSOT canonicalization start | ✅ Complete | 725 → 713 |
| Phase 1 | SSOT type canonicalization (hub pattern) | ✅ Complete | 713 → 704 |
| Phase 2 | Zero-Cost Gateway | 🔄 In Progress | — |
| Phase 3 | SRP + forwarding stubs | ⏳ Pending | — |
| Phase 4 | Ratchet mechanism + visualization | 🔄 In Progress | — |

## Per-Cluster Progress

| Cluster | Initial | Current | Target | Status |
|---------|---------|---------|--------|--------|
| `soc-leaf-module-imports` | ~25 | ~21 | 0 | 🔄 In progress |
| `solid-srp` | ~22 | ~20 | 0 | 🔄 In progress |
| `soc-surface-area` | ~15 | ~15 | 0 | ⏳ Pending |
| `solid-ocp` | ~10 | ~10 | 0 | ⏳ Pending |
| `forbidden-pragma` | ~8 | ~8 | 0 | ⏳ Pending |
| Other rules | ~645 | ~630 | 0 | ⏳ Pending |

> Note: Cluster counts are approximate. Run `src/gate/nimtry/nimtry_cli.nim --full-tree --list` for exact numbers.

## Weekly Budget Tracking

**Target**: 5% weekly reduction from current baseline (704).

| Week | Start | End | Δ | Target | Status |
|------|-------|-----|---|--------|--------|
| W25 (2026-06-09) | 725 | 704 | -21 | ≤689 | 🔄 In progress |

### Budget Calculation

```
Week N target = baseline * 0.95^N

Week 1: 704 * 0.95 = 668.8 → ≤669
Week 2: 669 * 0.95 = 635.6 → ≤636
Week 3: 636 * 0.95 = 604.2 → ≤605
Week 4: 605 * 0.95 = 574.8 → ≤575
```

## Tooling

| Tool | Purpose | Location |
|------|---------|----------|
| `nimtry_snapshot.nim` | Capture post-push violation snapshot | `tools/ci/nimtry_snapshot.nim` |
| ~~`nimtry_dashboard.py`~~ | ~~Trend report (console/HTML)~~ | ~~`tools/ci/nimtry_dashboard.py`~~ (deleted) |
| ~~`bypass_expiry_gate.py`~~ | ~~Enforce 48h bypass expiry~~ | ~~`tools/ci/bypass_expiry_gate.py`~~ (deleted) |
| `ratchet_check.nim` | Pre-commit legacy violation guard | `tools/ci/ratchet_check.nim` |

## Monitoring

```bash
# Capture a new snapshot
nim c -r tools/ci/nimtry_snapshot.nim

# Check ratchet
nim c -r tools/ci/ratchet_check.nim
```
