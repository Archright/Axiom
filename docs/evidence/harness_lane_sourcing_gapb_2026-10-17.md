# 하니스 Gap-B 레인-어웨어 job 소싱 — prereg §10 Q2 승인 설계 (2026-10-17)

> **종류**: 측정 하니스 수정 기록 + 검증 산출물. `go_matrix_s3_readjud_post_leverb_2026-10-17.md` §4에 등록된 하니스 갭 중 **Gap B(레인-어웨어 job 소싱)** 만을 해소한다. 측정 정의(E3 §5.1 name-rule, §5.2 regime, A2.1.2 분류, prereg §4.1 값 정의, §5 합격 기준)·판정 규칙은 한 항목도 변경하지 않는다 — 변경되는 것은 **1차값의 소싱 채널**뿐이다.
> **권위**: GitHub Actions API(GET-only, api-second-granularity ±1s). 두 도구 모두 Reporter이며(Authority ≠ Adapter) merge-admission 판정을 대체하지 않는다.
> **승인 근거**: `go_matrix_parallelization_prereg_2026-10-16.md` §10 Q2(2026-10-16 append-only 재결 — **APPROVED "수집 채널 적응", 1차 값 정의 불변**). Gap A(PR #890)와 달리, 본 변경은 §10 Q2의 승인 범위 **그 자체**다(§5 처분 참조).
> **소비처**: merge-latency measure→change→measure 루프의 v2 세대(AFTER) 측정 — `go_step`·`classification`의 fail-closed 기록(`null`/`UNKNOWN_LOG`) 해소.

## 1. 블랙아웃 (수정 전 — 매트릭스 세대 1차값 수집 두절)

G2 세대(2026-10-15T20:49:46Z 경계 런 38805085401 이후)는 GO-critical 4종이 소비 job(`attest / admission-check`)의 직렬 스텝에서 2-레인 job matrix `attest / go-critical-lane (0)` / `(1)`로 이동했다(prereg §1, `.github/workflows/admission-check.yml` go-critical-lane). 동결 하니스는 소비 job만 소싱하므로 매트릭스 런에서:

- **`merge_latency_audit.sh`** — 소비 job steps[]에 `[check] GO-critical` 스텝이 없어 `go_step=null`; 소비 job 로그에 `[admission-tests]` RUN/SKIP 행이 전무(skip=0 ∧ run=0) 하여 A2.1.2 기계규칙이 `UNKNOWN_LOG`로 기록(fail-closed — 침묵 아님). 실측(origin/main @ c9cca2655, 2026-10-17):

  | run | go_step | regime | classification |
  |---|---|---|---|
  | 38925131342 | null | L | UNKNOWN_LOG |
  | 38913175446 | null | L | UNKNOWN_LOG |
  | 38891209338 | null | H | UNKNOWN_LOG |

  (regime은 a-restore 마커가 소비 job 로그에 존속하여 이미 해소 — `harness_v2_gate_recognition_2026-10-17.md` §3 관측과 동일. 본 변경의 대상은 `go_step=null`·`UNKNOWN_LOG` 두 축이다.)
- **`go_critical_parallel_extraction.sh`** — job 소싱이 `attest / admission-check`로 하드핀되어 D4 전부 NA(`go_mode=none`). prereg §10 Q2가 기록한 드라이런 재현(PR #864, 런 38805085401): "기계적 exit 0이나 D4 전부 NA — 동결 명령이 매트릭스 형상에서 1차값 수집에 실패하는 것의 정확한 재현".

## 2. 수정 — 소싱 채널 적응 (1차값 매핑 명시)

### 2.1 `merge_latency_audit.sh` (steps-matcher + A2.1.2 코퍼스)

| 사이트 | 변경 |
|---|---|
| `GO_STEP_RE` | `'^\[check\] GO-critical'` → `'^\[(check|lane)\] GO-critical'` — 정확히 하나의 disjunct 추가. 매칭 대상은 레인 job의 `[lane] GO-critical admission tests (DEBT#432 — lane N, fail-closed)` 스텝뿐이다(워크플로 전수 대조: 그 외 `[lane] *` 스텝은 존재하지 않음). |
| 신규 | 레인 job 해석: `attest / go-critical-lane (0)` / `(1)`, conclusion `skipped`/`null` 제외(실행되지 않은 레인은 소싱하지 않는다 — PR-venue skip 확장 포함). |
| `gostep.jq` | **job별 다중매치 합산(기존 규칙 불변) → GO-bearing job들 간 max** 감소로 재작성. 직렬 세대는 GO-bearing job이 1개 → max = 기존 합산과 바이트 동일. 매트릭스 세대는 두 레인 GO 스텝이 병행 실행되므로 임계경로 GO 지속 = `max(lane-0 GO, lane-1 GO)` — prereg §5(a) D4-parallel-composite의 GO 성분 공식과 정확히 합성된다. 합(Σ)이 아닌 max인 이유: Σ는 어느 스텝의 지속값으로도 존재하지 않는 병렬 이중계수 수량이며, §5(a)가 이 값을 그대로 소비한다. (대조 — 추출기의 `go_lane_sum_s` 컬럼은 동결된 정의 그대로 Σ = "GO 스텝 테스트 소요" 합산이다. 두 도구가 서로 다른 동결 수량을 각각 유지한다: audit = 임계경로 지속, extractor = 테스트 소요 합.) |
| A2.1.2 코퍼스 | 분류 입력을 소비 job 로그 + 레인 job 로그의 **합집합**으로 확장. SKIP/RUN 산정 grep 패턴·기계규칙 자체는 한 글자도 변경 없음. 로그 내 스텝 소스 echo 행(`…Z     echo "[admission-tests] SKIP — $t …"`)은 앵커 패턴(타임스탬프 직후 마커)이 비마치므로 오탐 없음(실측 확인). |
| regime | **변경 없음** — 소비 job 로그의 a-restore 마커(E3 §5.2 권위). 레인 job도 각자의 a-restore 마커를 출력하지만(관측: 런 38925131342 레인0 51192 ms vs 소비 30652 ms — 별도 restore), 이는 관측으로 기록할 뿐 공변량 교체는 측정 정의 변경이므로 하지 않는다. |
| additive 레코드 필드 | `go_step_source_jobs`(GO 매치가 기여한 job id 배열), `lane_jobs`(`{name, job_id}` 배열) — schema `axiom.merge_latency.run/1` 유지, 기존 필드 무변경 뒤충가. summary `rules` 문언 2건 갱신(값 규칙 불변, 소싱 채널 문언만). |

### 2.2 `go_critical_parallel_extraction.sh` (D4 배치 추출기)

| 사이트 | 변경 |
|---|---|
| job 소싱 | 소비 job 해석(기존 불변)에 더해 레인 job 2종을 해석, 실행 레인 로그만 코퍼스에 추가. 코퍼스 순서 고정: 소비 → lane-0 → lane-1(LC_ALL=C sort). |
| 로그 파서 | **무변경** — 기존 듀얼모드 파서 그대로. 임의 LANE 행이 로그를 lane 모드로 전환하고 4종 테스트는 서로소 집합(레인당 하나의 LANE 행)이므로 연결 코퍼스에서 per-test `lms[]`가 완성된다. §4.3 동결 명령의 로그 라인 1차값 경로(레인 job 로그 + `duration_ms`)와 동일 1차값. |
| `a_restore_ms` | **변경 없음** — 소비 job 로그 전용(E3 §5.2, audit과 동일 판정). |
| `supply_entries` | 코퍼스 전체의 첫 `[test-supply]` 행. 직렬 세대: 소비 행(바이트 동일). 매트릭스 세대: 소비 job은 supply 행이 없으므로 lane-0의 행(단일 컬럼 스키마 유지 — per-lane 값은 레인 로그에 원본 보존). |
| `gc_fired` | 직렬 세대: 기존 `PASS — 4/4 …` grep 그대로. 매트릭스 세대: 소싱한 **모든 레인**이 자신의 `PASS — <n>/<n> GO-critical admission tests green` 집계행을 보유해야 yes(4/4 집계행은 이 세대에 존재하지 않음 — 정의적 부재를 "no"로 기록하는 위음성 제거). |
| `gc_span_s` | lane 모드에서 NA 유지(단일 cross-lane span은 존재하지 않는 수량 — 레인 steps[] 벽시계는 신규 컬럼의 job id로 외부 재인출 가능). |
| **LANE 행 매처 수정 (잠재 결함 — 본 소싱 변경이 표면화)** | 듀얼모드 파서의 정규식 `LANE [A-Za-z0-9_]+ duration_ms=`는 생산 포맷 `LANE lane=<N> <slug> duration_ms=`와 **불일치**했다(`lane=<N> ` 접두어가 slug 매치를 파단 — admission-check.yml go-critical-lane 스텝의 verbatim 출력). 동결 추출기는 소비 job 로그만 소싱했으므로(레인 행 부재) 이 결함은 관측 불가능했다. 레인 로그가 코퍼스에 합류하자 파서가 레인 로그를 **serial RUN→PASS 경로로 조용히 파싱**하는 오표기가 최초 검증에서 관측됐다(값은 근사하지만 채널 표기 오류 + `go_lane_sum_s=NA` — 출항 금지). 수정: `lane=<N> ` 선택 그룹 추가(구형 `LANE <slug>`도 수용). 이로써 §4.3이 승인한 duration_ms 1차값 경로가 실제로 발화한다. 단위시험: 레인 0+1 코퍼스(런 38925131342) → `49.0 260.5 151.8 32.5 NA lane 493.8`; 레인 0 단독 → `NA 260.5 NA NA NA lane NA`(결측 삼킴 없음). |
| TSV 스키마 | 뒤충가 2컬럼: `go_lane0_job_id`, `go_lane1_job_id`(부재 시 `-`). 기존 22컬럼 무변경. |

### 2.3 세대 퇴화 (하위호환)

직렬 세대 런에는 레인 job이 존재하지 않는다 → `lanes_tsv`/`LANE_IDS` 공집합 → 모든 확장 분기가 구경로로 퇴화한다. §3.2의 바이트 비교로 입증.

## 3. 검증 (전부 GET-only, 산출물 /tmp)

### 3.1 양성 — 매트릭스 세대 3런 (audit)

`merge_latency_audit.sh --runs 38925131342,38913175446,38891209338 --out /tmp/gapb_pos` → **exit 0**

| run | go_step (구→신) | regime | classification (구→신) | RUN/SKIP 행 | go_step_matches | go_step_source_jobs |
|---|---|---|---|---|---|---|
| 38925131342 | null→**261** | L | UNKNOWN_LOG→**EXECUTED** | 4/0 | 2 | 레인 2 job id |
| 38913175446 | null→**334** | L | UNKNOWN_LOG→**EXECUTED** | 4/0 | 2 | 레인 2 job id |
| 38891209338 | null→**260** | H | UNKNOWN_LOG→**EXECUTED** | 4/0 | 2 | 레인 2 job id |

**독립 교차검증**: 각 레인 GO 스텝의 steps[] API 직접 조회 — 38925131342: lane0 261 s / lane1 233 s → max 261 ✓; 38913175446: 334/243 → 334 ✓; 38891209338: 260/241 → 260 ✓. `stats.executed_only.go_step_s` n=3 (mean 285, p50 261, min 260, max 334, sd 42.4). `counts`: executed=3, unknown_log=**0**. `stats.all_operational`(wall 800.3±130.8, dur_sum 778.7±130.5, gaps 17.3±0.6, residual 4.3±0.6)은 Gap-A 문서 §3의 값과 동일 — 측정 불변 확인.

**추가 스펙시멘(창 끝단)**: 런 38981663204(2026-10-16T23:28) → `go_step=182`, EXECUTED, regime H, RUN 4 — 창 후반 런에서도 동일 동작.

### 3.2 회귀 — 직렬 세대 (audit)

런 38106561118(v1 세대, 2026-10-11)을 origin/main 도구와 본 도구로 각각 측정: **측정값 전부 바이트 동일**(wall 670, dur_sum 652, gaps 13, residual 5, go_step 277, matches 1, a_restore 49069, regime H, EXECUTED, RUN 4/SKIP 0). 차이는 `collected_at` 타임스탬프와 §2.1의 의도적 rules 문언 2건뿐이다. 직렬 세대 additive 필드 퇴화 확인: `lane_jobs=[]`, `go_step_source_jobs=[소비 job id]`.

### 3.3 음성 대조 (audit)

`merge_latency_audit.sh --runs 38977368334` (landing-integrity) → **HARD-FAIL exit 1** — `[mla] HARD-FAIL: run 38977368334 path '.github/workflows/landing-integrity.yml' is not an admission-gate run …` — Gap A의 음성 대조와 동일 결과, 가드 불변.

### 3.4 검증 — 추출기

- **v1-path 창(2026-10-15T18:00Z~, 42런)**: origin/main 추출기와 본 추출기 대조 —
  - **직렬 2런(38787538389, 38796772058)**: 행 열 1–22 **바이트 동일**(예: 38787538389 `52.2 307.3 158.3 33.4 serial`, gc=yes).
  - **모드 전이**: 17건 `none→lane`(매트릭스 런 소싱 성공), 23건 `none→none`(GO 데이터 없는 직렬 로그 — 변경 없음), 2건 `serial→serial` — 역전·오표기 0건.
  - **경계 런 38805085401**: 구버전 `none/NA` → 신버전 `lane`, 4종 1차값 **50.3 / 361.3 / 156.4 / 32.6 s**(ms 원값 50323 / 361255 / 156431 / 32650 — S3 수작업 레인 원장 `data/merge_latency/g2matrix_d4_lanes.tsv`와 일치; 32.6은 32650 ms의 `%.1f` 반올림 절반값 표기), `go_lane_sum_s=600.7`, gc=yes, supply=0(lane-0 콜드), a_restore는 소비 로그 원값 유지.
- **v2-path 창(2026-10-16T00:00Z~, 24런 — 구버전 전부 `go_mode=none/NA`)**: **MG 매트릭스 12런 전부 `go_mode=lane` + `go_lane_sum_s` 산출(NA 0건)**, PR-venue 12런 `none`(레인 skip — 올바른 퇴화). 표본: 38925131342 `49.0 260.5 151.8 32.5 lane 493.8`(§2.2 오프라인 단위시험과 정확히 일치), 38981663204 `38.8 174.2 117.3 25.1 lane 355.5`.
- **재실행 안정성**: 창 재실행 간 GO 값 컬럼(17–22) 바이트 동일. 유일한 차이는 1런의 `a_restore_ms` 일회성 로그 조회 지연(NA vs 25933 — API 일시 결격, 재실행으로 해소) — 1차값 경로는 결정적.
- 실행 명령: `go_critical_parallel_extraction.sh runs 2026-10-15T18:00:00Z|2026-10-16T00:00:00Z <out>`(v1 회귀는 /tmp 복제본 WF 치환판 사용 — 리포 파일 불변).

### 3.5 무표본 경로 (정직 기록)

- **실패 레인 스펙시멘 없음**: 매트릭스 세대의 merge_group 게이트 런은 전부 success(2026-10-15T20:00Z 이후 실패 conclusion 0건) — 실패 레인에서의 steps max 감소·분류 동작은 라이브 표본 없음(규칙 코드는 기존 그대로: gostep success-step 필터, A2.1.2 기계규칙).
- **레인 SKIP(판정-CAS REUSED) 스표시멘 없음**: 표본 런(38981479662, 38981663204 등)의 레인 로그는 4종 전부 RUN — FULL_REUSE/PARTIAL_REUSE 분류 경로도 라이브 표본 없음(규칙 코드 불변).
- **`--no-logs` 경로**: 런 38925131342 → `go_step=261`(steps 레코드 평면 — 로그와 무관), `classification=UNKNOWN_LOG`·`regime=unknown`(로그 억제 시 기존 fail-closed 동일).

## 4. 발견 사실 (범위 밖 기록 — Follow-up)

- **동결 파서의 잠재 결함(본 차량에서 수정 — §2.2 표)**: 듀얼모드 LANE 정규식이 생산 포맷과 불일치(`lane=<N> ` 접두어 파단). 레인 로그 코퍼스 합류 없이는 관측 불가능했고, 합류 후 최초 검증에서 serial-경로 오표기로 포착 — 출항 전 수정. §10 Q2가 승인한 duration_ms 1차값 경로가 이 수정으로 비로소 실제 발화한다.
- 매트릭스 세대는 v1 경로(`admission-gate.yml`) 시대인 2026-10-15 밤부터 시작되었다(경계 런 38805085401의 path = v1). 따라서 **v2 경로의 직렬 런은 존재하지 않으며**, 추출기의 직렬 회귀 검증은 v1-path 사본(본 차량 /tmp 복제본만 WF 치환 — 리포 파일 불변)으로 수행했다(§3.4).
- 레인 job은 각자의 a-restore 마커를 출력하며 소비 job의 마커와 이형일 수 있다(§2.1 regime 행: 런 38925131342 레인0 51192 ms vs 소비 30652 ms). 공변량 재정의 여부는 측정 정의 판단이므로 본 차량에서 유보한다.
- 실패 레인·레인 SKIP(판정-CAS REUSED) 스펙시멘은 매트릭스 세대에 아직 없다(§3.5 — 무표본 경로 정직 기록).

## 5. §2.5 처분 (비례 차량 근거 — Gap-A §5 정정 문안 계승)

- **AGENTS.md §2.5 전문**(`docs/agents/ci_epoch_cutover.md`)의 CI 변경 정의 목록 항목 (verbatim): "CI를 검증하거나 CI의 trust boundary에 영향을 주는 스크립트·설정 변경" — 본 하니스 2종은 CI를 검증하는 측정 스크립트이므로 §2.5 차량이 적용된다.
- **prereg §10 Q2**(`go_matrix_parallelization_prereg_2026-10-16.md` §10, verbatim 요지): D4 추출기의 레인-어웨어 job 소싱 → **APPROVED(수집 채널 적응)**, "배치 추출기의 job 소스를 레인 job으로 확장하는 것은 수집 채널 적응이며 … **승인**한다. **1차 값 정의 불변.**" + "**범위 포함 (audit steps-matcher)**: `merge_latency_audit.sh`의 steps-matcher도 동일 취지의 레인-어웨어 job 소싱으로 확장한다(레인 job에서 GO 스텝을 소싱 — `go_step=null` fail-closed 기록의 해소)". — **본 차량이 수행한 변경은 이 승인 범위 그 자체다.** Gap-A(PR #890)에서 지적된 범위 과잉 인용 문제는 여기서 재발하지 않는다: §10 Q2의 "도구 구현 변경은 별도 차량에서 수행한다" 문언은 본 소싱 변경의 구현 차량 지정이며, 본 차량이 그 차량이다.
- **근거**: (a) prereg §10 Q2의 사전 승인(위 인용 — 본 변경의 재결을 직접 담당), (b) 사용자 명시 허가(2026-10-17, "권한이 필요한 부분은 전면 허가한다").
- **처분**: epoch-record형 본 증거 기록 + 표적 검증(§3) + 일반 큐 PR 착지는 **AGENTS.md §2.5의 권한 조항에 따른 사용자 명시 허가 아래에서 적용**한 것이다(수행자의 경미성 독자 판정이 아님 — Gap-A §5 정정 문안 계승). 본 변경은 활성 실행 경계(게이트·워크플로·required-check)를 일절 변경하지 않는 읽기 전용 리포터의 소식 채널 정합화다 — 상태 혼합이 아니라 관측 정합화이며, coherent-generation 전환 의식 불요 판단도 수행자 몫이 아니라 위 (b) 허가 아래 유효한 것이다.

## 6. 재현

```bash
# 양성 (매트릭스 3런 — go_step/regime/분류 해소)
bash tools/ci/merge_latency_audit.sh --runs 38925131342,38913175446,38891209338 --out /tmp/gapb_pos
# 회귀 (직렬 세대 — 구현 전후 비교 대상은 git show origin/main:tools/ci/merge_latency_audit.sh)
bash tools/ci/merge_latency_audit.sh --runs 38106561118 --out /tmp/gapb_serial_new
# 음성 (exit 1 필수)
bash tools/ci/merge_latency_audit.sh --runs 38977368334 --out /tmp/gapb_neg
# 추출기 (매트릭스 창 — go_mode=lane 전환)
bash tools/ci/go_critical_parallel_extraction.sh runs 2026-10-16T00:00:00Z /tmp/gapb_d4_v2
```
