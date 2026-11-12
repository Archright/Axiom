# G2 S1 검증 기록 — 2-lane job-matrix 격리·실패 전파 실측 (2026-10-16)

> **종류**: 실행 증거 문서 (S1 acceptance record) — `docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md` §8의 S1 수용 조건 3항에 대한 관측 기록이다. 사전등록의 기준을 **변경하지 않는다** — 관측만 등록한다.
> **후보**: `probe/g2-matrix-candidate` @ `9e0b92eaf` (실험 제거 revert 상태 — 승격 대상 job shape와 동일 구조). 차량 = `h4-routing-measure.yml` dispatch 실험 `g2-matrix` (§8 장소 — 비권위 측정판, required check 아님). `probe-merge-queue`는 동결 유지, 미사용.
> **측정 명령**: 사전등록 §4.3 verbatim (jobs API steps[] started_at→completed_at, API 초).

---

## 1. 실행 런 (3)

| 런 ID | 목적 | 후보 SHA | 결론 |
|---|---|---|---|
| 38773944847 | 최초 green 관측 | `01ccdf247` | success |
| 38776105625 | 실패 주입 (lane-1에 `zz_g2_probe_fail` 스텁 — @`b0e1fda2a`) | `b0e1fda2a` | failure (의도됨) |
| 38777882135 | 주입 제거 후 clean 재관측 | `9e0b92eaf` | success |

## 2. 수용 조건 판정 (§8 — 3항 전부)

1. **양 레인 EXECUTED green (§2-iv)** — PASS. 3런 모두 양 레인이 신규 구조 위에서 실제 GO 테스트를 실행. S1 차량은 CAS staging이 없어 전 테스트 fresh EXECUTED (`DEC=""` — 의도된 S1 의미; production CAS 체인은 S2 승격 런에서 검증 — 본 문서 §5). `RUN make test-fast-one` + `PASS` 라인이 양 레인 로그에 관측됨 (production 어휘 그대로).
2. **injected-failure 런에서 양 레인 증거 동시 수집 (§3-1)** — PASS. 런 38776105625: lane-1 GO 스텝 conclusion=**failure** (17:22:06→17:25:58, 232 s), lane-0 GO 스텝 conclusion=**success** (17:22:13→17:27:33, 320 s) — **같은 런에서** 실패 레인과 성공 레인의 완결 로그가 동시 존재. `fail-fast: false`의 실증 관측 (lane-1 실패가 lane-0 취소를 유발하지 않음).
3. **집계 fail-closed (§3-2 상응)** — PASS. 런 38776105625에서 롤업 job(`g2-matrix-rollup`, needs+always + result==success 강제)이 **failure**로 닫힘 (17:27:40→17:27:44). skipped/cancelled 미관측이지만, needs.result 집계가 레인 실패를 그대로 승계하는 것은 관측됨. 깨끗한 런(1·3)에서는 롤업 success (3-4 s).

## 3. 측정 (§4.1 D4 — 스텝 1차값, API 초)

### 3.1 GO 스텝 duration (스텝 6, `[check] GO-critical admission tests`)

| 런 | lane-0 (s1a) | lane-1 (pi+d2g+d2p) |
|---|---:|---:|
| 38773944847 | 322 s | 211 s |
| 38776105625 | 320 s (green) | 232 s (FAILURE — 주입) |
| 38777882135 | 323 s | 189 s |

### 3.2 job wall / 셋업 (참고)

| 런 | lane-0 job wall | lane-1 job wall | 셋업(체크아웃→GO 직전) |
|---|---:|---:|---:|
| 38773944847 | 598 s | 466 s | ~230-234 s (빌드 스텝 226-230 s 포함) |
| 38777882135 | 580 s | 461 s | ~255-268 s (빌드 스텝 205-216 s 포함) |

**S1 특이 비용 주의**: S1 차량은 `exp-` 캐시 네임스페이스로 B 복원이 구조적으로 부재 → 각 레인이 **cold** `nim c`를 지불하고, `make ci-bootstrap` + `lake build ircheck` 빌드 스텝(205-230 s)을 레인이 자체 지불했다. **production 승격 구조는 이 둘을 지불하지 않는다** — bin/ax·ircheck는 job1의 manifest 검증 아티팩트로 공급되고, B-캐시 복원이 test-mode 컴파일 공급을 워밍한다 (J3 fold 유지). production D4-composite 기대 = max(lane GO) + per-lane setup(attest 프리앰블 상당, ~57-80 s) — G-A 모델 371 s와 정합 영역 (S1 cold GO 323 s가 이미 이 안에 들어온다).

### 3.3 runner 격리 (§2-ii)

각 런에서 양 레인이 **서로 다른 runner에 할당**됨 (Jobs API runner_name): 런1 = `GitHub Actions 1000023006` / `1000023005`, 런2 = `1000023056` / `1000023055`, 런3 = `1000023079` / `1000023078`. 레인 간 공유 파일시스템 0 — per-runner 격리 관측.

## 4. 편차 (사전등록 대비)

1. **S1 차량은 production 코드가 아닌 실험 job 복제판** — 셋업 레시피(job1 빌드 재수행, exp- 캐시)가 production attest 프리앰블과 다르다. §8 "후보 = 실제 production-shaped matrix 코드"의 취지(레인 구조·격리·증거의 동일성)는 충족하나, **공급망(아티팩트 다운로드 vs 자체 빌드)만 S2 production 구조로 대체**된다. S2 첫 production MG 런에서 이 대체부의 검증이 필요하다 (§5).
2. **CAS 체인 미검증 (범위 백)** — S1 차량은 CAS staging이 없어 DEC=""/fresh EXECUTED만 관측. Judgment-CAS plan/armed-attest 결속은 S2 production 런의 검증 항목으로 이월된다 (사전등록 §2-iv의 production 적용).
3. **롤업의 Jobs API 관측** — S1 롤업은 per-lane conclusion·runner를 Jobs API로 관측했다. production 롤업은 게이트 호출 그래프의 권한 상한(contents+pull-requests read — grant > callee 선언 위반 시 0-job startup_failure, 2026-09-26 실증) 때문에 `actions: read`를 요구할 수 없어 **needs.result 강제만** 수행한다. per-lane 관측은 run의 네이티브 job 목록으로 외부 관측 가능 (측정 도구 소관 — 게이트 아님).

## 5. S2 이월 검증 항목 (승격 후 첫 production MG 런)

- 양 레인 job이 **production attest 프리앰블**(job1 아티팩트 다운로드 + manifest 검증) 위에서 **RUN/PASS 라인과 실제 Judgment-CAS 기록**(basis=EXECUTED 우위 — REUSED 시 armed attest의 재검증 라인)을 남기는가.
- lane 판정파일 → attest job 다운로드 → armed attest의 subject 레코드 fail-closed 루프 통과.
- 집계: 레인 실패 → required check `admission-check` RED 전파 (production 권위 그래프).

---

*본 문서는 S1 실행 사실의 등록이다. 판정 기준의 원본은 사전등록(2026-10-16)이며 본 문서는 그를 변경하지 않는다.*
