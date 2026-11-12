# C01–C10 Promotion scenario matrix — FREEZE (2026-09-05)

> 기준: baseline eaed53d8a. case = unique CanonicalChangeSet (replicate 아님). mechanism coverage 포함.
> 상태: FROZEN(정의) — C04·C05는 discovery OBSERVED, C06–C10은 정의만(관측 대기).

| case | mechanism | target file/symbol | oracle expectedRatio | status | evidence |
|---|---|---|---|---|---|
| C01 | comment-only (overapprox control) | topology_dependency::proximityScore | 1/40 | FROZEN(측정됨 N0) | VALID, selected non-empty |
| C02 | literal change | topology_dependency::proximityScore | 1/40 | FROZEN(측정됨 N1) | VALID |
| C03 | body change | topology_dependency::proximityScore | 1/40 | FROZEN(측정됨 N2: 5 pair 1.30×) | VALID |
| C04 | shared-function body propagation | topology_engine::findTopologyMetricIndex | 3/40 | FROZEN(discovery OBSERVED) | VALID, selected=3 (전파) |
| C05 | contract(postcondition) | topology_dependency::proximityScore | 1/40 | FROZEN(discovery OBSERVED) | VALID |
| C06 | constant (재대상 선정 필요) | TBD — const 보유 파일 | TBD | PENDING-observation | (N3-A rejected_fixture 기록) |
| C07 | call-site addition | kernel file with calls (TBD) | TBD | PENDING-observation | |
| C08 | generated-artifact | src/generated/* (TBD) | TBD | PENDING-observation | |
| C09 | body change (다른 타깃) | vault_manager_spec::axiomSpecToJsonNode | TBD | PENDING-observation | |
| C10 | contract change (다른 타깃) | kernel func with post (TBD) | TBD | PENDING-observation | |

규칙: freeze 이후 정의 변경 없음. 관측 결과는 evidence에 추가(정의 수정 아님). replicate는 C3b economics 전용.
