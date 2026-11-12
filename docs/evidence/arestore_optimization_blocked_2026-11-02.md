# A-restore 성능 최적화 슬라이스 — 설계-계약 검증 BLOCKED 종결 기록

> **판정**: **BLOCKED** (2026-11-02). A-restore 최적화의 양 메커니즘 모두 선택 기준 미충족 — "안전성을 증명할 수 없다면 BLOCKED가 정답" 규칙 발동. 구현·착지 절차(메커니즘 선택 → 최소 diff → 부정 시험 → 세대 착지)는 전면 소멸.
> **관측 프로토콜**: 본 분석 전 과정 GET-only(`gh api`·`git`·파일 읽기) — 저장소 mutation 0건.
> **선택 기준 3항목**: 계약 무손상 AND 최소 변경 AND 실제 절감 발생 — 양 메커니즘 모두 미충족.

## 1. 배경 — 후보 선정 경위

merge_queue admission-gate critical path 분해(2026-11-01, `docs/evidence/merge_queue_dag_attribution_2026-11-01.md`)에서 성능 후보 4종(evidenceId check·setup 재프로브·A-restore·Provider 다운로드 비대칭)이 특정됐고, A-restore가 5기준 평가(최소·이상·우아·근본·결정론)를 통과해 설계-계약 검증 대상으로 승격됐다:

- 체인 setup ≈155-165s 중 A-restore ≈114s (경합 팽창 29.3s→51-60s·admission-check 재복원 31.3s)
- 기대 절감 p50 40-60s (당시 추정 — 본 검증에서 ~23s로 교정, §3-(d))
- GO tests 이중 분포는 판정 CAS `basis=REUSED` 발화 결정론적(85런 전수) — 최적화 대상 제외 확정

## 2. 메커니즘 2 (재복원 제거/대체) — 기각: 계약 무손상 불가능 (fail-closed 체인 파괴)

attest/admission-check의 A-restore는 "가속"이 아니라 **검증 체인 stage-b/c의 실행 재료 공급**이다:

- attest witness-only는 전체 체인 (a)–(f)를 실행 — `src/cli/cert_cli.nim:836-838` "Runs the kernel chain stages (a)-(f) EXACTLY as the full attest does"
- **stage-b (추출 대조)**: `runExtractionAgreement(...ircheckExe...)` — `src/verification/attestation_orchestrator.nim:672-686`. ircheck는 lake `lean_exe`(`proofs/lakefile.lean:35-38`, Lean 런타임 링크)이고 바이너리 부재 시 fail-closed(`src/verification/extraction_agreement.nim:168-177`)
- **stage-c (커널 재실행)**: `reexecuteLean` + `reexecuteZ3` 무조건 호출 — `attestation_orchestrator.nim:698-703`. 기본 호출이 `lake env lean`(`src/verification/kernel_reexecution.nim:289-290`) → lean+lake 동시 필수. z3는 checksum pin miss 시 krZ3Error fail-closed(`kernel_reexecution.nim:321-323`). 판정 매핑은 krPassed 외 전부 FAIL(`attestation_orchestrator.nim:376-381`) — lean 부재 = attest red
- **b+c 스킵은 casHit뿐**(`attestation_orchestrator.nim:831-841`); casOff/casMiss는 항상 b+c 실행. 신규 헤드 착지는 전부 MISS(evidence key가 헤드 고유)이며, 실제 evidence 4종 전부가 leanSource 163B + smtlib2 223B를 내장(`data/trusted/evidence/*.json` 실측)
- **2026-10-12 verdict-leg 전례는 이전 불가**: 그 게이트는 verdict leg가 "lean/lake 실행 없음, z3 실행 없음, ircheck 실행 없음"을 실행 테스트로 증명했기에 GO였다(`docs/evidence/verdict_payload_gate_2026-10-12.md:53`, §5 GO :150-166). attest는 정확히 반대 — lean/z3/ircheck/nim(core_purity_gate, `admission-check.yml:1007` + `Makefile:380-381`)을 매 착지 소비
- **J3/프로브 커버리지**: Lean 툴체인(~0.5GB+)을 base artifact(39.7MB)에 실으면 A-cache를 더 느린 채널로 재건하는 것(artifact는 3일 retention·런 간 dedup 없음)이고, 기존 A-verify+기능 프로브(`action.yml:337-393, 669-728, 908-924`)가 지키던 공급 무결성을 Lean 페이로드용으로 재창출해야 함 — 순비용, 절감 0

