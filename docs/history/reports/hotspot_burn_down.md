# Hotspot Burn-down Queue

**Auto-generated report** — do not edit manually.

- Analysis period: last 30 days
- Total hotspots tracked: 20
- Scoring: priority = edits × risk_multiplier
  - No test: ×3.0, SAD<5%: ×2.0, SAD<15%: ×1.5, SAD≥15%: ×1.0

| Rank | Module | Path | Edits | Test? | SAD | Priority | Tier |
|------|--------|------|-------|-------|-----|----------|------|
| 1 | wf_state | src/cli/wf_state.nim | 60 | ✗ | — | 180.0 | 🔴 Critical (no test) |
| 2 | topology_cli | src/cli/topology_cli.nim | 48 | ✗ | — | 144.0 | 🔴 Critical (no test) |
| 3 | report_cli | src/cli/report_cli.nim | 44 | ✗ | — | 132.0 | 🔴 Critical (no test) |
| 4 | analyzer | src/verification/analyzer.nim | 43 | ✗ | — | 129.0 | 🔴 Critical (no test) |
| 5 | asi_cli | src/cli/cst_cli.nim | 39 | ✗ | — | 117.0 | 🔴 Critical (no test) |
| 6 | heal | src/cli/commands/heal.nim | 39 | ✗ | — | 117.0 | 🔴 Critical (no test) |
| 7 | axiom_engine | src/cli/axiom_engine.nim | 36 | ✗ | — | 108.0 | 🔴 Critical (no test) |
| 8 | heal_injection | src/cli/commands/heal_injection.nim | 36 | ✗ | — | 108.0 | 🔴 Critical (no test) |
| 9 | judge | src/personas/judge.nim | 35 | ✗ | — | 105.0 | 🔴 Critical (no test) |
| 10 | observability | src/cli/commands/observability.nim | 34 | ✗ | — | 102.0 | 🔴 Critical (no test) |
| 11 | verify_workflow_cli | src/cli/verify_workflow_cli.nim | 34 | ✗ | — | 102.0 | 🔴 Critical (no test) |
| 12 | recertify_lean | src/cli/commands/recertify_lean.nim | 33 | ✗ | — | 99.0 | 🔴 Critical (no test) |
| 13 | pipeline_core_runner | src/verification/pipeline_core_runner.nim | 32 | ✗ | — | 96.0 | 🔴 Critical (no test) |
| 14 | detective | src/personas/detective.nim | 31 | ✗ | — | 93.0 | 🔴 Critical (no test) |
| 15 | translation_validator | src/verification/translation_validator.nim | 31 | ✗ | — | 93.0 | 🔴 Critical (no test) |
| 16 | hint_processor | src/verification/hint_processor.nim | 30 | ✗ | — | 90.0 | 🔴 Critical (no test) |
| 17 | stage_05_lean_bridge | src/verification/analyzer/stages/stage_05_lean_bridge.nim | 30 | ✗ | — | 90.0 | 🔴 Critical (no test) |
| 18 | legislator | src/personas/legislator.nim | 29 | ✗ | — | 87.0 | 🔴 Critical (no test) |
| 19 | tools | src/mcp/tools.nim | 29 | ✗ | — | 87.0 | 🔴 Critical (no test) |
| 20 | proof_synthesis_engine | src/verification/proof_synthesis_engine.nim | 27 | ✗ | — | 81.0 | 🔴 Critical (no test) |

