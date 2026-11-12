# node24 세대 merge_group 잡 내부 비용 분해 (job decomposition) — 2026-11-02

> **종류**: 성분 분해 분석 기록 (component decomposition analysis) — node24 신세대(ciGeneration N+8) merge_group 배치의 Critical Path 잡(`attest / go-critical-lane`·`attest / admission-check`·`verdict / admission-check`) 내부 step 비용 귀속. 소비 대상: CI 시간 최적화 로드맵 4.75(절감 후보 사전등록)의 판정 입력 또는 BLOCKED 근거. 본 문서는 코드·워크플로·게이트·판정 의미론을 변경하지 않는다(관측·분석만 — GET-only).
> **규율 원천**: 형식·절차 계보 `docs/evidence/attest_job_decomposition_2026-10-12.md`(직계 형식 — 표본 열거·분류·코호트·부록 전수 분류 장부·§7 재현 명령) · 실행 계획 v4.2(잡 내부 비용 귀속 Vertical Slice — 대상 잡·분류 축·경합 증거 기준·관측 한계 사전 고정) · 표본 규칙 `docs/evidence/slo_official_measurement_prereg_2026-11-01.md` §5·§7(진단 모집단 허용·창 고정·전수·제외 사유 공개 — 본 표본은 공식 SLO 모집단을 대체하지 않는 진단 표본 선택) · 관측 quirk `docs/spec/gh_run_observation_quirks.md` Q16(merge_group 목록 누락)·Q17(jobs labels 배열) · 경합 분류 기준: 동시 실행 구조 증명 + 자원 공유 신호(동일 runner_id·캐시 키·lock 오류) 또는 복원 시간 인과 곡선 없으면 경합 아님(UNKNOWN 유지).
> **권위**: 런/잡/스텝 존재·타임스탬프·결론 = GitHub Actions REST API(GET-only, jobs 조회 `filter=latest` 명시, 표본 전부 `run_attempt=1`). 판정 재사용 basis = 레인 판정 아티팩트(`judgment-decision.json`·`go-exec-records/*.json` — 다운로드 후 jq 판독). 본 문서는 Reporter다 — 병합 판정 권위(GitHub ruleset 25218071·23943917, merge queue)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> **측정 기준**: api-second-granularity(±1 s) · step wall = `completed_at − started_at` epoch 차감(jq `fromdateiso8601` — `data/ci_provider/census_20261101T125932Z/summary.txt:41` 계보; 원문 타임스탬프는 §7 재현 명령으로 인출) · skipped 판별자 = `conclusion == "skipped"`(타임스탬프는 시작=종료 동일 시각일 수 있음 — '실행 안 됨' 마킹, 0초 실행 아님) · 표본 n=2(코호트별 n=1 — 분포 추정 아님, mean/sd 미산출).

## §1 배경과 질의

실행 계획 v4.2가 남긴 질의: node24 coherent generation 착지 이후, Critical Path 잡의 **내부** 비용을 읽기 전용으로 귀속하고, 검증 의미론을 건드리지 않는 절감 후보를 최대 1개 선정하거나 BLOCKED 근거를 정본에 기록한다.

