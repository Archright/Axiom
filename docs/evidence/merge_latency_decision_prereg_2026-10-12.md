# 병합 지연 의사결정 사전등록 — 확증 수집 이전 규칙 고정 (2026-10-12)

> **종류**: 사전등록 문서 (decision pre-registration) — toolchain-handoff go-live 이후의 **확증 N≥5 수집이 완료되기 전에** 다음 병목 목표 선정 규칙과 현행 변경의 효과 판정 규칙을 숫값으로 고정한다 (no-peeking — 원측정 계약 §5.6과 동일 규율; 결과를 본 뒤 규칙을 고르는 것을 원천 차단).
> **규율 원천**: `docs/evidence/e3_measurement_contract_2026-10-11.md` §5.6(고정 n·단일 분석·중지 규칙)·§7(wall 정의·정밀도) + `docs/evidence/e3_amendment_a2_2026-10-11.md` A2.1(분류)·A2.2(δ 게이트)·A2.3(wall 판정) + `tools/ci/merge_latency_audit.sh` 헤더의 사전등록 측정 규약 + 등록 베이스라인 `docs/evidence/merge_latency_baseline_2026-10-12.md` / `data/merge_latency/baseline_2026-10-11.runs.jsonl`.
> **고정성**: 본 문서가 main에 착지하는 순간 아래 규칙은 **고정**된다. 착지 이후의 규칙 변경은 금지이며, 변경이 필요하면 **새 날짜의 사전등록 문서**로만 한다(본 문서 개정 금지).
> **권위**: 런/작업/스텝 존재·타임스탬프 = GitHub Actions API, 레짐 마커·REUSED 분류 라인 = 작업 로그(E3 §9 권위표). `merge_latency_audit.sh`는 Reporter다 — 병합 판정 권위(GitHub)를 대체하지 않는다(Authority ≠ Adapter).

---

## 1. 배경과 경계 — go-live와 스모크 런

