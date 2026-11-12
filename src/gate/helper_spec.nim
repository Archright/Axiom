##  이 목록은 Check 6의 SSOT 진실 출처다. 등록 게이트와 별개인 헬퍼/유틸리티/미배선 모듈만 담는다.
##  추가/제거는 이 파일과 sync_topology로 결정론적으로 반영된다.

import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite

axiomLayer "gate"

const HelperModules* {.axiomDecision(
  id = "DECISION-HELPERS-1",
  reason = "Non-gate runner modules declared in SSOT so manifest_consistency Check 6 uses deterministic data instead of code heuristics",
  adr = "docs/adr/0004-ssot-gate-registry.md",
  introduced = "v32"
).} = [
  "agent_preflight.nim",
  "architecture_config_gate.nim",
  "axiom_codemod.nim",
  "canonical_hub_lint_runner.nim",
  "debt_scan_gate.nim",
  "documentation_first_gate_selftest.nim",
  "documentation_first_gate_types.nim",
  "example_gate_pre_check.nim",
  "example_gate_report.nim",
  "example_gate_validate.nim",
  "fail_secure_state.nim",
  "gate_concept.nim",
  "gate_hook.nim",
  "gateway_test_runner.nim",
  "import_normalizer.nim",
  "isolated_check.nim",
  "nim_check_runner.nim",
  "runner_process_pool.nim",
  "semantic_boundary_guard.nim",
  "source_fetcher.nim",
  "unified_gate_runner.nim",
  "unified_gate_runner_funcs.nim",
  "unified_gate_runner_procs.nim",
  "unified_gate_runner_types.nim",
  "validate_runners.nim"
]
