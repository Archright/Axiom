# G1 — 작업 트리 상태점 고정 (Checkpoint)

> 설정 동결: 아래 상태점 이후 설계 변경 없음. 남은 작업은 G2(검증 완료 처리) → G3(실측) → G4(커밋).
> 날짜: 2026-09-05 · 브랜치: `debt` · HEAD: `67ad84e66` (feat(ci): production shadow — canonical semantic equivalence lane)

## 1. 게이트 검증 결과 (G0)

| 게이트 | 결과 | 비고 |
|---|---|---|
| check-arch (nimtry) | ✅ **PASS** | SoC 위반 6건 수정 완료. baseline 4086개 (우리 코드 신규 경고 앵커 제거, 검증 가능한 재앵커만 잔존) |
| check-debt | ✅ **70/70 PASS** | nimtry DRIFT 0, architecture_debt 해시 재앵커 6건, projection 동기화 완료 |
| check-imports / check-mcp / check-determinism / env-check / check-nim-theater / check-decision-binding / doc-path-validator / topology-drift / decision-graph-drift / manifest-consistency / scope-consistency / sloc-verify | ✅ PASS | 최초 실행에서 check-debt·check-arch 외 실패 없음 (91 PASS 마커) |
| check-lean-vacuity / check-vacuity | ✅ PASS | 30개 .lean 파일 클린 (jinja 경고만) |
| check-mutation-harness | ✅ PASS | 스캐너가 3종 극장 패턴(M1 stub/M2 unmanifested/M3 sorry) 검출 |
| check-git-purity | ⚠️ **by-design** | 미커밋 트리에서 0-diff 실패(예상). 커밋 후 CI/`purity_check`가 검증하는 설계 |

**정리**: 워크트리 대상 17개 게이트 green + purity(커밋 후 검증 성격) 1개 → **S0–S4 변경이 기존 아키텍처/import/governance 불변식과 충돌하지 않음을 확인.**

## 2. 리팩터 내용 (게이트 실패 원인 수정 — G0 소속)

1. **SoC 리프 규칙 준수**: `src/core/types/*` 5개 모듈을 순수 데이터(리프)로 축소 —
   - digest 계산을 신규 `src/verification/selection/selection_digests.nim`으로 이전 (hash_kernel/cas_index/topology/engine/run_identity import 전부 이쪽)
   - `GraphUnresolvedEdge`(문자열 기반) 로컬 정의 + `toGraphUnresolvedEdge` 변환
   - `composeWithBaseRun`(BaseRunIdentity) digests 모듈로 이동
2. **ProofStatus SSOT**: 신규 `src/core/types/proof_status.nim`, `engine/proof_certificate.nim`은 `import+export`로 re-export (기존 소비자 무변경)
3. **타입 중복 제거**: `DerivationGraph` → `obligation_evidence` sibling import; `ChangedFile`→`DiffStatusEntry`(anti_theater의 DiffFile과 충돌 회피); `CacheEntry`→`ResultCacheEntry`
4. **§0.6 준수**: result_cache 순수 proc 3건(`store`/`load`/`deserializeEntry`) → func

## 3. 테스트 검증 결과 (16개 파일, 16/16 PASS)

selection_independence(19) · topology_resolution(9) · selection_types(31) · selection_report_determinism(12) · selection_engine(12) · plan_executor(8) · dag_executor(24) · projection_golden(6) · identity_collision(11) · result_cache(9) · proof_budget(7) · batch_uap_orchestrator(4) · z3_budget_clamp(6) · **test_dependency_digests(19)** · execution_identity_propagation(3) · test_d2_golden(14)

> batch_uap_orchestrator의 "FAIL[4]"는 테스트 자체 출력 "Error: 0" 라인을 오계수한 것 — 실제 [OK] 4건, [FAILED] 0건.

## 4. 파일 인벤토리

- 수정(14): Makefile · proof_budget / topology_dependency·engine·types / shadow_digests / dag_executor / loop_depth_scheduler·loop_driver / canonical_verification / identity(obligation) / semantic_target_extractor / proof_certificate / generated(build_metadata·type_registry·debt_constants) / architecture_debt.json / nimtry_baseline.json / dag_executor_test / topology_resolution_result_test / 2개 docs
- 신규: docs/spec/canonical_execution_semantics.md · docs/audit/selection_independence_audit.md · docs/reports/×4 · proof_status.nim · core/types 5종 · plan_executor.nim · result_cache.nim · selection/ 5모듈(engine·oracle·builders·digests·harness) · tests 9종 · tools 4종 · selector_soundness/symbol_mutation_catalog.json · data/benchmarks/identity_cost_probe.json

## 5. G2 확인 (dependencyDigests — 이미 랜딩된 wiring 검증)

- `identity.nim`: `computeDependencyDigests`(callee별 sha256, 정렬) + `computeSemanticBundleFingerprint`(H(receipt | sorted deps))
- `semantic_target_extractor.nim`: `collectSemanticDependencies`(IR irCall 수집, 자기재귀 제외, 사전/사후조건 포함, 결정적)
- `canonical_verification.nim`: bundleFp = receipt ⊕ depDigests (executionIdentity 공식 무변경, doAssert len=64 유지)
- 테스트 19/19: (b) semantic 변경→digest 변경→identity 변경(MISS 경로) / (c) incidental(경로·정렬) 변경→identity 불변(HIT 경로)
- **새 identity 스키마 없음** — 기존 Bundle 경로 채움. `result_cache`의 fail-closed(dependencyDigests 빈 값 reuse 금지)와 결합 시 semantic→MISS·incidental→HIT 양방향이 검증됨.

## 6. 상태점 선언

이 시점의 트리는 다음 작업(G3 실측, G4 커밋)의 기준점. G3가 추가하는 것은 측정 하네스/데이터뿐이며, 설계·wire 코드는 이 상태점에서 동결.