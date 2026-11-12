# nim-check: skip — 보존 아티팩트(증거): 주체 핀(@4aa8e22)의 모듈(orchestrator_topology_worker —
# Axiom 자체 캐리어의 Q3 collateral 재생)과만 컴파일되는 재생 하니스 원본이다.
# Axiom3 트리의 번역 단위가 아니므로 nim-check 게이트 코퍼스에서 제외한다
# (.githooks/pre-commit Part 1 스킵 계약). 이 사본에 추가된 주석 외에는
# runs/e_replay_harness_c0.nim(원본 raw — gitignored) 및
# state_e1/.axiom/tmp/replay/74fded71cfe77375/replay_harness.nim와 바이트 동일이다.
# 보존 사유와 출처: evidence/README.md · state_e1/.axiom/tmp/replay/74fded71cfe77375/.
# 결함 대상 scanString의 재생 하니스는 생성되지 않았다 — P4 bool-binding 파이프라인
# 갭(pipeline_gap/PIPELINE_GAP_P4_BOOL_BINDING.md)으로 ce-replay가 발화하지 않았다.
import orchestrator_topology_worker
echo "AXIOM_REPLAY_BEGIN"
echo $calcDynamicTimeoutCore(0, 0, 0, 0)
echo "AXIOM_REPLAY_END"
