# attest / admission-check 작업 내부 분해 — 다음 병목 레버 후보 평가 (2026-10-12)

> **종류**: 성분 분해 분석 기록 (component decomposition analysis) — 라운드 R1 재감사가 선정한 다음 병목 목표 **소비 job `attest / admission-check`(점유율 68.2%)**의 내부 스텝 구조를 최근 merge_group 런 원기록에서 분해하고, 사전등록 문턱에 대한 후보 레버의 고려 자격을 기계적으로 평가한다. 본 문서는 코드·워크플로·게이트·판정 의미론을 변경하지 않는다(관측·분석만).
> **규율 원천**: `docs/evidence/merge_latency_decision_prereg_2026-10-12.md`(이하 "prereg") §3(다음 목표 선정·후보 고려 문턱)·§3.7(층 한정 평가·층명 의무 표기)·§6(동률·변경 없음) + `docs/evidence/merge_latency_cycle1_judgment_2026-10-12.md`(이하 "R1 판정") §5 + `docs/evidence/e3_measurement_contract_2026-10-11.md` §5.2·§7 + `docs/evidence/e3_amendment_a2_2026-10-11.md` A2.1(REUSED 분리).
> **권위**: 런/작업/스텝 존재·타임스탬프 = GitHub Actions API(GET-only), 레짐 마커·REUSED 분류 라인 = 작업 로그(E3 §9). 측정·분류는 등록 하니스 `tools/ci/merge_latency_audit.sh` 단일 패스를 그대로 사용했고, 스텝 채널만 같은 레코드 평면(`/actions/jobs/{id}` steps)에서 보강 인출했다. 본 문서는 Reporter다 — 병합 판정 권위(GitHub)를 대체하지 않는다(Authority ≠ Adapter).
> **측정 기준**: api-second-granularity(±1 s, E3 §7.2). 통계는 하니스와 동일 정의(표본 sd n−1, p50 선형보간).

---

## 1. 배경과 질의