- **변경**: toolchain-handoff(landing verdict 재프로비저닝 제거, GO 스코프 (a') 아티팩트 확장) — T_land `2026-10-12T00:46:47Z`, merge `d975fc936`, PR #760. 게이트 근거 `docs/evidence/verdict_payload_gate_2026-10-12.md`(S_net +53.3s 보수 / +61.0s 관측). 착지 경계 레코드 `data/e4e5/landing_boundaries/2026-10-12T004647Z-toolchain-handoff-a-prime.json`.
- **go-live 메커니즘**: org caller(`Archright/.github` `admission-gate.yml`)가 callee(`Archright/Axiom` `.github/workflows/admission-check.yml`)를 **고정 커밋 SHA**로 호출하므로, Axiom main 착지와 별개로 Dependabot 핀 회전이 live를 결정한다(`tools/ci/golive_detect.sh`, `docs/evidence/external_trust_anchor_org_workflow_2026-10-12.md`). 회전 #168–#170(01:48–01:52Z) 직후 최초 신경로 런 관측 — golive 탐지기 `first_post_run_id` = `38193686820`(01:54:13Z).
- **스모크 런(본 등록의 앵커) = `38193723834`**(2026-10-12T01:54:47Z, success) — 전환 **검증** 런이다. 기계 서명: producer에 deriver 컴파일·pinned jq 페치 스텝 + 7멤버 매니페스트, verdict leg에 `setup-axiom-toolchain` **부재**(신규 경로 스텝으로 대체), verdict job 실측 **39 s**(01:59:56→02:00:35) vs 구경로 103.2 s(페이로드 게이트 문서 §1). 스모크 런은 **모든 확증 통계에서 제외**된다 — 전환 확인은 성능 관측이 아니다.
- **경계 유의**: golive 탐지기의 최초 post 런은 `38193686820`(01:54:13Z)으로 스모크 앵커보다 34 s **이전** 시작이다. 이 런은 확증 표본에 들어가지 않으며(§2 모집단 정의가 앵커 **엄격 초과**를 요구), ledger에 **제외 사유와 함께 기록**된다 — 조용한 탈락 없음.

## 2. 표본 정의 (확증 표본 — 사전고정)

1. **모집단**: `event=merge_group` ∧ 런 레코드 `path`가 `admission-gate.yml`로 끝남(하니스 `GATE_PATH`와 동일 식별) ∧ `run_attempt=1` ∧ `run_started_at > 2026-10-12T01:54:47Z`(스모크 앵커 엄격 초과).
2. **독립성 키**: 런의 `head_branch`(큐 브랜치명 = PR×병합 베이스 SHA)가 관측 단위다. **같은 키의 두 번째 이후 런은 `dependent_repeat`로 기록되며 N에 진행하지 않는다**(같은 코드 상태 재시도는 런간 변동의 독립 표본이 아님 — fail-closed). 재시도(attempt≥2)도 마찬가지로 기록만 하고 N 불가.
3. **분류**: A2.1.2 기계 분류 — `EXECUTED` / `FULL_REUSE` / `PARTIAL_REUSE` / `UNKNOWN_LOG`. 레짐: a-restore 마커 40,000 ms 임계(E3 §5.2), 미판별 → `unknown`(A2.2.7 fail-closed).
4. **확증 표본 N**: 위 순서(`run_started_at` 오름차순)의 **첫 5개 EXECUTED 런** (N=5 고정). **FULL_REUSE·PARTIAL_REUSE·dependent_repeat 런은 ledger에 기록·별도 층으로 보고되지만(A2.1.3) N을 진행시키지 않는다** — 수집은 N=5 도달까지 계속.
5. **라운드 종료와 단일 분석**: 5번째 EXECUTED 런 종료 시점에 라운드 R1은 닫히고 **딱 한 번** 분석 수행(§5.6 단일 분석 준용 — 측정은 `merge_latency_audit.sh` 단일 패스). 그 이후 종료하는 런은 본 라운드 판정에 **불가산**이며 ledger에만 누적된다. 중간 추출·중간 분석 금지 — 분류·레짐 판독은 하니스의 기계 분류로, 라운드 종료 시점에 일괄 수행한다.
6. **측정 명령 (고정)**:

```bash
tools/ci/merge_latency_audit.sh --runs <R1 확증 run ids> \
  --out data/merge_latency/confirm_2026-10-12_R1 \
  --boundary-note "toolchain-handoff go-live smoke=38193723834 excluded; R1 confirmatory"
tools/ci/merge_latency_audit.sh --compare \
  data/merge_latency/baseline_2026-10-11.runs.jsonl data/merge_latency/confirm_2026-10-12_R1.runs.jsonl \
  --out data/merge_latency/confirm_2026-10-12_R1
```

## 3. 다음 병목 목표 선정 지표 (decision metric — 계산식 고정)

측정 루프의 다음 목표는 **게이트 wall-clock의 잔여 점유율이 가장 큰 성분**이다. 임계경로 재감사는 확증 표본 원기록(`confirm_2026-10-12_R1.runs.jsonl`)의 `critical_path`·`gap_segments`·`residual_s` 필드에서 다음과 같이 **기계적으로** 계산한다:

1. **성분 정의**: (i) job 성분 = `critical_path[].job` 이름 **정확 일치** 그룹(숨은 세그먼트 `hidden=true`는 중복 방지 위해 가산하지 않고 `visible_s`만 가산), (ii) 갭 성분 = `gap_segments[]`의 `from→to` 쌍 그룹별 `gap_s` 합, (iii) `residual` 성분 = `residual_s`.
2. **집계**: 성분 c별 `mean_c` = EXECUTED 분모 런의 c값 산술평균; `sd_c` = **합집합 표본 sd** — 등록 베이스라인(25런 원기록, EXECUTED 분모)과 R1 표본의 c값을 합한 표본의 표본편차(n−1). 변경으로 소멸한 성분(예: 구 `setup-axiom-toolchain`)은 baseline sd만 사용.
3. **점유율**: `share_c = mean_c / mean_wall` — 분모 `mean_wall` = **같은 EXECUTED 런 집합**의 `wall_s` 평균(E3 §7.1 정의). 층별 보고는 부수로, 선정은 풀링값으로 한다.
4. **선정 규칙**: `target = argmax share_c`.
5. **동률**: 상위 두 성분의 `share` 차가 **1.0 미포인트 미만이면 동률**로 보고 → **변경 없음**(현 목표 집합 유지, §6).
6. **후보 고려 조건 (variance-aware termination)**: 선정된 성분 위의 후보 변경은 기대 절감이 **둘 다** 초과할 때만 고려된다: `E[Δc] > max(1 s, 1.5 × sd_c)` — 1 s는 API 초 해상도(E3 §7.2), 1.5×sd는 런간 변동 마진. 이 레저의 하니스 종료 규칙(`required_min_saving_s = max(resolution, sd)`)의 **강화판**이며, 어떤 성분도 문턱을 넘는 후보가 없으면 **루프 종료**다.
7. **레짐 의존 성분**: L/H 이봉이 확인된 성분(§4 표)은 풀링 sd가 레짐 혼입으로 부풀려진다 — 후보의 기제가 특정 층에 결합한다면 **층 한정 평가**(해당 층의 sd로 같은 산식)를 허용하되, 주장·목표 표기에 **층명을 의무 명기**한다. 레짐 미판별 런은 H 밴드를 적용한다(A2.2.7).

## 4. 알려진 성분의 문턱표 (임계값 고정)

등록 베이스라인 실측(출처: `merge_latency_baseline_2026-10-12.md` §3.2·§3.4·§5 및 `data/merge_latency/baseline_2026-10-11.runs.jsonl` 원기록 재계산 — §4.1 명령). `min_saving = max(1, 1.5 × sd)`.

| 성분 | baseline mean±sd (s) | 분모 | min_saving (s) | 비고 |
|---|---|---|---|---|
| verdict 프로비전 (구 `setup-axiom-toolchain` full) | 64.7±12.9 | 25/25 런 | **19.4** | 등록치(페이로드 게이트 §1·§4); handoff로 소멸 — 소멸 성분 비교 기준 sd |
| 소비 job `attest / admission-check` (pooled) | 592.3±94.5 | EXECUTED 23 | **141.8** | L/H 이봉 — 풀링 sd는 혼입 부풀림 |
| 소비 job 동일 (운영 전체 분모) | 555.1±157.6 | 전체 25 | **236.4** | fail-closed 변형(등록 요약의 "~154 이봉" 계열 값) |
| 소비 job — L층 | 644.6±26.3 | EXECUTED L 16 | **39.5** | 층 한정 평가 전용 |
| 소비 job — H층 | 473.0±84.5 | EXECUTED H 7 | **126.8** | 층 한정 평가 전용 |
| wall (EXECUTED) | 887.2±102.8 | EXECUTED 23 | **154.2** | baseline §3.2 |
| wall — L층 | 945.1±28.1 | L 16 | **42.2** | baseline §3.4 |
| wall — H층 | 754.9±86.0 | H 7 | **129.0** | baseline §3.4 |
| dur_sum | 846.6±100.6 | EXECUTED 23 | **150.9** | |
| gaps_sum | 12.5±4.7 | EXECUTED 23 | **7.1** | |
| residual | 28.1±65.6 | EXECUTED 23 | **98.4** | failure-conclusion 3런이 상위 꼬리 — conclusion 투영 분리 권장 |
| go_step (GO-critical 스텝) | 486.7±101.8 | EXECUTED 23 | **152.7** | baseline §3.2 |
| producer job `attest / build-base-artifacts` | 82.1±11.7 | 전체 25 | **17.6** | |
| 신규 job `closure-deriver` | — (baseline 무) | after-only | max(1, 1.5×sd_after) | R1에서 sd 채택 |

### 4.1 원기록 재계산 명령 (검증 가능성)

```bash
jq -s '[.[].jobs[] | select(.job == "attest / admission-check") | .duration_s] |
  {n: length, mean: ((add/length)*10|round/10),
   sd: (((map(.*.)|add) - ((add*add)/length)) / (length-1) | sqrt*10|round/10)}' \
  data/merge_latency/baseline_2026-10-11.runs.jsonl     # → 555.1±157.6 (n=25)
# EXECUTED 분모 버전: .[] | select(.classification=="EXECUTED") 프리필터 → 592.3±94.5 (n=23)
# L/H층: .regime=="L"|"H" 프리필터 → L 644.6±26.3 (n=16) / H 473.0±84.5 (n=7)
```

## 5. 현행 변경(toolchain-handoff)의 효과 판정 — 3단 사전고정

| 단 | 판정 내용 | 조건 |
|---|---|---|
| **1. 구현 성공** | 신경로 기계 서명 관측 | producer에 `[build] Compile derived-closure deriver from B` + `[build] Fetch pinned jq 1.7.1` 스텝 ∧ 7멤버 매니페스트 ∧ verdict leg에 `setup-axiom-toolchain` 부재 + `[check] Provision pinned jq` + `[check] Install libpcre3` 스텝(경계 레코드 `capture` 절 그대로). 스모크 런에서 이미 관측 — 단, 이는 **전환 검증**이며 어떤 성능 주장도 아니다. |
| **2. 초기 성능 신호** | N≥5 도달 시점의 서술 비교 | R1 단일 패스 측정값을 보고한다 — **신호일 뿐**, "개선" 주장 불가. Tier 3 불충족 시 이 단에 머문다. |
| **3. 성능 개선 입증** | 사전 지정 비교 통과 | 아래 (a) ∧ (b) **모두** 충족 시에만 "개선 입증". |

### 5.1 사전 지정 비교 (Tier 3 — 측정 채널 고정)

- **(a) verdict-leg provision+handoff 스텝 총합**: before = 구 `setup-axiom-toolchain` 스텝 총합 **64.7±12.9 s**(25/25 런 등록치) / after = 대체 handoff 스텝들의 visible 총합. 런 성분 비교는 `--compare` 산출(같은 원기록 소비)로, 스텝 채널은 하니스 snet 모드로 산출한다:
  `tools/ci/merge_latency_audit.sh --snet --baseline data/merge_latency/baseline_2026-10-11.runs.jsonl --after data/merge_latency/confirm_2026-10-12_R1.runs.jsonl --baseline-provision 64.7 --producer-steps '^setup-axiom-toolchain' --consumer-steps 'Provision pinned jq|Install libpcre3' --out data/merge_latency/confirm_2026-10-12_R1`
  **판정**: 절감(before − after)이 `max(1, 1.5 × max(sd_base, sd_after))` = 현재 **19.4 s** 초과 → 통과.
- **(b) 게이트 wall-clock**: `--compare`의 `wall_s [operational, ALL]`·`wall_s [EXECUTED only]` 행과 `delta_L`·`delta_H`를 소비한다. **판정**: (i) `delta_L < 0` **AND** `delta_H < 0`(양층 감소), **또는** (ii) 풀링 감소 < 0 ∧ **레짐믹스 보정** — 층 평균에 양 코호트 공통 가중 `w_L=2/3, w_H=1/3`(A2.3.2의 사전등록 가중 — 본 문서가 새로 정하는 것이 아님)을 적용한 가중 차가 음. 어느 한 층이 한쪽 코호트에서 공백이면 그 층은 판정 불가 → (ii) 경로만 가능하고 주장은 **관측 층으로 제한**(E3 §5.2 공층 규칙 준용).
- **Tier 3 = (a) ∧ (b)**. 하나라도 미충족이면 Tier 2(신호)에 머무르며 "개선 입증" 주장은 금지된다.

## 6. 동률·UNKNOWN — fail-closed

- **동률**(§3.5): 상위 두 성분 점유율 차 < 1.0 pp → **변경 없음**, 현 목표 집합 유지.
- **UNKNOWN**: 라운드 R1 수집 중 **하나라도** `classification=UNKNOWN_LOG` 또는 `regime=unknown` 런이 관측되면 **라운드는 즉시 중단**되고 해당 런은 N에 가산되지 않는다. 중단된 라운드는 목표 선정도 효과 판정도 **수행하지 않으며**, 재개는 **새 날짜의 사전등록 문서**로만 한다. 하니스 하드페일(exit 1 — 구조적 API 실패·비게이트 런 혼입)도 동일하게 라운드 중단이다. (A2.2.7 fail-closed 정신의 라운드 단위 적용 — 불명 런을 조용히 버리거나 억측으로 채우지 않는다.)
- 중단 없이 N=5에 도달한 라운드만이 §3·§5 판정을 수행한다.

## 7. PR #754 등록 링크 (저장소 SSOT)

PR #754 — *ci(admission): GO-critical 4레인 병렬화 — A/B 실증 + 착지 유보 (P3)* — 의 등록은 GitHub PR 본문에만 존재했으나, **본 절을 저장소 SSOT 링크로 한다**:

- **착지 트리거**: E3 **단일 확증 분석 추출** — `docs/evidence/e3_measurement_contract_2026-10-11.md` §5.6의 단일 분석(정상 종료 = 고정 n 도달, 또는 (b) 창 닫힘 종료; 창 한계 `2026-11-10T02:52:14Z`). 단일 추출 완료 전 병합 금지(2중 처처 방지 — 병렬화 착지는 E3 확증 C-arm을 오염시킨다).
- **δ 결속 게이트**: `docs/evidence/e3_amendment_a2_2026-10-11.md` **§A2.2** 전체 — δ ≤ 55 s 결정적 채택, (55, 65] 밴드 → A2.2.3 웜 2회 반복, > 65 s 미채택; 전면보류 H > 126.4 s·L > 239.0 s; 노출 창 T_exp=24 h/K_exp=10(A2.2.5); 카덴스 7일 rolling < 2.2 연속 2일 보류(A2.2.6).
- 본 문서 시점의 기계 상태: PR #754 = **CLOSED(미병합)**, 트리거 대기. 상태 갱신은 이력 문서가 아니라 GitHub이 권위다(§2.3).

## 8. 착지 선행 증거 — 본 문서 병합 시점의 확증 런 원장

본 문서는 **확증 N≥5 수집이 완료되기 전에** 고정된다. 관측 시점 `2026-10-12T02:56:44Z`(GitHub API) 기준:

| post-smoke 런 (started > 01:54:47Z) | 큐 키 | 종결 | N 기여 |
|---|---|---|---|
| 38194556640 (02:07:27Z) | pr-766-e8cde1652 | failure | 미분류(수집중) — 0 |
| 38195558280 (02:22:55Z) | pr-767-e8cde1652 | success | 미분류(수집중) — 0 |
| 38196395802 (02:35:42Z) | pr-766-6ed4a6911 | failure | 미분류(수집중) — 0 |
| 38197725016 (02:55:46Z) | pr-766-6ed4a6911 | success | **dependent_repeat** — 0 |

즉 착지 시점까지 post-smoke 런 4건 생성(완결 3 + 진행 1), **EXECUTED 분류 0건 — N=0/5**. 분류는 라운드 종료 시점의 하니스 단일 패스로만 수행되므로(§2.5), 본 규칙 고정은 확증 표본의 분류·측정 **이전**에 확정된다. 병합 시점에 새 런이 더 종결되었더라도 그것은 관측의 누적일 뿐이며 규칙을 바꾸지 않는다.

## 9. 검증 가능성

- 측정·비교: §2.6 명령 그대로(하니스 GET-only, 재현 가능). go-live 경계: `tools/ci/golive_detect.sh` 재실행.
- 스모크 런 verdict 39 s: `gh api repos/Archright/Axiom/actions/runs/38193723834/jobs` — `verdict / admission-check` 01:59:56→02:00:35Z.
- 본 문서는 코드·워크플로·게이트를 변경하지 않는다(관측·규칙 등록만). 어떤 판정 권위도 이동·추가하지 않는다.
