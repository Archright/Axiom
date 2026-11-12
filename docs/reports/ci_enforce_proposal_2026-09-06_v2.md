# CI Enforce Proposal — Phase B (Canonical selective-verification path)

> 작성일: 2026-09-06 · 상태: **PROPOSAL — 아키텍트 승인 요청**
> `.github/workflows/ci.yml` 상태: **UNCHANGED** (§-1 — 승인 전 수정 금지)

---

## 1. 요약

VerificationClosure / RunInputSnapshot / Cache-as-optimization 통합(I-A~I-F)을 구현·검증했다.
Promotion-B는 이전 PASS 유지(P2~P3의 동일 infrastructure), Promotion-A는 Projection gate만 PARTIAL(5/9).
Phase-B enforce(enforce 전환)는 §8.2 게이트 실측 + 최소 ci.yml diff 제안 + 아키텍트 승인 요청이다.

## 2. 구현·검증 요약 (이번 세션 확정)

| 단계 | 커밋 | 내용 | 검증 |
|---|---|---|---|
| g7 계약 정렬 | 811a3dbfa | computeReportExitCode를 product contract 정렬(no_obligation+no-fail→exit 0) | report 테스트 |
| RunInputSnapshot | 3fbc2733e | runInputSnapshotDigest(A)/runResultDigest(B) 순수 함수 | selection_digests_test 8 |
| Cache=I-D | 7e33b2abc | vault hydration 소스 지문 검증(validated candidate reuse) | hydrate_test 5 |
| VerificationClosure | cacd0fe37+41d54f0d6 | wave loop(attempted-set 종료) + 독립 oracle + blocked_by + universe 가드(I-C/I-F) | closure_test 4, 스모크 2-wave |
| Projection | 40cbd7659 | closure-complete Full vs Pruned 실측 | r8b3: 5/9 equal |
| R8d determinism | fe68ad57e | 7 digest IDENTICAL(state dir 독립) | r8d v2 |

핵심 불변식(모두 테스트로 고정):
```
I-A RunInputSnapshotDigest = H(BaseRun|Plan|Toolchain|EnvContract)   — 결과 미포함
I-B RunResultDigest      = H(RunInputSnapshot|RequestResults|UnitResults) — 실행 후
I-C ClosureComplete ⇔ DiscoveryFixedPoint ∧ (Required ⊆ Completed ∪ Justified)
I-D CacheHit = ValidCertificate(CurrentExecutionIdentity)
I-E ExecutionIdentity ≠ RunInputSnapshotDigest ≠ RunResultDigest
I-F universe 신선도 가드
```

## 3. §8.2 Phase-B 전환 게이트 실측

| 게이트 | 실측 | 상태 |
|---|---|---|
| 1. shadow 관측 기간 | impact_closure_shadow 3건 + canary(schedule) 누적 | 미달(N 실측 후 결정) |
| 2. CI/local parity ≥P% | selection_digest_compare 게이트 존재; 금회 실행분 없음 | 미검증 |
| 3. Project(Full,Selected)==Pruned shadow | r8b3: **5/9 equal, 4 fail-closed not-claimed** (dependency-차단, blocked_by 정당화 존재) | **미충족 (PARTIAL)** |
| 4. FALLBACK_REQUIRED 증가 | trend data 없음 | 미확립 |
| 5. baseline 대비 regression | R8d/R6 재현; g7 fresh-state 정합 | 부분 확립 |

**결론: Projection 게이트 미충족 → Phase-B enforce는 승인 불가(권고: 게이트 충족까지 보류).**
Projection 완전 성립은 full-side dependency-차단 단위의 blocked_by-정당화 계수(아키텍트 결정)가 필요.

## 4. 의도된 최소 ci.yml 변경 (승인 전 미적용)

```text
ChangeSet → Graph → Selection → RequestDerivation → ExecutionPlan
         → Exact Cache(validated) → Parallel Execute → RequestResult
```
- selection 로직 CI 재구현 금지 — canonical planning implementation 소비.
- uncertainty(FALLBACK)→FULL, integrity(ERROR)→REJECT 유지.
- 기존 required check `all-gates-passed` 유지; 게이트 충족 후 추가.

## 5. 승인 요청

아래 항목의 승인을 요청한다:
1. blocked_by-정당화 기반 projection 계수 허용 여부(or Projection 강제 FAIL 정책 유지).
2. §8.2 게이트 미충족 상태에서 enforce 진행 여부(권고: 보류).
3. 이 Proposal validation 통과 시 최소 ci.yml diff 적용 승인.

## 6. 상태

```text
CI enforce proposal prepared: true
architect approval = PENDING
ci.yml unchanged: true
Projection gate = PARTIAL (5/9 equal, 4 dependency-blocked fail-closed)
Promotion-A = PARTIAL (Projection gate 미충족)
Promotion-B = PASS
```