- R1 판정 §5: 다음 목표 = 소비 job `attest / admission-check`(mean_R1 552.0 s, 점유율 68.2%, 동률 아님). 후보 고려 문턱(variance-aware): **`E[Δc] > max(1, 1.5×sd_pooled 90.0) = 135.0 s`(풀링)** — 등록 문턱표(§4)의 풀링 141.8 s·L층 39.5 s·H층 126.8 s와 병기되며, 층 한정 평가 사용 시 **층명 의무 표기**(prereg §3.7).
- R1 판정이 남긴 질의: (i) 이 job의 내부 스텝 구조는 무엇이고 (ii) 문턱을 넘는 신규 후보가 존재하는가, (iii) GO-critical 스텝(PR #754 병렬화 후보, 기대 −189 s)이 여전히 job 내부 지배 sub-lever인가.
- 전제 상태: verdict leg의 프로비전은 toolchain-handoff(PR #760)로 소멸(Tier 3 입증, R1 판정 §4). 소비 job `attest / admission-check`는 여전히 `setup-axiom-toolchain`을 실행하며 GO-critical 스텝을 포함한다.

## 2. 표본 — 열거·분류·코호트

단일 열거(2026-10-12T07:52:29Z, `event=merge_group` ∧ path endswith `admission-gate.yml` ∧ created 01:54:47Z..07:52:29Z): **26건**(스모크 앵커 `38193723834` 포함). 스모크 앵커는 prereg §1에 따라 제외 → post-smoke **25런 전량**을 등록 하니스로 단일 패스 측정·분류했다(exit 0).

| 분류 | 건수 | 비고 |
|---|---|---|
| EXECUTED | **17** | L 8 / H 9 |
| FULL_REUSE | 8 | 별도 층(A2.1.3) — 실행 비용 통계 불가산 |
| PARTIAL_REUSE / UNKNOWN_LOG | **0** | 라운드 중단 조건 미발생 |

- **분해 코호트**: (a) 등록 베이스라인 EXECUTED **23런**(`data/merge_latency/baseline_2026-10-11.runs.jsonl`), (b) post-go-live EXECUTED 17런 중 **시작순 마지막 10런**(04:10Z–07:38Z, L=5/H=5). 후자는 "최근 ~10 EXECUTED" 요구를 그대로 충족하며, run 결론 failure 6건 / success 4건을 포함한다(운영 벽시계 유지 관례 — R1 판정 §2와 동일). 전부 run_attempt=1, attest job 자체는 10/10 success(하니스 소비 job 식별 조건).
- **스텝 채널 동질성**: 33런(23+10)의 attest job에서 관측된 스텝 이름 집합이 **완전 동일**(결측 0, 신규/소멸 스텝 0) — 관측 창 전체에서 callee 워크플로 핀이 불변이었음의 기계 증거. 스텝별 n은 base 23/post 10으로 수렴한다.
- FULL_REUSE 8런의 attest job 길이(95–128 s, mean 115.3±11.9; baseline 2런 111/142)는 **GO 실행 없는 job의 바닥치**(§4)로 참조한다.

## 3. job 레벨 분해 — 임계 기여

| 지표 (s) | baseline EXEC (n=23) | post 최근 10 (n=10) | post L (n=5) | post H (n=5) |
|---|---|---|---|---|
| attest job duration | 592.3±94.5 (p50 638) | 551.0±103.3 (p50 566.5) | 635.6±31.9 | 466.4±71.4 |
| attest job **visible**(임계경로) | 567.5±86.0 | 511.9±127.5 | 603.6±51.8 | 420.2±113.5 |
| visible / wall | 64.0% | 61.2% | — | — |
| go_step_s | 486.7±101.8 | 438.2±109.9 | 531.4±31.1 | 345.0±67.2 |
| steps_sum | 589.0±94.3 | 547.8±102.7 | 631.8±31.4 | 463.8±71.4 |
| job head / tail | 1.3 / 2.0 | 1.0 / 2.1 | — | — |
| wall_s | 887.2±102.8 | 836.0±129.0 | — | — |

정합성: baseline job 592.3±94.5는 등록 문턱표(prereg §4) 값과 **일치**(원기록 재계산 동일성), steps_sum+head+tail = 547.8+1.0+2.1 = 550.9 ≈ duration 551.0(±1 s 반온림). job duration 중 스텝이 차지하는 몫 = 99.4% — **job 내부에 숨은 슬랙 없음**. 은닉 구간(duration−visible, 평행 선행 job 피복분)은 post 평균 39.1 s(base 24.8)로, 이미 상당한 leg 간 병렬화가 존재함을 뜻한다.

## 4. 스텝별 분해 — mean / p50 / sd

post 최근 10런(p50·sd는 post, L/H는 mean만)과 baseline 대비. 전체 23스텝 중 1 s 미만 상수 스텝(Post-cleanup·venue·slice-engine·register subject·stage D9 등)은 하단 군집으로 합산 보고한다.

| # | 스텝 | post mean±sd (p50) | post L / H | base mean±sd | 성격 |
|---|---|---|---|---|---|
| 1 | `[check] GO-critical admission tests (DEBT#432 — isVkdAdmissible/S1A/D2, fail-closed)` | **438.2±109.9 (448.0)** | 531.4 / 345.0 | 486.7±101.8 | GO-critical 판정 실행 |
| 2 | `Run ./.github/actions/setup-axiom-toolchain` | **62.7±12.1 (61.0)** | 51.6 / 73.8 | 57.3±14.1 | 툴체인 프로비전 |
| 3 | `[check] Attest witness-only (B-built ax kernel, H-derived data)` | 8.1±1.0 | 9.0 / 7.2 | 8.2±1.0 | witness 발행 |
| 4 | `[check] Judgment CAS plan (GO-critical judgment reuse ×4 subjects, SL-15 scope)` | 7.2±1.0 | 6.8 / 7.6 | 7.0±0.9 | CAS 계획 |
| 5 | `[check] Upload folded nimcache (B-cache carrier — J3 acceleration)` | 5.6±1.2 | 6.6 / 4.6 | 5.8±0.8 | 캐시 캐리어 |
| 6 | `[check] Re-derive admission identity (B/H/treeOID — fail-closed)` | 4.2±1.0 | 3.8 / 4.6 | 3.7±0.9 | 신원 재유도 |
| 7 | `[check] Core purity gate (B-built judge on _candidate tree)` | 3.6±0.8 | 4.2 / 3.0 | 4.0±1.0 | 순도 게이트 |
| 8 | `[check] Checkout executor tree = B (base.sha, workspace root)` | 3.1±0.6 | 3.0 / 3.2 | 2.8±0.7 | I/O |
| 9 | `[check] Merge base nimcache carrier (union — J3 acceleration)` | 2.9±0.9 | 3.4 / 2.4 | 2.8±0.8 | 캐시 캐리어 |
| 10 | `[check] Download base-built artifacts (B bin/ax + ir…)` | 2.6±0.5 | 2.8 / 2.4 | 2.4±0.7 | I/O |
| 11 | `[check] Checkout candidate = H (PR head / merge-group…)` | 2.6±0.5 | 2.8 / 2.4 | 2.3±0.5 | I/O |
| 12 | `Set up job` | 1.7±0.7 | 1.4 / 2.0 | 1.2±0.6 | 러너 |
| 13 | `[check] Upload evidence record (SL-15 admission ident…)` | 1.4±1.7 | 1.0 / 1.8 | 0.8±0.6 | 증거 업로드 |
| 14 | `[check] Upload admission records (witness + verdict)` | 1.2±0.4 | 1.2 / 1.2 | 1.0±0.5 | 증거 업로드 |
| 15 | `[check] Upload judgment record (s1a judgment CAS reu…)` | 1.0±0.5 | 1.2 / 0.8 | 1.0±0.4 | 증거 업로드 |
| 16 | `[check] Verify artifact manifest (fail-closed — buil…)` | 1.0±0.7 | 0.8 / 1.2 | 0.8±0.8 | 매니페스트 검증 |
| — | 소형 상수군 (Post-cleanup 2종·venue·slice-engine·register subject·stage D9·Complete) | 합 ≈1 s | — | 합 ≈1 s | 상수 |

**군집 요약 (post mean)**: GO-critical 438.2 (job의 **79.5%**) + setup-axiom-toolchain 62.7 (**11.4%**) + 나머지 전체 46.9 (**8.5%**) + head/tail 3.1 (0.6%) = 550.9 ≈ duration 551.0. 스텝 합계 정합: 438.2+62.7+46.9+3.1 = 550.9. go_step_s(하니스, `^\[check\] GO-critical` 다중매치 합) 평균 438.2가 1번 스텝 mean과 **정확히 일치** — GO 스텝은 단일 매치다.

**압축 가능 vs 고유**:

- **GO-critical 스텝(438.2 s)** — 유일하게 압축 여지가 큰 성분. 압축 기제는 이미 등록된 PR #754(4레인 병렬화)뿐이며 판정 실행 의미론 접촉 = MUST-adjacent(§6 L1).
- **setup-axiom-toolchain(62.7 s)** — 기계적으로 압축 가능(verdict-leg handoff 판례, §6 L2). 판정 의미론 비접촉(동일 핀 toolchain의 전달 경로 변경).
- **witness·CAS plan·purity·re-derive·증거 업로드(≈25 s)** — 판정·인증 의미론 그 자체(witness 발행, CAS 재사용 계획, fail-closed 신원 재유도). 고유 비용에 가까우며 접촉 시 MUST-adjacent.
- **I/O·캐리어·러너 상수(≈22 s)** — checkout/download/upload/manifest/러너. 상한이 낮고(전부 교체해도 ~22 s) 캐리어 스텝은 CAS 운반 의미론 접촉.
- **GO-less 바닥치**: FULL_REUSE 8런의 attest job = 95–128 s(115.3±11.9) ≈ setup 62.7 + 소형 클러스터 46.9 + head/tail 3.1의 함(112.7)과 일치 — **GO 스텝을 전부 제거해도 job은 ~110 s 아래로 내려가지 않는다**(판정 의미론 변경 없이는).

## 5. 후보 레버 평가 — 사전등록 문턱 대비

문턱: **pooled 135.0 s**(= max(1, 1.5×sd_pooled 90.0)). 층 한정 평가는 후보 기제가 특정 층에 결합할 때만 허용되고 층명을 표기한다(prereg §3.7).

| 레버 | 기제 | E[Δc] (불확도) | 의미론 접촉 | 문턱 판정 |
|---|---|---|---|---|
| **L1** GO-critical 4레인 병렬화 (PR #754 — **이미 등록됨**) | 스텝 내부 테스트 병렬화 + 레인별 nimcache/TMPDIR 격리 + hermetic 스탬프 경합 수정 | **−189 s** (등록 기대치; PR 국소 A/B 웜 513.0→307.7 = −205.3 s, 콜드 −263.9 s가 동 규모 실측 지지) | **GO-critical 실행 = MUST-adjacent** | **189 > 135.0 → 통과** — 단, 착지는 자체 사전등록 트리거 소관(§6) |
| **L2** attest-leg toolchain handoff (verdict-leg 판례 확장) | PR #760 메커니즘의 consumer 확장 — GO-scope (a′) 아티팩트에 toolchain payload 추가, setup 대체(Provision/Install) | **−56.9 s** (setup 62.7 − 판례 대체 비용 5.8±5.9; 상한도 −62.7) | 비접촉으로 보임(동일 핀 전달 경로) — 착지 시 게이트 재검증 필요 | **56.9 < 135.0 → 탈락**. 기제가 양층 공통(L 51.6/H 73.8)이라 층 한정 평가 부적용; H층 문턱 126.8 > 상한 73.8. (L층 39.5 < 45.8로 통과하는 독해가 있으나 L 결합 기제가 아니므로 §3.7상 허용 안 됨 — 정직 기록) |
| **L3** 소형 판정 클러스터 융합 | witness/CAS plan/purity/re-derive/증거 업로드 스텝 융합·배치 | 상한 −46.9 s(전체 소형 클러스터 전부), 현실 −15~25 s | **witness·CAS·증거 = MUST-adjacent** | **≪ 135.0 → 탈락** |
| **L4** 캐시 캐리어 가속 | B-cache 캐리어(J3)·a-restore 가속 — exact-key·verify-then-use·no restore-keys MUST 준수 전제 | 캐리어 스텝 실측 합 8.5 s, 최대 여지 ~10 s | **CAS 운반 = MUST-adjacent** | **≪ 135.0 → 탈락** |
| **L5** job 재배치·병렬화 확대 | attest를 다른 leg와 추가 피복 | 은닉 이미 39.1 s 존재, 갭 성분 전부 0.5% 미만(R1 §5), producer 아티팩트 의존으로 선행 불가 | 구조 변경 | **신뢰 경로 없음 → 탈락** |

## 6. 결론

1. **신규 고려자격 후보: 0개.** 문턱(135.0 s 풀링)을 넘는 레버는 이 job 내부에 하나 존재하고 그것은 이미 등록된 **PR #754(−189 s)** 뿐이다. #754는 (a) GO-critical 실행 의미론 접촉으로 MUST-adjacent이며 (b) 착지가 **자체 사전등록 트리거** — E3 단일 확증 분석 추출(`e3_measurement_contract_2026-10-11.md` §5.6; 창 한계 2026-11-10T02:52:14Z) — 과 δ 결속 게이트(A2.2: δ≤55 s 채택·밴드·전면보류·노출 창)에 묶여 있다. 단일 추출 완료 전 병합 금지(2중 처치 방지)는 prereg §7이 저장소 SSOT로 고정했다. **본 문서는 이를 재계획하지 않는다.**
2. **GO-critical 스텝은 여전히 job 내부 지배 sub-lever다** — post 코호트에서 job duration의 79.5%(438.2/551.0), L층 531.4±31.1 s로 더 크다. L1의 −189 s는 135.0 s 문턱을 넘는 유일 경로이며, 그 착지 시점에 소비 job 성분은 약 551→~360 s로 수렴할 것이나 이는 #754 자체 트리거의 판정 사안이다.
3. **루프의 다음 목표는 유지된다**: `attest / admission-check`. 목표 교체 요건(더 큰 점유 성분의 존재)은 없고(여타 전부 ≤8.3%), 신규 문턱 통과 후보도 없으므로 prereg §6 정신에 따라 **변경 없음**이 이 분해의 판정이다. 목표 위의 실질 진행은 #754 트리거 소관임이 본 분해의 유일한 행동 시사점이다.
4. **PLANNING-REQUIRED 목록(MUST-adjacent — 판정 의미론 접촉)**: L1(PR #754, 자체 트리거 소관), L3(witness/CAS/증거 클러스터 융합), L4(CAS 캐리어 캐시 가속). L2(attest-leg toolchain handoff)는 의미론 비접촉 후보이나 **문턱 미달로 부결** — 추진 근거 없음.
5. 규칙 준수: GET-only 인출 전체(gh api), 등록 하니스 재사용(분류·레짐 채널 변경 없음), FULL_REUSE 별도 층화, failure-conclusion 런의 운영 벽시계 유지, 스모크 앵커 제외. 본 문서는 코드·워크플로·게이트를 변경하지 않는다.

## 7. 검증 가능성

```bash
# 1) 열거 (GET-only)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-10-12T01:54:47Z..2026-10-12T07:52:29Z&per_page=100" \
  --paginate --jq '.workflow_runs[] | select(.path | endswith("admission-gate.yml")) | [.id, .run_started_at, .conclusion] | @tsv'
# 2) 등록 하니스 단일 패스(분류·레짐·go_step) — post-smoke 25 ids
tools/ci/merge_latency_audit.sh --runs <25 ids> --out <prefix> \
  --boundary-note "attest job decomposition analysis pool; smoke=38193723834 excluded"
# 3) 스텝 채널 보강 (GET-only) — 각 코호트 런의 attest job_id로
gh api repos/Archright/Axiom/actions/jobs/<attest_job_id> \
  --jq '[.steps[] | {name, number, s: .started_at, e: .completed_at, conclusion}]'
# 4) 집계 — 하니스와 동일 정의(표본 sd n−1, p50 선형보간)로 스텝별 mean/p50/sd 재계산
#    정합성 검증: baseline job 592.3±94.5 == prereg §4 등록치, steps_sum+head+tail == job duration(±1 s)
```

스텝 채널 원데이터는 하니스 runs.jsonl에 저장되지 않는 채널이므로(하니스는 go_step 합만 보존), 본 분석의 코호트·집계는 위 명령으로 GET-only 재생 가능하다. 부록 A에 런 단위 원값을 보존한다(재인출 없는 1차 검증용).

## 부록 A — 코호트 런 단위 원값 (s)

| 코호트 | run | 레짐 | run 결론 | wall | job dur | job visible | go_step | steps_sum |
|---|---|---|---|---|---|---|---|---|
| base | 38106561118 | H | success | 670 | 386 | 386.0 | 277 | 383 |
| base | 38108480897 | L | success | 947 | 642 | 612.0 | 545 | 640 |
| base | 38109033392 | L | success | 924 | 638 | 615.0 | 548 | 634 |
| base | 38109479498 | L | failure | 985 | 637 | 637.0 | 542 | 634 |
| base | 38110787877 | H | success | 667 | 389 | 388.0 | 280 | 386 |
| base | 38129273102 | H | success | 757 | 471 | 470.0 | 351 | 468 |
| base | 38129755277 | L | success | 924 | 639 | 595.0 | 551 | 634 |
| base | 38130173518 | L | success | 923 | 589 | 553.0 | 478 | 585 |
| base | 38131088390 | H | success | 835 | 546 | 515.0 | 421 | 542 |
| base | 38136162023 | L | success | 980 | 726 | 679.0 | 615 | 721 |
| base | 38139501402 | L | success | 928 | 640 | 614.0 | 547 | 636 |
| base | 38140848433 | L | success | 910 | 644 | 598.0 | 547 | 642 |
| base | 38141497778 | L | success | 943 | 654 | 636.0 | 549 | 650 |
| base | 38141879562 | L | success | 920 | 634 | 631.0 | 545 | 632 |
| base | 38145451605 | L | success | 917 | 642 | 602.0 | 550 | 640 |
| base | 38145908498 | L | failure | 1008 | 641 | 599.0 | 550 | 639 |
| base | 38147391578 | H | success | 822 | 551 | 551.0 | 411 | 547 |
| base | 38147642079 | H | success | 862 | 575 | 534.0 | 424 | 571 |
| base | 38149366483 | L | success | 970 | 652 | 622.0 | 544 | 649 |
| base | 38149721402 | H | success | 671 | 393 | 373.0 | 282 | 390 |
| base | 38150945786 | L | failure | 942 | 636 | 605.0 | 543 | 634 |
| base | 38153970409 | L | success | 945 | 643 | 624.0 | 550 | 639 |
| base | 38154520008 | L | success | 956 | 656 | 613.0 | 544 | 650 |
| post | 38202703646 | L | success | 874 | 639 | 637.0 | 542 | 636 |
| post | 38203209031 | L | failure | 1069 | 648 | 525.0 | 544 | 643 |
| post | 38207762674 | H | failure | 777 | 535 | 527.0 | 420 | 533 |
| post | 38209754465 | L | failure | 872 | 652 | 642.0 | 546 | 648 |
| post | 38211567606 | H | failure | 644 | 421 | 421.0 | 302 | 418 |
| post | 38214362505 | L | success | 924 | 659 | 638.0 | 549 | 655 |
| post | 38216902606 | H | success | 658 | 419 | 415.0 | 291 | 415 |
| post | 38217260300 | H | failure | 934 | 553 | 501.0 | 417 | 550 |
| post | 38217752691 | H | failure | 779 | 404 | 237.0 | 295 | 403 |
| post | 38218853433 | L | success | 829 | 580 | 576.0 | 476 | 577 |

## 부록 B — post-smoke 전 런 분류 장부 (침묵 탈락 없음)

하니스 단일 패스(2026-10-12T07:52Z). 스모크 앵커 `38193723834`(01:54:47Z)는 prereg §1로 제외.

| run | started (Z) | 분류 | 레짐 | wall | 분해 코호트 |
|---|---|---|---|---|---|
| 38194556640 | 02:07:27 | EXECUTED | H | 766 | — (초기 런, 최근 10 밖) |
| 38195558280 | 02:22:55 | FULL_REUSE | H | 350 | — |
| 38196395802 | 02:35:42 | EXECUTED | L | 963 | — |
| 38197725016 | 02:55:46 | FULL_REUSE | H | 343 | — |
| 38199481287 | 03:22:14 | EXECUTED | L | 853 | — |
| 38199696633 | 03:25:34 | EXECUTED | H | 640 | — |
| 38200410801 | 03:36:22 | EXECUTED | L | 825 | — (R1 N5) |
| 38200436346 | 03:36:45 | EXECUTED | H | 654 | — |
| 38201219794 | 03:48:37 | EXECUTED | H | 623 | — |
| 38202703646 | 04:10:25 | EXECUTED | L | 874 | **post #1** |
| 38203209031 | 04:17:56 | EXECUTED | L | 1069 | **post #2** |
| 38205887178 | 04:57:31 | FULL_REUSE | H | 551 | — |
| 38207762674 | 05:24:01 | EXECUTED | H | 777 | **post #3** |
| 38209441790 | 05:46:50 | FULL_REUSE | H | 362 | — |
| 38209754465 | 05:51:00 | EXECUTED | L | 872 | **post #4** |
| 38211473519 | 06:13:16 | FULL_REUSE | L | 318 | — |
| 38211567606 | 06:14:29 | EXECUTED | H | 644 | **post #5** |
| 38214225149 | 06:46:54 | FULL_REUSE | L | 347 | — |
| 38214362505 | 06:48:32 | EXECUTED | L | 924 | **post #6** |
| 38216902606 | 07:17:20 | EXECUTED | H | 658 | **post #7** |
| 38217260300 | 07:21:14 | EXECUTED | H | 934 | **post #8** |
| 38217751618 | 07:26:32 | FULL_REUSE | L | 563 | — |
| 38217752691 | 07:26:32 | EXECUTED | H | 779 | **post #9** |
| 38218678798 | 07:36:23 | FULL_REUSE | H | 358 | — |
| 38218853433 | 07:38:14 | EXECUTED | L | 829 | **post #10** |
