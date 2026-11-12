# 병합 지연 라운드 R1 판정 — 사전등록 규칙의 기계 적용 (2026-10-12)

> **종류**: 라운드 판정 기록 (round judgment record) — `docs/evidence/merge_latency_decision_prereg_2026-10-12.md`(이하 "prereg")이 고정한 규칙을 **확증 표본 N=5 도달 시점에 단 한 번** 적용한 결과다. 본 문서는 규칙을 새로 만들거나 수정하지 않는다(사전등록 고정성 준수). 관측·판정은 GET-only이며 GitHub의 merge-admission 권위를 대체하지 않는다(Authority ≠ Adapter).
> **측정 도구**: `tools/ci/merge_latency_audit.sh`(GET-only reporter) · go-live 경계: `tools/ci/golive_detect.sh`.
> **원기록**: `data/merge_latency/confirm_2026-10-12_R1.runs.jsonl`(+`.summary.json`·`.compare.json/md`·`.snet.json/md`), 라운드 스캔 장부 `data/merge_latency/confirm_2026-10-12_R1_roundscan.runs.jsonl`, 등록 베이스라인 `data/merge_latency/baseline_2026-10-11.runs.jsonl`.

---

## 1. 라운드 정의와 종결

- **변경**: toolchain-handoff(PR #760, T_land `2026-10-12T00:46:47Z`) — go-live(활성화) 경계는 `2026-10-12T01:54:13Z`, 첫 신경로 런 `38193686820`(탐지기 등식 blob==TWS; 활성화 경계 레코드 `data/e4e5/landing_boundaries/2026-10-12T015413Z-golive-activation.json`).
- **스모크 앵커**: `38193723834`(01:54:47Z) — **모든 확증 통계에서 제외**(전환 검증 런; prereg §1).
- **라운드 R1 종결**: 시작 시각 오름차순 5번째 EXECUTED 런 = `38200410801`의 종료 시점 **2026-10-12T03:50:07Z**. 이후 종료한 런은 판정에 불가산(prereg §2.5).
- **UNKNOWN 검사**: 라운드 내 관측된 전 런에서 `classification=UNKNOWN_LOG` 0건, `regime=unknown` 0건, 하니스 하드페일(exit 1) 0건 → **라운드 중단 없음**(prereg §6). 측정 패스 exit code = 0.

## 2. 라운드 장부 (post-smoke 전 런 — 침묵 탈락 없음)

스캔 시점: 2026-10-12T04:00Z 단일 열거(`event=merge_group` ∧ `admission-gate.yml` ∧ started > 01:54:47Z). 9건 전부 `run_attempt=1`, 전부 측정 완료(단일 패스).

| 순번 | run | started (Z) | 큐 키(head_branch 접두) | 종결 | 분류 | 레짐 | N 기여 |
|---|---|---|---|---|---|---|---|
| 제외 | 38193686820 | 01:54:13 | pr-765-61870f82 | success | (탐지기: post_golive) | — | **앵커 이전 시작** — prereg §2.1 엄격 초과 위반. 활성화 경계 레코드에 관측치 기록(verdict leg 33 s, setup SKIPPED) |
| 제외 | 38193723834 | 01:54:47 | pr-765-1db435db | success | (앵커) | — | **스모크 앵커** — prereg §1 제외 |
| 1 | 38194556640 | 02:07:27 | pr-766-e8cde165 | failure | EXECUTED | H | **N1** |
| 2 | 38195558280 | 02:22:55 | pr-767-e8cde165 | success | FULL_REUSE | H | 0 — 별도 층 보고(§2.4), N 불가산 |
| 3 | 38196395802 | 02:35:42 | pr-766-6ed4a691 | failure | EXECUTED | L | **N2** |
| — | 38197725016 | 02:55:46 | pr-766-6ed4a691 | success | FULL_REUSE | H | 0 — **dependent_repeat**(3과 동일 키) ∧ FULL_REUSE |
| 4 | 38199481287 | 03:22:14 | pr-769-c3f1d982 | success | EXECUTED | L | **N3** |
| 5 | 38199696633 | 03:25:34 | pr-770-7bfe602a | success | EXECUTED | H | **N4** |
| 6 | 38200410801 | 03:36:22 | pr-771-446a56d | success | EXECUTED | L | **N5** — 라운드 종결 런 (03:50:07Z) |
| — | 38200436346 | 03:36:45 | pr-772-93f06f2 | success | EXECUTED | H | 0 — 시작순 6번째 EXECUTED(§2.4 "첫 5개" 밖). 라운드 내 관측(03:47:39Z 종료), 장부 누적 |
| — | 38201219794 | 03:48:37 | pr-773-c55369b | success | EXECUTED | H | 0 — 라운드 종료(03:50:07Z) **이후** 종료(03:59:00Z), ledger 누적만 |

**R1 확증 표본(N=5)**: `38194556640, 38196395802, 38199481287, 38199696633, 38200410801` — EXECUTED 5(L 3 / H 2), 실패 종결 2건 포함(운영 벽시계 유지). FULL_REUSE 별도 층: baseline 2/25 vs 라운드 관측 2/9(`38195558280` 350 s, `38197725016` 343 s) — 실행 비용 통계에는 계수되지 않는다(A2.1.3).

## 3. 측정 — prereg §2.6 고정 명령 실행

```bash
tools/ci/merge_latency_audit.sh --runs 38194556640,38196395802,38199481287,38199696633,38200410801 \
  --out data/merge_latency/confirm_2026-10-12_R1 \
  --boundary-note "toolchain-handoff go-live smoke=38193723834 excluded; R1 confirmatory"   # exit 0
tools/ci/merge_latency_audit.sh --compare \
  data/merge_latency/baseline_2026-10-11.runs.jsonl data/merge_latency/confirm_2026-10-12_R1.runs.jsonl \
  --out data/merge_latency/confirm_2026-10-12_R1                                            # exit 0
```

## 4. 효과 판정 — 3단 (prereg §5)

### Tier 1 — 구현 성공: **충족**

신경로 기계 서명이 스모크 런 + 활성화 런 6/6에서 관측: producer `[build] Compile derived-closure deriver from B`(3 s) + `[build] Fetch pinned jq 1.7.1` + **7멤버 매니페스트**, verdict leg `setup-axiom-toolchain` **SKIPPED** + `[check] Provision pinned jq` + `[check] Install libpcre3` (경계 레코드 `verdict_leg_newpath_capture` 참조). 전환 검증이며 성능 주장이 아님(prereg §5 Tier 1 유의문구 준수).

### Tier 2 — 초기 성능 신호 (서술 비교, N=5 단일 패스)

`--compare` 산출(`confirm_2026-10-12_R1.compare.md` 전문):

| component | baseline mean±sd | R1 mean±sd | delta | Δ_L | Δ_H |
|---|---|---|---|---|---|
| wall_s [operational, ALL] | 848.4±166.7 (n=25) | 809.4±118.7 (n=5) | **−39.0** | — | — |
| wall_s [EXECUTED only] | 887.2±102.8 (n=23) | 809.4±118.7 (n=5) | **−77.8** | **−64.8** | **−51.9** |
| dur_sum_s | 870.0±104.1 | 793.0±119.3 | −77.0 | −64.1 | −49.9 |
| gaps_sum_s | 13.4±4.1 | 12.2±0.8 | −1.2 | — | — |
| residual_s | 3.8±0.9 | 4.2±0.8 | +0.4 | — | — |
| go_step_s | 486.7±101.8 | 470.4±109.4 | −16.3 | — | — |

REUSED 층: baseline FULL_REUSE=2 / R1 파일=0(별도 층 분리 — §2 장부 참조). 실패 종결 런은 운영 벽시계에 유지됐다.

### Tier 3 — 성능 개선 입증: **충족 (사전등록 규칙의 기계 판정)**

**(a) verdict-leg provision+handoff 스텝 총합 — 통과**

- 채널: prereg §5.1(a) 고정 snet 명령(`--baseline-provision 64.7 --producer-steps '^setup-axiom-toolchain' --consumer-steps 'Provision pinned jq|Install libpcre3'`).
- **실행 비고(투명 기록)**: 고정 명령의 `*.runs.jsonl` 인자 형태가 하니스 `resolve_runs_arg`의 JSONL 파싱 한계로 실패한다(compare 모드는 `cp` 경로라 영향 없음). 규칙·채널·문턱 변경 없이 하니스가 동등 수용하는 `@idsfile` 형태로 **동일 등록 런 집합**(baseline 25 ids / R1 5 ids, 각 원기록에서 `jq -r '.run_id'`로 기계 추출)을 투입해 실행했다(exit 0). 하니스 인자 파서 수리는 후속 과제다.
- 산출(`confirm_2026-10-12_R1.snet.json`): `T_old_provision = 64.7 s`(등록 오버라이드), producer 채널 양측 매치 0(스텝 실명은 `Run ./.github/actions/setup-axiom-toolchain` — `^` 앵커 미매치; ΔT_producer = 0), consumer after visible mean = **5.8±5.9 s**(n=5; 런별 0/0/7/8/14).
- **판정값**: 절감 = 64.7 − 5.8 = **58.9 s > 19.4 s**(= max(1, 1.5×max(sd_base 12.9, sd_after 5.9)) = 19.4) → **통과**.
- **민감도**: 0 s로 계수된 2런은 verdict job이 failure 종결한 런으로, 하니스 snet이 success job의 스텝만 인출하기 때문이다(두 런 모두 handoff 스텝 자체는 success — 경계 레코드 스텝 표: jq 1+5 s, 0+5 s). 이 실측치를 반영하면 after mean 8.0 s, 절감 56.7 s — **문턱 통과는 양쪽 방식 모두 동일**하다.

**(b) 게이트 wall-clock — 통과 (경로 (i))**

- `delta_L = −64.8 < 0` **AND** `delta_H = −51.9 < 0` — 양층 감소(prereg §5.1(b)(i)). 양 코호트 모두 양층 비어 있지 않음(baseline L16/H7, R1 L3/H2) → 층 공백 예외 조항 불발동, 경로 (ii) 검토 불요.
- 참고(주장 아님): 풀링 operational Δ = −39.0 s, 레짐믹스 보정 가중 차(w_L=2/3, w_H=1/3) = (2/3)(−64.8)+(1/3)(−51.9) = **−60.5 s** < 0.

**Tier 3 = (a) ∧ (b) → 둘 다 충족. 사전등록 규칙에 따라 이 변경의 효과는 "개선 입증"으로 판정된다.**

- 판정 근거의 정확한 범위: (a) verdict-leg 프로비전 채널(구 setup 64.7 s → handoff 대체 5.8 s)과 (b) 게이트 wall 레짐별 양층 감소. 운영 전체 wall(−39.0 s)과 EXECUTED wall(−77.8 s)의 점 추정은 감소 방향이지만, 하니스 종료 규칙의 변동 바(required_min_saving = 118.7 s)를 EXECUTED Δ가 넘지 않는다는 점은 별도 사실로 기록한다 — 이는 **루프 종료 규칙 입력**이지 본 판정의 조건이 아니다(prereg §5는 (a)∧(b)만을 조건으로 고정했다).

## 5. 다음 병목 목표 재감사 — prereg §3 기계 계산

R1 원기록 `critical_path`(visible_s, hidden 제외)·`gap_segments`·`residual_s` + 등록 베이스라인(EXECUTED 23) 원기록에서: 성분별 mean(R1 5런), pooled 표본 sd(baseline ∪ R1, n=28), `share = mean/mean_wall(809.4 s)`, `min_saving = max(1, 1.5×sd_pooled)`.

| 순위 | 성분 | mean_R1 (s) | sd_pooled (s) | share (%) | min_saving (s) |
|---|---|---|---|---|---|
| **1** | **소비 job `attest / admission-check`** | **552.0** | **90.0** | **68.2** | **135.0** |
| 2 | `closure-deriver` | 66.8 | 41.2 | 8.3 | 61.8 |
| 3 | `verdict / admission-check` | 58.0 | 38.1 | 7.2 | 57.2 |
| 4 | `mint-publish / publish` | 54.8 | 8.7 | 6.8 | 13.1 |
| 5 | `mint-prepare / prepare` | 31.0 | 5.9 | 3.8 | 8.9 |
| 6 | `attest / build-base-artifacts` | 14.2 | 39.7 | 1.8 | 59.6 |
| 7 | `gateway / select` | 12.6 | 21.5 | 1.6 | 32.3 |
| 8 | residual | 4.2 | 0.9 | 0.5 | 1.4 |

(갭 성분 `from → to` 쌍은 전부 0.5% 미만 — 상위 8건 밖. 전체 표는 원계산 jq로 재현 가능 — 부록 A.)

- **동률 검사**: 1·2위 점유율 차 = 68.2 − 8.3 = **59.9 pp ≥ 1.0 pp** → 동률 아님(prereg §3.5).
- **목표 선정**: `target = argmax share` = **소비 job `attest / admission-check`(68.2%)** — 변경 전 목표와 동일(현 목표 집합 유지).
- **후보 고려 문턱(variance-aware)**: 이 성분 위의 다음 레버는 `E[Δc] > max(1, 1.5×90.0) = 135.0 s`(풀링)일 때만 고려된다. 등록 문턱표(§4)의 소비 job 풀링 141.8 s·L층 39.5 s·H층 126.8 s와 병기하며, 층 한정 평가를 쓰면 **층명을 의무 표기**한다(prereg §3.7). 본 판정 시점에 문턱을 넘는 구체적 후보 변경을 선언하지 않는다(후보 발굴은 다음 레버 설계의 몫).
- 구 `setup-axiom-toolchain` 프로비전 성분은 handoff로 **소멸**(R1 mean 0) — 소멸 성분 비교 기준 sd(12.9)는 §4 문턱표에 등록된 대로 보존된다.

## 6. 결론

1. **R1 라운드는 UNKNOWN·하드페일 없이 정상 종결**(N=5, 단일 분석).
2. **효과 판정: Tier 3 "개선 입증"** — (a) verdict-leg 절감 58.9 s > 19.4 s, (b) wall Δ_L=−64.8<0 ∧ Δ_H=−51.9<0. 사전등록 규칙의 기계 적용이며 해석 여지를 남기지 않는다.
3. **다음 목표: 소비 job `attest / admission-check`**(점유율 68.2%, 동률 아님) — 후보 문턱 135.0 s(풀링).
4. 규칙 준수 사항: 스모크·경계 이전 런 제외 사유 장부 기록, FULL_REUSE·dependent_repeat 별도 층화, snet 고정 명령의 인자 형태 동등 치환 1건 투명 기록(하니스 수리 후속).

## 부록 A — 재현

```bash
# R1 측정·비교·snet (§3 명령 + @idsfile 치환)
tools/ci/merge_latency_audit.sh --runs 38194556640,38196395802,38199481287,38199696633,38200410801 \
  --out data/merge_latency/confirm_2026-10-12_R1 \
  --boundary-note "toolchain-handoff go-live smoke=38193723834 excluded; R1 confirmatory"
tools/ci/merge_latency_audit.sh --compare data/merge_latency/baseline_2026-10-11.runs.jsonl \
  data/merge_latency/confirm_2026-10-12_R1.runs.jsonl --out data/merge_latency/confirm_2026-10-12_R1
jq -r '.run_id' data/merge_latency/baseline_2026-10-11.runs.jsonl > /tmp/base.ids
jq -r '.run_id' data/merge_latency/confirm_2026-10-12_R1.runs.jsonl > /tmp/after.ids
tools/ci/merge_latency_audit.sh --snet --baseline @/tmp/base.ids --after @/tmp/after.ids \
  --baseline-provision 64.7 --producer-steps '^setup-axiom-toolchain' \
  --consumer-steps 'Provision pinned jq|Install libpcre3' --out data/merge_latency/confirm_2026-10-12_R1
```

성분 집계(§5)에 쓴 jq 원계산 프로그램: `critical_path[] | select(.hidden != true)`의 `visible_s`를 job명 정확 일치 그룹 합산, `gap_segments[]`를 `from → to` 쌍 합산, `residual_s` 독립 성분 — pooled sd는 baseline(EXECUTED) ∪ R1 값 나열의 표본편차(n−1). 본 판정 집계 결과물은 `confirm_2026-10-12_R1.runs.jsonl`·`baseline_2026-10-11.runs.jsonl`만 입력으로 다시 계산할 수 있다.