선행 판정의 위치: 잡 간 연결(직렬 tail) 조사에서 제거 가능 edge 0건(merge_queue DAG 귀속 보고서 2026-11-01), A-restore 최적화는 계약 검증 실패로 BLOCKED 종결(PR #1192), GO tests는 REUSED 발화 결정론이 85런에서 확인됨. 남은 미조사 영역은 잡 내부 step 비용이며, GitHub Jobs API `steps[]`(공식 스키마 — `started_at`·`completed_at`·`conclusion`)가 이미 그 관측 채널이다.

**출처 정정**: 2026-11-02 미커밋 에이전트 보고의 "lane 374s·evidenceId 108.5s·setup 내 A-restore 114s" 수치는 본 문서에서 재사용하지 않는다(원시 관측값 미보존·인용 불일치 — v4.2 §검증 표의 정정 판정 준수). 본 문서의 정본 수치는 전부 이하 §7 재현 명령으로 재도출된 값이다. 커밋된 DAG 보고서의 잡 수준 wall(lane 292s·admission-check 222s — 2026-11-01 관측, 구세대·다른 창)은 본 표본과 별개 모집단이며 상호 대체하지 않는다.

## §2 표본 — 열거·분류·코호트

**관측창(사전 고정)**: `[2026-11-02T08:12:08.926Z, 2026-11-02T09:13:00Z]`.
하한 근거: node24 세대 착지 시각 = 양 org ruleset 재핀 readback PASS 중 늦은 쪽 — ruleset 23943917 `updated_at` 2026-11-02T17:12:08.926+09:00(=08:12:08.926Z), ruleset 25218071 08:11:42.586Z, 양측 핀 `7eaa9624` readback 일치. 상한 근거: 표본 수집 종결 나열 시각(큐 비어 있음·창 종결 시점 진행 중 런 없음). 창 외 사후 편입 금지.

**열거 조건**: `event=merge_group ∧ path=admission-gate-v2.yml ∧ created ∈ 창 ∧ run_attempt=1` — 전수(체리피킹 없음). Q16 준수: 창 내 총 merge_group 런 16건(2 배치×8 워크플로, 각 질의 `total_count=16<1000` — 분할 필요 없음), run-id 중복 제거 확인, 대상 2런은 단일 런 GET으로 교차검증(목록이 아니라 단일 GET이 권위). 창 시작~첫 배치 디스패치(08:12:09Z~08:39:20Z) 사이 merge_group 런 부재를 별도 필터 쿼리로 확인(07:00Z~08:39:19Z의 24런은 전부 재핀 이전 구세대 실행 — 마지막 구세대 배치 07:49:52Z, head 8c46c4ea).

**표본(n=2, 전부 conclusion=success)**:

| run | run_number | 배치 head(=착지 MERGE 커밋) | PR | B(base) | 생성 | 런 wall | 큐 wall | 코호트 |
|---|---|---|---|---|---|---|---|---|
| 41414648142 | 816 | 9381cb3a5 | #1214 docs(evidence) 세대 전환 기록 | 8c46c4ea | 08:39:20Z | 512 s | 530 s(08:39:01Z→08:48:11Z MERGE) | **A: REUSED** |
| 41416443711 | 818 | 4c19fa9b6 | #1215 docs(spec) quirk 문서화 | 9381cb3a | 08:54:19Z | 647 s | 565 s(08:54:00Z→09:05:25Z MERGE) | **B: EXECUTED** |

- **제외 런: 0건** — 창 내 완결 admission-gate merge_group 런은 위 2건이 전부. 실패·취소·SKIP 런 없음. 창 종결 시점 큐 비어 있음(진행 중 미완결 런 없음).
- **라벨 축(별도 정의 준수)**: ciGeneration = N+8(node24 — callee `498c5570`, blob `f0bb8fb5`, 3-way 일치 TWS:41 = manifest:25 재확인) · provider epoch = GHEC 복귀 후 시간 버킷 — 판별자 `runner_group_id=0`(GitHub-hosted) 전 success 잡 관측(`ci_provider_ghec_return_acceptance_2026-11-01.md` §2 판별자 — '공급자 실측 아님': provider epoch는 시간 버킷 라벨). 재실행 없음(전부 `run_attempt=1`, jobs `filter=latest`).
- **코호트 정의(판정 아티팩트 증거)**: 코호트 A — 4개 판정 서브젝트 전부 `basis: "REUSED"`, reason "closure re-derivation + executionEpoch + per-read re-hash all passed", `probeTreeOid f32641d7…` — GO-critical admission tests 스텝 wall 0 s('실행 안 됨(재사용)'). 코호트 B — 4개 서브젝트 전부 `basis: "EXECUTED"`, reason "no record for the current closure (fresh judgment)", `probeTreeOid 44946f71…`(≠ 코호트 A) — GO tests 실실행(134/149 s). 두 배치 모두 docs-only PR이며 서로 다른 클로저 판정을 받은 것이 분기의 전부다(재사용이 거짓 양성 없이 입력 민감적으로 작동하는 실측 사례 쌍).
- **warm-up 층 분리**: run 816은 신세대 첫 merge_group 실행(세대 착지 27분 후)이므로 콜드/워밍 가능성을 라벨로 남긴다. 본표본은 본포 분포 추정이 아니다(진단 분해 — 표본 수 n=2 명시).
- **원시 데이터 보존**: jobs 원문 각 1회 GET — run 816 `sha256 869b5ad2b526ef225844c93f600fa79d130c23a9cd6f93426f3600e598474856`(63,142 bytes), run 818 `sha256 bdb7382324c9707bdd233a4d48e6feb392a3a48959c08c5c5248a9aeb6b921f4`(65,808 bytes). 판정 아티팩트: lane-0/1 judgment zip 각 2런(§7 재현).

## §3 job 레벨 분해 — 임계 기여

**Run 816(코호트 A, 런 wall 512 s) 크리티컬 패스 체인**(잡 시작/종료 관측치, gaps 포함):

```
dispatch 4s → build-base 90s → gap 3s → lane(1) 207s ┐ lane(0) 188s (병렬)
→ gap 4s → attest/admission-check 91s → gap 5s → mint-prepare/prepare 50s
→ gap 3s → mint-publish/publish 48s ┐ verdict/admission-check 41s (병렬)
→ gap 3s → admission-check(최종) 3s → gap 1s = 512s
```

**Run 818(코호트 B, 런 wall 647 s) 크리티컬 패스 체인**:

```
dispatch → build-base 79s → lane(1) 337s ┐ lane(0) 299s (병렬)
→ attest/admission-check 98s → mint-prepare 45s → mint-publish 43s ┐ verdict 38s (병렬)
→ admission-check(최종) 4s = 647s
```

병렬 비게이팅: gateway/select 139 s(816)/110 s(818), gateway/ci-bootstrap 818에서만 실행 95 s(venue 조건부 디스패치 — 816에서 skipped), closure-deriver 71/95 s(선행 단계).

**크리티컬 패스 구성(잡 수준, 코호트 A/B)**:

| 구성 | 816(A) | 818(B) | 비고 |
|---|---|---|---|
| build-base-artifacts(B-built judge 공급) | 90 s (17.6%) | 79 s (12.2%) | PR venue에서도 재실행 관측(§5) |
| 레인 최장잡 | 207 s (40.4%) | 337 s (52.1%) | 내부 분해 §4.1 |
| attest/admission-check | 91 s (17.8%) | 98 s (15.1%) | 내부 분해 §4.2 |
| mint-prepare + mint-publish | 98 s (19.1%) | 88 s (13.6%) | 대상 잡 범위 밖(§5) |
| 최종 admission-check | 3 s | 4 s | |
| dispatch·gaps·러너 배정 | 23 s (4.5%) | ~41 s | 잡 간 gap(§4.4) |

**정합성(계보 규칙: steps_sum + head/tail gap ≈ job wall, ±1 s)**: 대상 4잔 × 2런 steps_sum/wall 커버리지 = 184/188(97.9%)·193/207(93.2%)·89/91(97.8%)·38/41(92.7%)·297/299(99.3%)·333/337(98.8%)·96/98(98.0%)·34/38(89.5%). 미커버리는 잡 시작~첫 스텝 사이 러너 부트/배정 gap(§4.4)이다(예: lane(1) 816 — 잡 started_at 08:40:57 vs 첫 스텝 08:41:09, 12 s).

## §4 스텝별 분해 — 측정 사실 | 원인 판정 2칸 분리

**분류 축(집계 키 — 실행 계획 (c) 등록 매핑 + 문서화 확장)**:

- `verif-exec` = **필수 검증·판정 실행**: GO-critical admission tests, evidenceId contract check(계획 등록: "필수 검증 = GO tests·evidenceId")
- `verif-path` = **필수 검증·판정 경로·식별**(확장): Resolve candidate head, Header, Candidate identity, Judgment CAS plan, Verify artifact manifest, Core purity gate, Re-derive admission identity, Stage D9, Register subject, GO execution accounting, Attest witness, Admission predicate, Verify verdict log, Resolve venue, Load derived-closure
- `env-cache` = **환경·캐시**: setup-axiom-toolchain(composite — actions/cache restore/save `action.yml:332/398/959` 위임, 내부 캐시 복원 비중 분리는 로그 차단으로 UNKNOWN)
- `env-workspace` = **환경·작업공간**(계획 등록: "setup·Checkout B/M·Overlay·slice-engine"): Checkout B/M, Overlay, Load epoch manifest
- `env-provision` = **환경·프로비전**(확장): Provision pinned jq, Install libpcre3
- `env-platform` = **환경·플랫폼 라이프사이클**(확장): Set up job, Complete job, Post(checkout cleanup)
- `transport` = **데이터 수송**(계획 등록: "Download·Upload 2종" + 확장): Checkout H(data-only path), Download*, Upload*, Fetch subject-certificate
- `경합`·`불필요한 반복`·`UNKNOWN`: 본 관측에서의 판정은 이하 각 절에 증거와 함께 명시(경합 입증 0건 — §4.5).

### §4.1 레인 잡 — 코호트 A(REUSED) vs B(EXECUTED) 분기가 비용을 설명한다

**[측정 사실]** 주요 스텝 wall(s):

| 스텝(계획 등록 라인 — node24 세대에서 드리프트 0 검증) | 816 lane(0) | 816 lane(1) | 818 lane(0) | 818 lane(1) | 분류 |
|---|---|---|---|---|---|
| [lane] evidenceId contract check(:3388) | **112** | **91** | 67 | **109** | verif-exec |
| [lane] GO-critical admission tests(:3426) | **0** | **0** | **134** | **149** | verif-exec |
| setup-axiom-toolchain(:3039 uses) | 49 | 74 | 72 | 48 | env-cache |
| [lane] Judgment CAS plan | 3 | 9 | 2 | 4 | verif-path |
| [lane] Upload nimcache(:3656) | 6 | 5 | 5 | 6 | transport |
| [lane] Checkout B(:2913)/M(:2967) | 4/3 | 4/3 | 4/4 | 3/3 | env-workspace |
| [lane] Download base-built(:3045) | 3 | 2 | 3 | 4 | transport |
| 잡 wall | **188** | **207** | **299** | **337** | — |

**[원인 판정]** GO tests 0 s(816) = **'실행 안 됨(재사용)'** — 판정 아티팩트 `basis: "REUSED"`·exec-record `observedAtUtc`가 GO tests 스텝 completed_at과 일치(08:43:55Z/08:44:15Z). 이것은 실행 계획이 남긴 관측 한계 "GO-critical admission tests 0 s — 실행이 evidenceId 스텝에 귀속되는지 UNKNOWN"을 **해소**한다: 0 s는 evidenceId 스텝으로의 귀속이 아니라 재사용에 의한 미실행이다. GO tests 134/149 s(818) = 신실행(`basis: "EXECUTED"` — "no record for the current closure"). evidenceId 67~112 s = 설계상 EXECUTED always(B-owned checker 자기검증 배터리) — wall 분산의 내부 귀속(빌드 내용·러너 편차 기여)은 로그 접근 차단으로 **UNKNOWN**. setup 48~74 s = composite(캐시 복원 포함) — 내부 A-restore/apt 분리 **UNKNOWN**.

**[분류 집계 — 전 스텝, skipped 0건]**:

| 잡 | wall | steps_sum | verif-exec | verif-path | env-cache | env-workspace | env-platform | transport |
|---|---|---|---|---|---|---|---|---|
| 816 lane(0) | 188 | 184 | 112 | 4 | 49 | 7 | 2 | 10 |
| 816 lane(1) | 207 | 193 | 91 | 11 | 74 | 7 | 2 | 8 |
| 818 lane(0) | 299 | 297 | 201(=67+134) | 4 | 72 | 8 | 3 | 9 |
| 818 lane(1) | 337 | 333 | 258(=109+149) | 5 | 48 | 8 | 2 | 12 |

### §4.2 attest / admission-check — 세대·코호트 간 구조 안정

**[측정 사실]** 주요 스텝 wall: setup-axiom-toolchain 43 s(816)/50 s(818) · Re-derive admission identity(:1094) 18 s/16 s · Attest witness-only 8 s/7 s · Core purity gate 4 s/5 s · Checkout B 4/4 s · Checkout H 3/3 s · 나머지 ≤2 s. skipped 13스텝 = '실행 안 됨'(preflight 전용 스텝 6종 + predicate/verdict류 7종 — 후자는 verdict 잡에서 실행, 스테이지 분리 구조). Provision jq·Install libpcre3 = skipped(이 잡에서 '실행 안 됨').

**[분류 집계]**:

| 잡 | wall | steps_sum | verif-path | env-cache | env-workspace | env-provision | env-platform | transport |
|---|---|---|---|---|---|---|---|---|
| 816 | 91 | 89 | 31 | 43 | 4 | 0 | 2 | 9 |
| 818 | 98 | 96 | 31 | 50 | 4 | 0 | 2 | 9 |

**[원인 판정]** identity 재유도(18/16 s)·witness(8/7 s)·purity(4/5 s) = 필수 검증(fail-closed 재유도 — venue 자기완결 설계: MG venue는 캐시 HIT만으로 통과하지 않고 identity·witness를 재계산한다). 코호트 간 차이(91→98 s)는 setup 43→50 s(+7 s)가 전부다 — 필수 검증 스텝은 31 s로 동일.

### §4.3 verdict / admission-check — 스테이지 분리가 중복 실행을 제거한다

**[측정 사실]** 실행 스텝: Admission predicate evaluation(:2257) 20 s(816)/18 s(818) · Install libpcre3 7/4 s · Provision jq 1/1 s · Fetch subject-certificate 1/2 s · Upload verdict log 2/1 s · Checkout B 3/4 s · Download B artifacts 1/2 s · derived-closure 0/1 s. skipped 19스텝 = '실행 안 됨' — **setup-axiom-toolchain도 이 잡에서는 skipped**(attest 스테이지 결과 소비 구조) · identity·witness·purity 등 attest 스테이지 실행분.

**[분류 집계]**:

| 잡 | wall | steps_sum | verif-path | env-provision | env-workspace | env-cache | env-platform | transport |
|---|---|---|---|---|---|---|---|---|
| 816 | 41 | 38 | 21 | 8 | 3 | 0 | 2 | 4 |
| 818 | 38 | 34 | 19 | 5 | 4 | 0 | 1 | 5 |

**[원인 판정]** predicate 20/18 s = 필수 검증(MergeAdmissible 판정 — 스텝 :2257, `[check]` 소속). 이 잡의 19개 skipped 스텝은 낭비가 아니라 attest/verdict 스테이지 분리 설계의 실행 배타다(같은 잡의 다른 stage 정의 — admission-check.yml 잡 :669 스테이지 디스패치).

### §4.4 잡 wall 대비 미커버리 — 러너 부트/배정 gap

잡 started_at ~ 첫 스텝 started_at 사이 gap: lane(1) 816 12 s · lane(1) 818 ~3 s · verdict 818 ~4 s 등(합계 잡당 0~14 s). [원인 판정] 러너 부트/배정 지연(등록 대안 설명 ③ — 플랫폼 동작)이지 검증·경합 아니다. 잡 수준 `runner_id`는 실행 잡마다 상이(예: 816 레인 1000038689/1000038690 — 별개 ephemeral runner, 설계상 고립).

### §4.5 경합·불필요한 반복 — 판정

- **경합: 입증 0건(UNKNOWN 유지 준수)**. 요건 (i) 동시 실행 구조 + (ii) 자원 공유 신호(동일 runner_id·캐시 키·lock 오류) 또는 (iii) 복원 시간 인과 곡선 — 어느 것도 관측되지 않았다. 레인 간 wall 차(188 vs 207 / 299 vs 337)는 등록된 대안 설명으로 먼저 귀속된다: ① workload 비대칭은 본 배치에서 아님(동일 서브젝트 분할) ② **교차 러너 분산 — 실측 근거: setup wall이 런 간 뒤집힌다(816: lane0 49 < lane1 74 → 818: lane0 72 > lane1 48 — 특정 레인에 고정된 편차가 아님)** ③ 러너 배정 지연(§4.4) ④ 캐시 서비스 지연(UNKNOWN 내부). 두 레인은 별개 ephemeral runner에서 동시 실행(전제: CACHE ISOLATION, admission-check.yml 주석 구조).
- **불필요한 반복: 대상 잡 내 0 s 측정.** GO tests는 클로저 일치 시 재사용(0 s), 미일치 시 신실행(필수). 잡 내 반복 스텝 없음. attest/verdict 스테이지 분리가 판정 경로 중복을 제거(§4.3). 유일한 측정된 교차 실행 반복은 build-base-artifacts의 venue 간 재실행(§5 — 대상 잡 외).

## §5 후보 레버 평가 — 문턱 대비

**문턱**: 효과 크기 > 노이즈(2×SE — arestore BLOCKED §3(d)의 기각 근거가 provider 스윙 ~23 s 노이즈 대비 미달이었던 선례). n=2·코호트별 n=1이므로 사후 Before/After 효과 입증 불가 상태에서 후보는 "계약 무손상 + 최소 diff + 부정 시험 가능"을 사전에 충족해야 한다(실행 계획 (e) ①~⑤).

| 레버 | 기제(실측) | 검증 범위·판정 계약 접촉 | 문턱 판정 |
|---|---|---|---|
| GO tests 재실행 제거 | 코호트 A에서 이미 0 s(재사용 작동). 코호트 B의 134/149 s는 신규 클로저 신실행 = 필수 | 판정 실행 — judgment CAS 이미 구현·입력 민감 작동 실증 | **제거 대상 없음** |
| evidenceId contract check 단축 | 레인 최대 단일 스텝 67~112 s | 검증 의미론("EXECUTED always" — 실행 계획 Out of Scope 명시) | **탈락(의미론 보호)** |
| setup-axiom-toolchain 단축 | 43~74 s/잡, composite 내부 UNKNOWN(로그 접근 차단) | A-restore 최적화 BLOCKED 종결(#1192)과 동일 영역·동일 계약 | **탈락(선례 BLOCKED)** |
| 수송 스텝 전체 | 잡당 4~12 s(합 <13 s) | 플랫폼 액션 — 무손상 가능하나 효과 < 노이즈(~23 s) | **탈락(효과 크기 미달)** |
| 교차-venue B-build 중복 제거 | **실측: 동일 B=8c46c4ea가 PR venue 65 s(런 41413475503, run_number 815) + MG venue 90 s(런 816) 이중 빌드** — MG 크리티컬 패스 17.6% | B-built judge 공급의 캐시 재사용 = "cache ≠ evidence" 분리 + 재사용 사운드니스(J1-J4 등가 증명 의무) + 신규 CAS 도메인 — 실행 계획 Out of Scope("검증 범위·판정·증거 순서·재사용 사운드니스(J1-J4) 변경"·"새 캐시 엔진") | **탈락(범위 밖 — 후속 계약 작업 필요, 본 문서가 실측 근거 착지)** |
| mint tail(mint-prepare 50/45 s + mint-publish 48/43 s) | 크리티컬 패스 88~98 s(13.6~19.1%) | 대상 잡 범위 밖(계획 (a): lanes·admission-check 고정) — ADR-0022 §D5-3 인증서 파이프라인, 내부 비용 미분해 | **탈락(범위 밖 — 후속 조사 입력)** |
| 경합 완화 | 경합 미입증(§4.5 — 증거 기준 미충족) | — | **대상 없음** |

**480 s 달성 가능성 판정 입력(정량)**: 코호트 A(재사용 최대) 런 wall 512 s·큐 wall 530 s — 잔여 구성 중 의미론 보호 대상(레인 verif-exec 102 s + attest/verdict verif-path 52 s + B-build 90 s)을 제외하면 가변 영역은 환경(~83 s)·mint(98 s)·수송(~30 s)·gaps(~23 s)이고, 이 중 범위 내·노이즈 상회 후보는 존재하지 않는다. 공식 SLO P95 480 s 판정은 #1166 공식 모집단(자연 누적)의 권한이며 본 진단 표본으로 판정하지 않는다.

## §6 결론

1. **절감 후보 판정: BLOCKED(범위 내 안전 후보 0개)** — 실행 계획의 종결 조건("후보가 없으면 BLOCKED — 근거가 없으면 변경하지 않고 조사 결과를 문서로 착지")을 따른다. 이것은 실패가 아니라 결정 가능한 운영 결과다: 대상 잡 내 측정된 비용은 필수 검증(재사용 작동 포함)·A-restore BLOCKED 영역 환경·노이즈 미달 수송으로 구성되며, 제거 가능한 낭비는 0 s였다.
2. **긍정 실측**: 판정 CAS 재사용이 입력 민감적으로 작동한다(코호트 A 4 서브젝트 REUSED, GO tests 0 s — 아티팩트 basis 증거; 코호트 B 클로저 변화 감지 신실행). "동일한 입력 ⇒ 동일한 판정" 재사용이 이미 구현·운영 중이며, 본 관측이 그 무손상 작동의 사례 쌍을 정본에 남긴다. 선행 관측 한계(GO tests 0 s 귀속 UNKNOWN)는 해소됐다(§4.1).
3. **후속 입력(본 슬라이스 범위 밖 — 별도 계약 작업·사전등록 필요)**: ① 교차-venue B-build 중복(동일 B 65+90 s 이중 빌드 실측 — J1-J4 등가 사운드니스 증명 + CAS 도메인 확장 계약 전제) ② mint tail 88~98 s(인증서 파이프라인 내부 미분해 — 별도 분해 조사) ③ 신세대 표본 자연 누적 후 동일 재현 명령으로 코호트 분포 재산출.
4. **규칙 준수**: GET-only(관측·판독 — 코드·워크플로·게이트·판정 의미론 변경 0) · Authority ≠ Adapter(병합 권위는 GitHub) · 전수 나열·제외 0건·침묵 탈락 없음 · 사전 고정 창·분류 축·경합 증거 기준 준수 · 재현 명령 §7 수록.

## §7 검증 가능성(GET-only 재현)

```bash
# 0) 전제: 세대 착지 경계 readback(하한 고정 근거)
gh api orgs/Archright/rulesets/25218071 --jq '{updated_at, sha: .rules[0].parameters.workflows[0].sha}'
gh api orgs/Archright/rulesets/23943917 --jq '{updated_at, sha: .rules[0].parameters.workflows[0].sha}'
# → 양측 sha 7eaa9624…, updated_at 08:11:42.586Z / 08:12:08.926Z(하한 = 늦은 쪽)

# 1) 관측창 열거(Q16: 단일 질의 total_count<1000 확인 + run-id dedupe)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-11-02T08:12:09Z..2026-11-02T09:13:00Z&per_page=50" \
  --jq '[.total_count, [.workflow_runs[] | select(.path|endswith("admission-gate-v2.yml")) | [.id, .run_number, .created_at, .conclusion, .run_attempt]]]'

# 2) 대상 런 단일 GET 교차검증(목록 아닌 단일 GET이 권위)
gh api repos/Archright/Axiom/actions/runs/41414648142 --jq '{id, run_number, head_sha, event, status, conclusion, run_started_at, updated_at, run_attempt}'
gh api repos/Archright/Axiom/actions/runs/41416443711 --jq '{id, run_number, head_sha, event, status, conclusion, run_started_at, updated_at, run_attempt}'
# sha256 보존: run 816 jobs 869b5ad2b526ef225844c93f600fa79d130c23a9cd6f93426f3600e598474856 / run 818 bdb7382324c9707bdd233a4d48e6feb392a3a48959c08c5c5248a9aeb6b921f4

# 3) jobs steps[] 원문(filter=latest 명시 — 재실행 이전 시도 조용히 제외 방지)
gh api "repos/Archright/Axiom/actions/runs/41414648142/jobs?per_page=100&filter=latest" > run_816_jobs.json
gh api "repos/Archright/Axiom/actions/runs/41416443711/jobs?per_page=100&filter=latest" > run_818_jobs.json

# 4) step wall·분류 집계(epoch 차감 — census_20261101 계보; 분류 함수는 §4 축과 동일 verbatim)
jq 'def cls: if (.name|test("Set up job|Complete job|^Post ")) then "env-platform"
  elif (.name|test("setup-axiom-toolchain")) then "env-cache"
  elif (.name|test("Provision pinned jq|Install libpcre3")) then "env-provision"
  elif (.name|test("Checkout executor tree = B|Checkout candidate = M \\(|Overlay M src|Load epoch manifest")) then "env-workspace"
  elif (.name|test("Checkout candidate = H")) then "transport"
  elif (.name|test("Download|Upload|Fetch subject-certificate")) then "transport"
  elif (.name|test("GO-critical admission tests|evidenceId contract check")) then "verif-exec"
  else "verif-path" end;
  .jobs[] | select(.name|test("go-critical-lane \\(|/ admission-check")) | select(.conclusion=="success")
  | {job: .name, wall: ((.completed_at|fromdateiso8601)-(.started_at|fromdateiso8601)),
     by_class: ([.steps[] | select(.started_at and .completed_at) | {c: cls, w: ((.completed_at|fromdateiso8601)-(.started_at|fromdateiso8601))}] | group_by(.c) | map({(.[0].c): (map(.w)|add)}) | add),
     steps_sum: ([.steps[] | select(.started_at and .completed_at) | ((.completed_at|fromdateiso8601)-(.started_at|fromdateiso8601))]|add),
     n_skipped: ([.steps[] | select(.conclusion=="skipped")]|length)}' run_816_jobs.json
# → §4 집계표와 동일 값(818도 동일 명령)

# 5) 판정 basis 증거(REUSED/EXECUTED — 아티팩트 다운로드 후 판독)
gh api repos/Archright/Axiom/actions/artifacts/13127192677/zip > lane0-816.zip && unzip -o -q lane0-816.zip -d lane0-816
jq -r '{basis, reason, landingVenue, probeTreeOid}' lane0-816/judgment-decision.json        # REUSED + f32641d7…
jq -r '{subject, verdict, basis, observedAtUtc}' lane0-816/go-exec-records/s1a.json          # REUSED, observed 08:43:55Z
gh api repos/Archright/Axiom/actions/artifacts/13128540616/zip > lane0-818.zip && unzip -o -q lane0-818.zip -d lane0-818
jq -r '{basis, reason, landingVenue, probeTreeOid}' lane0-818/judgment-decision.json        # EXECUTED + 44946f71…
# 816 lane-1 아티팩트 13126354638 / 818 lane-1 아티팩트 13128745637 — 동일 판독

# 6) 교차-venue B-build 관측(§5 근거 — PR venue 런의 잡 구성)
gh api "repos/Archright/Axiom/actions/runs/41413475503/jobs?per_page=100" \
  --jq '[.jobs[] | select(.name=="attest / build-base-artifacts") | {name, conclusion, wall: ((.completed_at|fromdateiso8601)-(.started_at|fromdateiso8601))}]'  # 65 s, B=8c46c4ea

# 7) 잡·스텝 정의 라인·핀 검증(신세대 callee — 라인 드리프트 0, 별도 매핑 검증 완료)
git rev-parse 498c5570:.github/workflows/admission-check.yml   # f0bb8fb5b839770bf8e53639f3c2cb99997447d4
```

관측 한계(문서화 의무): ① 1 s 그래니러러티(±1 s) ② composite(setup-axiom-toolchain) 내부 캐시/빌드 분리 — 스텝 로그 접근 차단으로 UNKNOWN(선례 3종의 `duration_ms` 파싱 경로도 동일 차단) ③ 스텝 이름↔내용 귀속 어긋남 가능(본 표본에서 GO tests 0 s는 아티팩트로 재사용 확정 — 잔여: evidenceId 배터리 내부 구성 UNKNOWN) ④ skipped 잡의 잡 수준 타임스탬프 역전(예: mint-prepare/publish completed < started — '실행 안 됨' 처리, 해석 금지) ⑤ 클로저 구성원 판정(probeTreeOid 차이의 파일 단위 귀속)은 판정 레코드에 OID로만 존재 — 본 관측 채널로는 UNKNOWN.

## 부록 A — 잡 단위 원값(전수, skipped 잡 포함 — 침묵 탈락 없음)

**Run 816(41414648142, 코호트 A)** — wall(s)·steps 수·skipped 스텝 수:

| 잡 | 결론 | wall | steps | skipped 스텝 |
|---|---|---|---|---|
| closure-deriver | success | 71 | 10 | 0 |
| attest / build-base-artifacts | success | 90 | 18 | 0 |
| gateway / sl09-scope | success | 11 | 5 | 0 |
| gateway / select | success | 139 | 15 | 0 |
| attest / go-critical-lane (0) | success | 188 | 19 | 0 |
| attest / go-critical-lane (1) | success | 207 | 19 | 0 |
| gateway / executed-jobs | success | 4 | 3 | 0 |
| attest / admission-check | success | 91 | 35 | 13 |
| attest / go-critical-rollup | success | 3 | 3 | 0 |
| mint-prepare / prepare | success | 50 | 17 | 0 |
| mint-publish / publish | success | 48 | 19 | 0 |
| verdict / admission-check | success | 41 | 34 | 19 |
| admission-check(최종) | success | 3 | 3 | 0 |
| anchor-resolve | skipped | '실행 안 됨' | — | — |
| gateway / candidate-build-arm·gateway-shard·ci-bootstrap·proof-reconcile·gateway-identity-gate | skipped | '실행 안 됨' | — | — |
| mint-prepare / publish·mint-publish / prepare | skipped | '실행 안 됨'(타임스탬프 역전 quirk) | — | — |
| verdict / build-base-artifacts·go-critical-lane·go-critical-rollup | skipped | '실행 안 됨' | — | — |

**Run 818(41416443711, 코호트 B)**:

| 잡 | 결론 | wall | steps | skipped 스텝 |
|---|---|---|---|---|
| closure-deriver | success | 95 | 10 | 0 |
| attest / build-base-artifacts | success | 79 | 18 | 3 |
| attest / go-critical-lane (0) | success | 299 | 19 | 0 |
| attest / go-critical-lane (1) | success | 337 | 19 | 0 |
| gateway / select | success | 110 | 15 | 0 |
| gateway / sl09-scope | success | 16 | 5 | 0 |
| gateway / ci-bootstrap | success | 95 | 14 | 2 |
| gateway / executed-jobs | success | 3 | 3 | 0 |
| attest / admission-check | success | 98 | 35 | 13 |
| attest / go-critical-rollup | success | 2 | 3 | 0 |
| mint-prepare / prepare | success | 45 | 17 | 1 |
| mint-publish / publish | success | 43 | 19 | 1 |
| verdict / admission-check | success | 38 | 34 | 19 |
| admission-check(최종) | success | 4 | 3 | 0 |
| skipped 잡 10종 | skipped | '실행 안 됨' | — | — |

(anchor-resolve, gateway/candidate-build-arm·gateway-shard·gateway-identity-gate·proof-reconcile, mint-prepare/publish·mint-publish/prepare, verdict/build-base-artifacts·go-critical-lane·go-critical-rollup)

## 부록 B — 스텝 단위 전수 장부(대상 4잔 × 2런, wall s · 결론 · 분류 — 원문 타임스탬프는 §7-3/§7-4로 재현)

### Run 816(41414648142)

#### attest / go-critical-lane (0) (wall 188s)

| # | step | wall | 결론 | 분류 |
|---|---|---|---|---|
| 1 | Set up job | 1 | success | env-platform |
| 2 | [lane] Checkout executor tree = B (base.sha, workspace root) | 4 | success | env-workspace |
| 3 | [lane] Resolve candidate head (M — fail-closed venue identity) | 0 | success | verif-path |
| 4 | [lane] Checkout candidate = M (overlay-only source, no credential persistence) | 3 | success | env-workspace |
| 5 | [lane] Header — lane/runner identity (isolation observation, evidence not authority) | 0 | success | verif-path |
| 6 | [slice-engine] Load epoch manifest implementedSlices (B tree — scope authority) | 0 | success | env-workspace |
| 7 | Run ./.github/actions/setup-axiom-toolchain | 49 | success | env-cache |
| 8 | [lane] Download base-built artifacts (B bin/ax + ircheck) | 3 | success | transport |
| 9 | [lane] Verify artifact manifest (fail-closed — build_sha == B) | 0 | success | verif-path |
| 10 | [lane] Candidate identity (M sha/tree, B tree, M objects, overlay digest) | 1 | success | verif-path |
| 11 | [lane] Judgment CAS plan (subjects: s1a — SL-15 scope) | 3 | success | verif-path |
| 12 | [lane] Overlay M src/+GO-critical tests onto the B workspace (manifest digest, identity log) | 0 | success | env-workspace |
| 13 | [lane] evidenceId contract check (B-owned checker — self-check battery, EXECUTED always) | 112 | success | verif-exec |
| 14 | [lane] GO-critical admission tests (DEBT#432 — lane 0, fail-closed) | 0 | success | verif-exec — '실행 안 됨(재사용: basis REUSED)' |
| 15 | [lane] Upload judgment files (post-mortem reachability — always) | 1 | success | transport |
| 16 | [lane] Upload nimcache (test supply — J3 fold input) | 6 | success | transport |
| 31 | Post [lane] Checkout candidate = M | 0 | success | env-platform |
| 32 | Post [lane] Checkout executor tree = B | 1 | success | env-platform |
| 33 | Complete job | 0 | success | env-platform |

#### attest / go-critical-lane (1) (wall 207s)

| # | step | wall | 결론 | 분류 |
|---|---|---|---|---|
| 1 | Set up job | 1 | success | env-platform |
| 2 | [lane] Checkout executor tree = B | 4 | success | env-workspace |
| 3 | [lane] Resolve candidate head (M — fail-closed venue identity) | 0 | success | verif-path |
| 4 | [lane] Checkout candidate = M | 3 | success | env-workspace |
| 5 | [lane] Header — lane/runner identity | 0 | success | verif-path |
| 6 | [slice-engine] Load epoch manifest implementedSlices | 0 | success | env-workspace |
| 7 | Run ./.github/actions/setup-axiom-toolchain | 74 | success | env-cache |
| 8 | [lane] Download base-built artifacts | 2 | success | transport |
| 9 | [lane] Verify artifact manifest | 1 | success | verif-path |
| 10 | [lane] Candidate identity | 1 | success | verif-path |
| 11 | [lane] Judgment CAS plan (subjects: proof_integrity d2_golden d2_persist — SL-15 scope) | 9 | success | verif-path |
| 12 | [lane] Overlay M src/+GO-critical tests onto the B workspace | 0 | success | env-workspace |
| 13 | [lane] evidenceId contract check | 91 | success | verif-exec |
| 14 | [lane] GO-critical admission tests (DEBT#432 — lane 1) | 0 | success | verif-exec — '실행 안 됨(재사용: basis REUSED)' |
| 15 | [lane] Upload judgment files | 1 | success | transport |
| 16 | [lane] Upload nimcache | 5 | success | transport |
| 31 | Post [lane] Checkout candidate = M | 1 | success | env-platform |
| 32 | Post [lane] Checkout executor tree = B | 0 | success | env-platform |
| 33 | Complete job | 0 | success | env-platform |

#### attest / admission-check (wall 91s)

| # | step | wall | 결론 | 분류 |
|---|---|---|---|---|
| 1 | Set up job | 1 | success | env-platform |
| 2 | [venue] Resolve execution venue (PR=preflight / MG+call=landing) | 0 | success | verif-path |
| 3 | [check] Checkout executor tree = B | 4 | success | env-workspace |
| 4 | [check] Provision pinned jq | 0 | skipped | env-provision — '실행 안 됨' |
| 5 | [check] Install libpcre3 | 0 | skipped | env-provision — '실행 안 됨' |
| 6 | [slice-engine] Load epoch manifest implementedSlices | 0 | success | env-workspace |
| 7 | Run ./.github/actions/setup-axiom-toolchain | 43 | success | env-cache |
| 8 | [check] Checkout candidate = H (PR head / merge-group head, data-only path) | 3 | success | transport |
| 9 | [check] Download base-built artifacts | 2 | success | transport |
| 10 | [check] Verify artifact manifest | 0 | success | verif-path |
| 11 | [check] Core purity gate (B-built judge on _candidate tree) | 4 | success | verif-path |
| 12 | [check] Download lane-0 judgment artifacts | 1 | success | transport |
| 13 | [check] Download lane-1 judgment artifacts | 0 | success | transport |
| 14 | [check] Re-derive admission identity (B/H/treeOID — fail-closed) | 18 | success | verif-path |
| 15 | [preflight] Attest-leg static contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 16 | [check] Stage D9 evidence | 0 | success | verif-path |
| 17 | [check] Register subject | 0 | success | verif-path |
| 18 | [check] GO execution accounting cross-check | 1 | success | verif-path |
| 19 | [check] Attest witness-only (B-built ax kernel, H-derived data) | 8 | success | verif-path |
| 20 | [check] Upload evidence record | 1 | success | transport |
| 21 | [check] Upload judgment record | 1 | success | transport |
| 22 | [check] Load derived-closure sets | 0 | skipped | verif-path — '실행 안 됨' |
| 23 | [check] Fetch subject-certificate artifact | 0 | skipped | transport — '실행 안 됨' |
| 24 | [preflight] Verdict-leg static contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 25 | [check] Download derived-closure | 0 | skipped | transport — '실행 안 됨' |
| 26 | [preflight] Rotation-pin H2 contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 27 | [preflight] Upload rotation-preflight evidence | 0 | skipped | transport — '실행 안 됨' |
| 28 | [check] Admission predicate evaluation | 0 | skipped | verif-path — '실행 안 됨'(verdict 잡에서 실행) |
| 29 | [check] FAIL-CLOSED guard | 0 | skipped | verif-path — '실행 안 됨' |
| 30 | [check] Verify verdict log content | 0 | skipped | verif-path — '실행 안 됨' |
| 31 | [check] Upload verdict log | 0 | skipped | transport — '실행 안 됨' |
| 32 | [check] Upload admission records | 1 | success | transport |
| 63 | Post [check] Checkout candidate = H | 1 | success | env-platform |
| 64 | Post [check] Checkout executor tree = B | 0 | success | env-platform |
| 65 | Complete job | 0 | success | env-platform |

#### verdict / admission-check (wall 41s)

| # | step | wall | 결론 | 분류 |
|---|---|---|---|---|
| 1 | Set up job | 2 | success | env-platform |
| 2 | [venue] Resolve execution venue | 0 | success | verif-path |
| 3 | [check] Checkout executor tree = B | 3 | success | env-workspace |
| 4 | [check] Provision pinned jq | 1 | success | env-provision |
| 5 | [check] Install libpcre3 | 7 | success | env-provision |
| 6 | [slice-engine] Load epoch manifest implementedSlices | 0 | success | env-workspace |
| 7 | Run ./.github/actions/setup-axiom-toolchain | 0 | skipped | env-cache — '실행 안 됨' |
| 8 | [check] Checkout candidate = H | 0 | skipped | transport — '실행 안 됨' |
| 9 | [check] Download base-built artifacts | 1 | success | transport |
| 10 | [check] Verify artifact manifest | 1 | success | verif-path |
| 11 | [check] Core purity gate | 0 | skipped | verif-path — '실행 안 됨' |
| 12 | [check] Download lane-0 judgment artifacts | 0 | skipped | transport — '실행 안 됨' |
| 13 | [check] Download lane-1 judgment artifacts | 0 | skipped | transport — '실행 안 됨' |
| 14 | [check] Re-derive admission identity | 0 | skipped | verif-path — '실행 안 됨'(attest 잡에서 실행) |
| 15 | [preflight] Attest-leg static contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 16 | [check] Stage D9 evidence | 0 | skipped | verif-path — '실행 안 됨' |
| 17 | [check] Register subject | 0 | skipped | verif-path — '실행 안 됨' |
| 18 | [check] GO execution accounting cross-check | 0 | skipped | verif-path — '실행 안 됨' |
| 19 | [check] Attest witness-only | 0 | skipped | verif-path — '실행 안 됨' |
| 20 | [check] Upload evidence record | 0 | skipped | transport — '실행 안 됨' |
| 21 | [check] Upload judgment record | 0 | skipped | transport — '실행 안 됨' |
| 22 | [check] Load derived-closure sets | 0 | success | verif-path |
| 23 | [check] Fetch subject-certificate artifact | 1 | success | transport |
| 24 | [preflight] Verdict-leg static contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 25 | [check] Download derived-closure | 0 | skipped | transport — '실행 안 됨' |
| 26 | [preflight] Rotation-pin H2 contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 27 | [preflight] Upload rotation-preflight evidence | 0 | skipped | transport — '실행 안 됨' |
| 28 | [check] Admission predicate evaluation (MergeAdmissible verdict → check conclusion) | 20 | success | verif-path |
| 29 | [check] FAIL-CLOSED guard | 0 | skipped | verif-path — '실행 안 됨' |
| 30 | [check] Verify verdict log content | 0 | success | verif-path |
| 31 | [check] Upload verdict log | 2 | success | transport |
| 32 | [check] Upload admission records | 0 | skipped | transport — '실행 안 됨' |
| 64 | Post [check] Checkout executor tree = B | 0 | success | env-platform |
| 65 | Complete job | 0 | success | env-platform |

### Run 818(41416443711)

#### attest / go-critical-lane (0) (wall 299s)

| # | step | wall | 결론 | 분류 |
|---|---|---|---|---|
| 1 | Set up job | 2 | success | env-platform |
| 2 | [lane] Checkout executor tree = B | 4 | success | env-workspace |
| 3 | [lane] Resolve candidate head (M — fail-closed venue identity) | 0 | success | verif-path |
| 4 | [lane] Checkout candidate = M | 4 | success | env-workspace |
| 5 | [lane] Header — lane/runner identity | 0 | success | verif-path |
| 6 | [slice-engine] Load epoch manifest implementedSlices | 0 | success | env-workspace |
| 7 | Run ./.github/actions/setup-axiom-toolchain | 72 | success | env-cache |
| 8 | [lane] Download base-built artifacts | 3 | success | transport |
| 9 | [lane] Verify artifact manifest | 1 | success | verif-path |
| 10 | [lane] Candidate identity | 1 | success | verif-path |
| 11 | [lane] Judgment CAS plan (subjects: s1a — SL-15 scope) | 2 | success | verif-path |
| 12 | [lane] Overlay M src/+GO-critical tests onto the B workspace | 0 | success | env-workspace |
| 13 | [lane] evidenceId contract check | 67 | success | verif-exec |
| 14 | [lane] GO-critical admission tests (DEBT#432 — lane 0, fail-closed) | 134 | success | verif-exec — 신실행(basis EXECUTED, 신규 클로저) |
| 15 | [lane] Upload judgment files | 1 | success | transport |
| 16 | [lane] Upload nimcache | 5 | success | transport |
| 31 | Post [lane] Checkout candidate = M | 0 | success | env-platform |
| 32 | Post [lane] Checkout executor tree = B | 0 | success | env-platform |
| 33 | Complete job | 1 | success | env-platform |

#### attest / go-critical-lane (1) (wall 337s)

| # | step | wall | 결론 | 분류 |
|---|---|---|---|---|
| 1 | Set up job | 1 | success | env-platform |
| 2 | [lane] Checkout executor tree = B | 3 | success | env-workspace |
| 3 | [lane] Resolve candidate head (M — fail-closed venue identity) | 0 | success | verif-path |
| 4 | [lane] Checkout candidate = M | 3 | success | env-workspace |
| 5 | [lane] Header — lane/runner identity | 0 | success | verif-path |
| 6 | [slice-engine] Load epoch manifest implementedSlices | 1 | success | env-workspace |
| 7 | Run ./.github/actions/setup-axiom-toolchain | 48 | success | env-cache |
| 8 | [lane] Download base-built artifacts | 4 | success | transport |
| 9 | [lane] Verify artifact manifest | 0 | success | verif-path |
| 10 | [lane] Candidate identity | 1 | success | verif-path |
| 11 | [lane] Judgment CAS plan (subjects: proof_integrity d2_golden d2_persist — SL-15 scope) | 4 | success | verif-path |
| 12 | [lane] Overlay M src/+GO-critical tests onto the B workspace | 1 | success | env-workspace |
| 13 | [lane] evidenceId contract check | 109 | success | verif-exec |
| 14 | [lane] GO-critical admission tests (DEBT#432 — lane 1, fail-closed) | 149 | success | verif-exec — 신실행(basis EXECUTED, 신규 클로저) |
| 15 | [lane] Upload judgment files | 2 | success | transport |
| 16 | [lane] Upload nimcache | 6 | success | transport |
| 31 | Post [lane] Checkout candidate = M | 1 | success | env-platform |
| 32 | Post [lane] Checkout executor tree = B | 0 | success | env-platform |
| 33 | Complete job | 0 | success | env-platform |

#### attest / admission-check (wall 98s)

| # | step | wall | 결론 | 분류 |
|---|---|---|---|---|
| 1 | Set up job | 1 | success | env-platform |
| 2 | [venue] Resolve execution venue | 0 | success | verif-path |
| 3 | [check] Checkout executor tree = B | 4 | success | env-workspace |
| 4 | [check] Provision pinned jq | 0 | skipped | env-provision — '실행 안 됨' |
| 5 | [check] Install libpcre3 | 0 | skipped | env-provision — '실행 안 됨' |
| 6 | [slice-engine] Load epoch manifest implementedSlices | 0 | success | env-workspace |
| 7 | Run ./.github/actions/setup-axiom-toolchain | 50 | success | env-cache |
| 8 | [check] Checkout candidate = H | 3 | success | transport |
| 9 | [check] Download base-built artifacts | 2 | success | transport |
| 10 | [check] Verify artifact manifest | 1 | success | verif-path |
| 11 | [check] Core purity gate | 5 | success | verif-path |
| 12 | [check] Download lane-0 judgment artifacts | 0 | success | transport |
| 13 | [check] Download lane-1 judgment artifacts | 1 | success | transport |
| 14 | [check] Re-derive admission identity | 16 | success | verif-path |
| 15 | [preflight] Attest-leg static contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 16 | [check] Stage D9 evidence | 0 | success | verif-path |
| 17 | [check] Register subject | 1 | success | verif-path |
| 18 | [check] GO execution accounting cross-check | 1 | success | verif-path |
| 19 | [check] Attest witness-only | 7 | success | verif-path |
| 20 | [check] Upload evidence record | 1 | success | transport |
| 21 | [check] Upload judgment record | 1 | success | transport |
| 22 | [check] Load derived-closure sets | 0 | skipped | verif-path — '실행 안 됨' |
| 23 | [check] Fetch subject-certificate artifact | 0 | skipped | transport — '실행 안 됨' |
| 24 | [preflight] Verdict-leg static contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 25 | [check] Download derived-closure | 0 | skipped | transport — '실행 안 됨' |
| 26 | [preflight] Rotation-pin H2 contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 27 | [preflight] Upload rotation-preflight evidence | 0 | skipped | transport — '실행 안 됨' |
| 28 | [check] Admission predicate evaluation | 0 | skipped | verif-path — '실행 안 됨'(verdict 잡에서 실행) |
| 29 | [check] FAIL-CLOSED guard | 0 | skipped | verif-path — '실행 안 됨' |
| 30 | [check] Verify verdict log content | 0 | skipped | verif-path — '실행 안 됨' |
| 31 | [check] Upload verdict log | 0 | skipped | transport — '실행 안 됨' |
| 32 | [check] Upload admission records | 1 | success | transport |
| 63 | Post [check] Checkout candidate = H | 0 | success | env-platform |
| 64 | Post [check] Checkout executor tree = B | 1 | success | env-platform |
| 65 | Complete job | 0 | success | env-platform |

#### verdict / admission-check (wall 38s)

| # | step | wall | 결론 | 분류 |
|---|---|---|---|---|
| 1 | Set up job | 1 | success | env-platform |
| 2 | [venue] Resolve execution venue | 0 | success | verif-path |
| 3 | [check] Checkout executor tree = B | 4 | success | env-workspace |
| 4 | [check] Provision pinned jq | 1 | success | env-provision |
| 5 | [check] Install libpcre3 | 4 | success | env-provision |
| 6 | [slice-engine] Load epoch manifest implementedSlices | 0 | success | env-workspace |
| 7 | Run ./.github/actions/setup-axiom-toolchain | 0 | skipped | env-cache — '실행 안 됨' |
| 8 | [check] Checkout candidate = H | 0 | skipped | transport — '실행 안 됨' |
| 9 | [check] Download base-built artifacts | 2 | success | transport |
| 10 | [check] Verify artifact manifest | 0 | success | verif-path |
| 11 | [check] Core purity gate | 0 | skipped | verif-path — '실행 안 됨' |
| 12 | [check] Download lane-0 judgment artifacts | 0 | skipped | transport — '실행 안 됨' |
| 13 | [check] Download lane-1 judgment artifacts | 0 | skipped | transport — '실행 안 됨' |
| 14 | [check] Re-derive admission identity | 0 | skipped | verif-path — '실행 안 됨' |
| 15 | [preflight] Attest-leg static contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 16 | [check] Stage D9 evidence | 0 | skipped | verif-path — '실행 안 됨' |
| 17 | [check] Register subject | 0 | skipped | verif-path — '실행 안 됨' |
| 18 | [check] GO execution accounting cross-check | 0 | skipped | verif-path — '실행 안 됨' |
| 19 | [check] Attest witness-only | 0 | skipped | verif-path — '실행 안 됨' |
| 20 | [check] Upload evidence record | 0 | skipped | transport — '실행 안 됨' |
| 21 | [check] Upload judgment record | 0 | skipped | transport — '실행 안 됨' |
| 22 | [check] Load derived-closure sets | 1 | success | verif-path |
| 23 | [check] Fetch subject-certificate artifact | 2 | success | transport |
| 24 | [preflight] Verdict-leg static contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 25 | [check] Download derived-closure | 0 | skipped | transport — '실행 안 됨' |
| 26 | [preflight] Rotation-pin H2 contrast | 0 | skipped | verif-path — '실행 안 됨' |
| 27 | [preflight] Upload rotation-preflight evidence | 0 | skipped | transport — '실행 안 됨' |
| 28 | [check] Admission predicate evaluation (MergeAdmissible verdict → check conclusion) | 18 | success | verif-path |
| 29 | [check] FAIL-CLOSED guard | 0 | skipped | verif-path — '실행 안 됨' |
| 30 | [check] Verify verdict log content | 0 | success | verif-path |
| 31 | [check] Upload verdict log | 1 | success | transport |
| 32 | [check] Upload admission records | 0 | skipped | transport — '실행 안 됨' |
| 64 | Post [check] Checkout executor tree = B | 0 | success | env-platform |
| 65 | Complete job | 0 | success | env-platform |
