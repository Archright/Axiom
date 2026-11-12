# Helper SSOT Classification (대안 D P0+P2)

- 작성일: 2026-08-08
- 목적: `src/gate/helper_spec.nim` + `sync_topology.nim`(`src/generated/helper_registry.nim`) 도입에 따른
  26개 비-게이트 러너 파일 분류 판정 기록. 기록 목적의 참조 문서이며 자동 생성/검증 로직에는 영향 없음.
- 분류범주:
  - (a) 순수 헬퍼 (다른 게이트가 import 하는 도구/러너 모듈, registerGate 미보유)
  - (b) 미배선 orphan (registerGate 보유하나 매니페스트에 등록되지 않음)
  - (c) 타입/셀프테스트 모듈 (타입 선언·셀프테스트 전용)

## 분류 표

| 파일 | 분류 | 근거 |
|------|------|------|
| agent_preflight.nim | (a) | 사전점검 헬퍼. registerGate 없음; 러너가 import하는 도구. |
| architecture_config_gate.nim | (b) | registerGate 보유하나 매니페스트 미등록 orphan. |
| axiom_codemod.nim | (a) | 코드 모드 변환 도구. registerGate 없음; 헬퍼/유틸. |
| canonical_hub_lint_runner.nim | (a) | 허브 린트 러너. registerGate 없음; import 대상 도구. |
| context_size_guard.nim | (b) | registerGate 보유하나 매니페스트 미등록 orphan. |
| debt_scan_gate.nim | (b) | registerGate 보유하나 매니페스트 미등록 orphan. |
| documentation_first_gate_selftest.nim | (c) | 셀프테스트 전용 모듈. |
| documentation_first_gate_types.nim | (c) | 타입 선언 전용 모듈. |
| example_gate_pre_check.nim | (a) | 예제 게이트 사전점검. registerGate 없음. |
| example_gate_report.nim | (a) | 예제 게이트 리포트 생성 도구. registerGate 없음. |
| example_gate_validate.nim | (a) | 예제 게이트 검증 도구. registerGate 없음. |
| fail_secure_state.nim | (c) | fail-closed 상태 표현 타입/상수 모듈. |
| gate_concept.nim | (b) | registerGate 보유하나 매니페스트 미등록 orphan. |
| gate_hook.nim | (a) | 게이트 훅 실행 도구. registerGate 없음. |
| gateway_test_runner.nim | (a) | 게이트웨이 테스트 러너. registerGate 없음. |
| import_normalizer.nim | (a) | import 경로 정규화 도구. registerGate 없음. |
| isolated_check.nim | (a) | 격리 체크 실행 도구. registerGate 없음. |
| nim_check_runner.nim | (a) | `nim check` 러너. registerGate 없음. |
| runner_process_pool.nim | (a) | 러너 프로세스 풀. registerGate 없음; 인프라 도구. |
| semantic_boundary_guard.nim | (a) | 의미 경계 가드. registerGate 없음. |
| source_fetcher.nim | (a) | 소스 fetch 도구. registerGate 없음. |
| unified_gate_runner.nim | (a) | 통합 게이트 러너 진입. registerGate 없음. |
| unified_gate_runner_funcs.nim | (a) | 통합 러너 funcs 서브모듈. registerGate 없음. |
| unified_gate_runner_procs.nim | (a) | 통합 러너 procs 서브모듈. registerGate 없음. |
| unified_gate_runner_types.nim | (a) | 통합 러너 types 서브모듈. registerGate 없음. |
| validate_runners.nim | (a) | 러너 검증 도구. registerGate 없음. |

## 범주 집계

- (a) 순수 헬퍼: 19
- (b) 미배선 orphan (registerGate 보유): 4 (architecture_config_gate, context_size_guard, debt_scan_gate, gate_concept)
- (c) 타입/셀프테스트 모듈: 3 (documentation_first_gate_selftest, documentation_first_gate_types, fail_secure_state)

## 비고

- `sign_integrity_gate.nim`은 디스크에 존재하지 않는 유령 항목 → 제외.
- `gate_self_check.nim`은 `bin/gate_self_check` 등록 게이트 소스 → 헬퍼 아님 → 포함 금지.
- `manifest_consistency_gate.nim`은 본 분류 대상이 아니며 P1에서 별도 리팩토링 대상.