## 3. 메커니즘 1 (경합 완화) — 기각: 전제 구성 오류 + 절감 증명 불가 + 재배치 문제

### (a) 관측 전제 교정 — "build/closure/lane0/lane1 4잡 동시" 구성 오류

- **closure-deriver는 동일 캐시가 아님**: org 오케스트레이터가 action을 `@18b180094a19096f15a268eeb110a1c7f2f4cfba`(PR #906, 구버전)에 핀(`Archright/.github` admission-gate-v2.yml:265-267). action.yml 바이트가 main과 다름(sha256 `46397e44…` vs main `17f04e39…`) → script_hash(`action.yml:194`) 상이 → 다른 A-키 — 같은 엔트리 경합 아님
- **lane0/lane1은 build 종료 후 시작**: `needs: [build-base-artifacts]`(`admission-check.yml:2891`), 간선 슬랙 p50 0.0초(DAG 보고서 `merge_queue_dag_attribution_2026-11-01.md:111-113`) — build의 복원 창과 겹칠 수 없음

### (b) 실제 동일-키 동시 복원 창 — 헤드 t≈22-90s에 4-way(+1)

| 잡 | setup 위치 | 스코프 |
|---|---|---|
| build-base-artifacts (체인 헤드, critical path) | `admission-check.yml:331-334` | full |
| debt-registry-gate | `debt-registry-gate.yml:5, 22` | full(기본) |
| axiom-operational-slice | `axiom-operational-slice.yml:16, 39` | full(기본) |
| observer-manifest-consistency | `observation.yml:21, 46-50` | full |
| generation-acceptance (조건부) | `generation-acceptance.yml:53, 267-268` | full |

전부 merge_group 트리거 단일잡 워크플로, 현행 action 바이트(머지 큐 커밋 트리) → 동일 a-key. 경합은 실재하며 build는 당사자다. 단, 레인 창(t≈100s)의 lane0∥lane1 2-way도 동일-키.

### (c) 스태거링은 경합을 제거하지 않고 재배치한다

밀려난 3-4개 복원이 lane 창으로 겹치면 최장 잡(lane 374s, max 817s — DAG 보고서 §3)이 팽창. 피하려면 lane 창을 넘는 sleep(≈400-800s) 상수가 필요하며, 이는 세대·provider별로 무너지는 클럭 추격이다.

### (d) 절감 입증 불가

기대 절감 ≈ 헤드 팽창분(52→29.3s, ~23s — 초기 추정 40-60s에서 교정). 경합-팽창 인과 곡선(단일/2-way/4-way 복원 wall)의 측정 증거가 없고(verdict gate는 단일 스트림 전송률만 보유), 효과 크기는 측정 노이즈 미달 — provider 세대 스윙이 P95 ±1200s(failover 2310.7s vs gen12 1133.4s, DAG 보고서 §8.4)인 상태에서 R-7 n≥30 Before/After로 23s를 식별할 수 없다. "실제 절감 발생" 기계 검증 주장 불가.

## 4. node24 세대 전환과 A-cache 키 — 콜드 시대 예측과 실측

- **키 입력은 4개뿐**: `a_key = 접두사 + RUNNER_OS + gcc_fp + glibc_fp + script_hash`(`action.yml:189-204`); `script_hash = sha256(action.yml + nimble.lock)`(`:194`). 워크플로 파일 바이트와 node 런타임은 키 입력이 아님 — composite action은 node 코드를 실행하지 않음(전 스텝 `shell: bash` 또는 고정 action)
- **node24 전환 자체는 키를 회전시키지 않는다.** 단, actions/cache 재핀(`:332, :398, :959`의 `0057852b`)이 node24 대응 버전으로 필요해지면 action.yml 바이트가 바뀌고 → script_hash 회전 → A 전체 + B(a_fp=`sha256(a_key)`, `:301` — recipe 구성에 포함 `:300-302`)가 **1회 콜드 시대**에 진입(메커니즘은 `action.yml:51-53` 헤더 명시)
- 부수 결합: repo 측 action 변경은 org 핀(`@18b1800`) 소비자(closure-deriver·gateway)에게 전파되지 않음 — org 핀 bump는 별도 일관 세대 전환(§2.5). org의 admission-check 핀이 main에서 뒤처지면 build/lane/attest의 키와 repo 워크플로들의 키가 분리됨(2026-11-01 기준 pin==main 확인)

**콜드 시대 실측 (완결 — 2026-11-02, node24 repo PR #1189 CI 관측)**: composite action.yml cache 핀 회전 → script_hash 회전 → 콜드 시대가 **실현·워밍·회복 전 과정 관측**됐다:

- **1차 시행 (콜드)**: A-cache 전체 MISS(`AXIOM_CACHE_A_PROBE: FAIL — compiler/ast.nim missing (stale/broken ~/.choosenim); purging` → native install fallback). 콜드 native install에서 nim-lang.org Nim 2.2.10 다운로드 CURL 실패(일시적 네트워크, `Failure when receiving data from the peer [CurlError]`)가 closure-deriver·axiom-operational-slice 잡 red 유발 — admission-check 집계 잡은 상류 fail을 fail-closed로 정확히 전파(**P1 실패 전파 계약의 실운영 검증**)
- **재실행 (rerun-failed-jobs, REST API)**: 전체 green — closure-deriver 1m16s · axiom-operational-slice 7m39s · verdict/admission-check 1m23s · admission-check(집계) 4s. CI 전체 wall ≈13.9분(01:01:40 첫 잡 시작 → 01:15:32 마지막 잡 완료, `gh pr checks --watch` exit 0 관측)
- **해석**: op-slice 재실행 7m39s는 콜드 시대의 워밍 비용 실측(캐시 부분 세이브 상태에서 native install 잔존). 콜드 시대는 1회성이며 이후 표본이 세대 안정 wall로 수렴하는지는 node24 세대 운영 표본에서 관측한다

## 5. 잔여 후송 (양 메커니즘 밖 — 비권장 참고)

attest의 A-restore를 **Lean + ~/.local/bin 전용 축소 스코프**로 줄이는 것(core_purity_gate를 base artifact 멤버로 이동해 choosenim+nimble 탈락 — verdict 핸드오프 패턴 재사용)만이 계약을 유지하면서 절감(~12-15s)을 낼 수 있는 경로다. 그러나:

- "제거"가 아닌 "축소"이며, action.yml 편집 → 전면 키 회전(콜드 1회) + a-verify/프로브 분기 추가 + 측정 사이클 수반
- 본 슬라이스의 두 메커니즘 선택 대상이 아니며, 별도 사전등록 워크스트림으로만 검토 가치가 있음 — 이 기록에는 참고로만 남긴다

## 6. 결론

| 메커니즘 | 판정 | 근거 요약 |
|---|---|---|
| 2 — 재복원 제거/대체 | **기각** | attest A-restore = stage-b/c 실행 재료 공급 — 제거 시 fail-closed 체인 파괴 (§2) |
| 1 — 경합 완화 | **기각** | 전제 구성 오류 + 스태거링은 재배치 + ~23s 절감은 노이즈 미달 기계 검증 불가 (§3) |

A-restore 슬라이스는 BLOCKED로 종결한다. 성능 개선은 실제 병목 관측(provider epoch 안정성·러너 배정 지연·상위 2잡 실행시간 — 자연 관측 과제)에 근거한 별도 사전등록 슬라이스로만 재개할 수 있다.

---

*본 문서의 file:line 인용은 2026-11-02 기준 `git show origin/main:<path>` blob 라인 번호. 설계-계약 검증은 2026-11-02 설계-검증 에이전트 보고를 정본화한 것이다.*
