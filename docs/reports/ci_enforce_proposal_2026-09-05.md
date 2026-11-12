# CI Enforce Proposal — Phase B (ExecutionPlan canonical path)

> 작성일: 2026-09-05 · 작성자: debt branch agent session
> 지위: **PROPOSAL — 아키텍트 승인 PENDING**
> **`.github/workflows/ci.yml` 상태: UNCHANGED (§-1 — 승인 전 수정 금지)**

---

## 1. 요약

CI 선택적 검증 enforce(Phase B)의 전환 제안서. Rollout 계약(`docs/spec/ci_execution_plan_rollout.md` §4.2/§8.2)에 따라
Phase-A shadow 증거를 수집하고 전환 게이트를 실측 기준으로 평가하였다.

**결론: §8.2 전환 게이트 중 3번(Project(Full,Selected)==Pruned shadow 지속)이 현재 HEAD에서 PARTIAL(1/3 claimable)이므로
Phase B enforce는 **승인 불가 상태**이다. 원인은 F-1/F-2이며, 이는 아키텍트 결정이 필요한 범위(실행 보고 상태 소스 정규화 +
전체 실행 스코프 커버리지)에 속한다.**

## 2. 기준 문서

- `AGENTS.md` §-1 — `.github/workflows/ci.yml` immutable (인간 아키텍트 명시적 승인 없이 수정 불가)
- `docs/spec/ci_execution_plan_rollout.md` — rollout 계약 (Phase A: shadow 무수정, Phase B: enforce + ci.yml 승인 필요)
- `docs/spec/canonical_execution_semantics.md` — 확정 semantics (RequestResult reducer, projection, fail-closed)
- `docs/spec/incremental_ci_contract.md` §4.2/§4.5 — selection containment / over-approximation

## 3. Phase-A shadow 증거 (실측)

| §8.2 게이트 | 실측 | 상태 |
|---|---|---|
| 1. shadow 관측 기간 | `docs/reports/impact_closure_shadow_2026-08-28.json`, `_core`, `_docs_only` 3건 + canary_v1_equivalence.yml (workflow_dispatch + schedule 일일) 누적 중 | 미달(N은 실측 후 결정 — 현재 3건) |
| 2. CI↔Local parity ≥ P% | `experiment_acceleration_local_ci_parity.md` 패리티 프로토콜 + `tools/selection_digest_compare.nim` 게이트 ①②③ 존재; 금회 실행분 없음 | 미검증(0건 추가 관측) |
| 3. Project(Full,Selected)==Pruned shadow 지속 | **r8b3_projection_evidence: 1/3 claimable·EQUAL (proximityScore), 2/3 full-side UNOBSERVABLE → not-claimed (fail-closed)** | **미충족 (PARTIAL)** |
| 4. FALLBACK_REQUIRED 증가 추세 없음 | trend data 없음 | 미확립 |
| 5. baseline(eaed53d8a) 대비 regression 없음 | 금회 재측정 없음 (단위/아키텍처 스위트 green 유지) | 미확립 |

## 4. F-1 / F-2 (Projection 게이트 차단 원인 — 아키텍트 결정 필요)

- **F-1 — 실행 스코프 커버리지**: C03 시나리오(`d3a4d2f75..c3adfb995` mutation)에서 선택은
  symbol-dependents closure(3 unit: hasVaultEntry/proximityScore/axiomSpecToJsonNode)를 요청하지만,
  Full 실행의 단일-wave 프론티어는 실패한 의존성(proximityScore psFail→demotion)으로 나머지 2개 unit을
  실행하지 못함 → Full-side 결과 부재 → projection not-claimed (fail-closed).
- **F-2 — 최종 상태 소스 이원성**: pre-demotion IR 라인(`status=psFail`)과 post-demotion 최종 certificate
  (`no_obligation` → vault `tcVerifiedProof`)이 동일 실행 내에 공존. UnitResult/캐시의 canonical proofStatus는
  post-demotion이 지배적이나, 산출물별 소스가 다름 → 증거 파이프라인이 소스를 통일해야 함.
- **결정 질문**: (a) cross-run projection의 canonical 전체 실행 스코프 정의, (b) 최종 verdict 상태 소스 표준화.
  이 두 결정은 실행-보고 의미론(제품 계약 표면)에 속하므로 아키텍트 승인이 필요.

## 5. 의도된 최소 ci.yml 변경 (적용 전 — 승인 대기)

CI canonical path (selection 로직 CI 재구현 금지 — plan artifact 소비만):

```text
ChangeSet → Graph → Selection → RequestDerivation → ExecutionPlan → Exact Cache → Parallel Execute → RequestResult
```

- 기존 verify-static/integration/coverage-guard 유지, required check `all-gates-passed` 유지.
- 신규 단계: `ax prove --plan <selection_report 산출 ExecutionPlan>` — uncertainty(FALLBACK)→FULL, integrity(ERROR)→REJECT 유지.
- `merge_group: checks_requested` 트리거 추가 (GitHub 공식 문서: merge queue + 필수 체크 요구 조건), concurrency group 고유화.
- **이 diff는 아키텍트 승인 수령 시에만 적용한다. 승인 전 ci.yml은 수정하지 않는다.**

## 6. 승인 요청 항목

1. F-1/F-2 해소 방향 승인 (전체 실행 스코프 정의 + 최종 상태 소스 표준화).
2. §8.2 게이트 미충족 상태에서의 Phase B 진행 여부 (권고: 게이트 충족까지 보류).
3. 워크플로 트리거 확장(merge_group 등) 포함 여부.

## 7. 상태 기록

```text
CI enforce proposal prepared: true
architect approval = PENDING
ci.yml unchanged: true
```