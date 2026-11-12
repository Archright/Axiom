# Pre-registration — v5 판정 CAS 재사용 효과 측정 절차 등록 (2026-10-31)

> **Status**: PROCEDURE-REGISTERED — 측정 **절차** 등록. 본 문서는 착지 전에 고정되며 측정 개시 후
> 편집하지 않는다(관측 결과는 최종 기록 PR — §8 — 에만 실린다).
> **등록 계층(정직 구조)**: 본 측정의 1차 판정 규칙은 **이미 사전등록되어 있다** — 2026-10-18 재결 §4
> (동결 공식: 3-metric, docs-only 표본 중앙값 n≥5, before-baseline #925, "401s는 등록된
> 달성가능성 상한이지 보증 아님", 측정=Reporter 원칙)가 모든 v5 표본(2026-10-21~)보다 먼저 착지했다.
> 본 문서가 신규로 등록하는 것은 그 **실행 절차**(표본 단위·분류 ground truth·provider-epoch 층화·
> 판독 어휘·P95 절차·증거 위생)다.
> **사전 관측 공개 의무**: 본 등록 시점에 본 세션이 이미 관측한 값은 §3.d에 전부 공개한다. 규칙은
> 관측값이 아니라 외부 사실(provider epoch 전환, acceptance의 paired-runs 요구)에서 유도됐다.
> **Date**: 2026-10-31T10:27:25Z · **Branch**: `work/v5-measurement-prereg` · **Scope**: 본 문서
> 1건(`docs/evidence/*.md`) — 코드·워크플로우·게이트·핀 변경 0건.

## §0. 상속·참조 권위 (본 문서는 아래를 대체하지 않는다)

| 권위 | 내용 | 위치 |
|---|---|---|
| 판정 규칙(1차, 동결) | 3-metric(D1 preflight / MG wall / D3)·docs-only 표본 n≥5 중앙값·before-baseline·Reporter | `docs/evidence/mg_reuse_policy_redecision_2026-10-18.md` §4 :180-217 |
| SLO of record | 8분 P95 = policy/SLO("remains the SLO of record") — 헌법 불변식 아님. 후속 최적화는 Owner 명시 승인 필요(본 프로그램: 2026-10-31 세션에서 Owner의 명시적 지시로 승인됨) | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` :133-135 |
| 측정 교란 규칙 | 러너 VM 속도 분산(~1.4-1.5×)은 측정 교란 — wall 비교는 **paired runs and/or multiple runner samples** 필수 | 같은 문서 :152 |
| wall·백분위 방법 | wall = `updated_at − run_started_at`(E3 §7.1, attempt-fresh), 백분위 Hyndman–Fan R-7, post-window 전수 관측(체리피킹 금지), 실패는 실패로 보고 | `docs/evidence/mg_folding_separation_prereg_2026-10-30.md` §8 :160-169 |
| P95 어휘 | 집단별 N≥30 도달 전 p50/p95는 "잠정·미산출" | `docs/evidence/residual_issue_ledger_2026-10-31.md` RESID-09 :136-144 |
| 배제표 N(차량 자격) | 무영향: `.md`(단 docs/spec·docs/agents·config/policy·config/templates·AGENTS.md·docs/DEBT_REGISTRY.md는 배제 금지)·이미지류·`.lock`(nimble.lock 제외) 등. **`data/*.json`은 전부 키 전진 멤버** | `src/verification/semantic_set_derivation.nim` :94-192 · `tests/unit/test_judgment_set_derivation.nim` T7 :463-507 |
| 판정 CAS 계약 | 5조건·fail-closed("조회 실패도 MISS다")·timeout/불완전 판정은 재사용 대상 아님 | `docs/spec/test_judgment_cas_contract.md` §5-§6 |
| 참조 밴드 | v4 관측 401-550s(n=5, #926/#927/#928/#934/#933, GHEC 시대) — v5 표본 진입 비교 참조 | `data/ci_optimization/judgment_key_v4_interim_2026-10-19.json` |

## §1. v5 수용 프로토콜 A/B/C/D — 상태 귀속 기록 (관측 완결)

`docs/evidence/v5_generation_acceptance_a_2026-10-21.md`는 프로토콜 정의·사전등록 문서로 상태 표기란이
없다(git log --follow: 커밋 1건, 2026-10-21 이후 무갱신). 완료는 별도 차량 PR·런에 존재하며 본 문서가
귀속을 최초로 집중 정리한다. 모든 마커는 라이브 런 로그에서 직접 인출된 원문이다.

| 수용 | 차량 | 관측 근거 | 판정 |
|---|---|---|---|
| A(신세대 v5 증거) | PR #1014 (2026-10-21 13:02Z MERGED) | v5 기록 발화(evidenceKey `148a4fac…`) | 완료(종전 인식 그대로) |
| **B(동일 closure REUSED)** | **PR #1020 "B2"** (16:40:44Z MERGED, merge commit `40be184e4`) | MG 런 `39635671834`(admission-gate, merge_group, success, 16:32:24Z→16:40:29Z, **wall 485s**): 4주체 `AXIOM_JUDGMENT_CAS: REUSED — record 644f058cb5db / b489f86ad4a5 / c75da17e5463 / a5218bdbaad9 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)` + `SKIP … basis=REUSED` + `[go-exec] exec record[*] OK — verdict=UNKNOWN basis=REUSED decision=REUSED` | **완료** |
| **C(변경 closure 거부)** | **PR #1021** (17:14:52Z MERGED, merge commit `e75f005c7`) — `tests/unit/test_s1a_lean_golden.nim` 주석 7행(①/⑤ 클로저 멤버 변경) | MG 런 `39639158902`(success, 16:55:38Z→17:14:29Z, **wall 1131s**): `AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)` + `PASS — tests/unit/test_s1a_lean_golden.nim (basis=EXECUTED — fresh judgment measured)` + `exec-record[s1a] verdict=PASS basis=EXECUTED evidenceKey=725502de3d91` — 선행 기록(`644f058cb5db`) 미재사용 관측 | **완료** |
| D(v4 세대 거부) | 기계+운영 — v5 키 스킴(`axiom.judgment.cas.key.v5`) 하 v4 기록은 구조적으로 미매칭, 운영 귀속은 A 착지가 증명 | 종전 기록(v5_generation_acceptance_a 프로토콜 정의) | 완료(종전 인식 그대로) |

**정직 부정 관측(기존 문서화 없음 — 본 문서가 최초 정리)**: 최초 B 차량 **PR #1016**
("docs(evidence): v5 acceptance B — same-closure REUSED", 13:57:06Z MERGED, merge commit `011c5127d`)은
사전등록 기대(REUSED) 미충족 — **EXECUTED 착지**였다. 원인: A(#1014)와 B(#1016) 사이에 semantic PR
#1015(`tools/merge_ruleset_drift_monitor.nim` 등)이 착지해 클로저가 전진했고 #1016의 클로저에는 기록이
없었다. 이는 계약상 **정상 fail-closed**다(무레코드 → 원 실행 — C와 동일 메커니즘). 이어 #1017 착지
실패(런 39613168689, lane1 stale guard)를 수습한 **PR #1019**(16:08:11Z, "fix(admission): v5 lane
outcome semantics — verified-REUSED is admissible for every subject", v5.1)이 4주체 신기록
(`644f058cb5db` 등)을 발화했고 B2(#1020)가 그 세대를 재사용해 형식 완결했다. 이 경과는 기존
evidence 문서 어디에도 집중 정리돼 있지 않았다(PR 본문·런 로그에 분산).

**귀속의 효과(범위 축소)**: 승인된 계획의 Phase 1(B/C 차량 PR 신규 실행)은 **불요**로 축소된다 —
이미 관측 완결된 수용을 중복 실행하지 않는다. 본 슬라이스의 남은 미완결은 §2 이하의 측정·판정뿐이다.

## §2. 표본 집합 정의

- **모집단**: v5 세대(2026-10-21 착지 이후) main 착지 중 **N-제외 docs-only PR 착지** — 변경 파일
  전부가 배제표 N에 매칭(실무상 `docs/**/*.md` 단, `docs/spec/`·`docs/agents/`·정확 경로 3종 제외).
- **표본 단위**: PR 착지 1건 = **최종 병합된 admission-gate merge_group 런**. 동일 PR의 재도크·
  dequeue 중간 런은 표본에서 제외하고 경계 관측으로 별도 기록한다(증거 격리 §5 — 선례: #1144의
  03:40Z·07:21Z 런은 착지 런 08:27Z와 분리).
- **분류 ground truth**: GO 레인 잡 로그의 4주체 basis 마커(s1a·proof_integrity·d2_golden·d2_persist
  각각 REUSED/EXECUTED). 파일 분류(N-제외 여부)는 교차확인이다. basis는 로그 수준에서만 확정한다
  (역추적 보간 금지 — v4 interim confirmationPath 관례).
- **역사 창**: 2026-10-21T16:40:44Z(B2 병합 — v5.1 semantics에서 최초 all-REUSED green 착지) ~
  본 문서 착지 시점. **신규 표본 사전선언**: 본 문서의 착지 런(§8) 및 이후 N-제외 docs-only 착지 전수.
- **semantic EXECUTED 대조군**: 같은 창의 semantic 착지(클로저 전진 → EXECUTED)는 효과 표본이
  아니며 분리 보고한다(재결 §4: "실행-축 전진 PR은 표본에서 분리 보고 — 정상").
- **red·비착지 런**: 실패·dequeue 런은 실패로 그대로 보고하고 표본에서 제외한다(v4 interim
  observations.red·nonLandingFailureRuns 관례).

## §3. Provider-epoch 층화 (측정 비교 가능성 — 2차 비판 ② 수용)

**a. 교란 사실**: before-baseline #925 717s(런 39132586441, 2026-10-18, 13:40:35Z→13:52:32Z,
`docs/evidence/mg_reuse_cutover_e2e_2026-10-18.md` :70-84)는 **GHEC hosted 시대** 값이다. v5 표본
창은 provider 세대를 가로지른다: GHEC(~2026-10-23) → failover 과도기(10-23 ~ 10-30T07:46:09Z) →
**gen-12 Ubicloud**(10-30T07:46:09Z~, `docs/evidence/ci_provider_epoch_2026-10-30.md` :30-38) →
GHEC 시험창 가능(2026-11-01~03, RESID-13 :180-188).

**b. 층화 규칙**: 표본마다 런 `created_at` 기준 epoch 태그를 기록한다: `ghec`(≤2026-10-23)·
`failover`(10-23~10-30T07:46Z)·`gen12`(이후)·`ghec-trial`(11-01~03 — 실제 발생 시). 중앙값은
(i) 전체 표본 (ii) epoch 층별 로 각각 산출·보고한다. 러너 레짐 L/H 문법
(`merge_latency_decision_prereg_2026-10-13.md` §5.2, a-restore 40s 이봉)은 GHEC 시대 정립이므로
gen-12 적용 여부는 미가정으로 둔다 — a-restore 마커가 관측되는 표본만 부가 기록한다.

**c. 교란 통제 추정(2차 보고)**: 동일 epoch 내 **EXECUTED vs REUSED 대조**(예: gen-12 #1128
semantic EXECUTED 974s vs REUSED 표본들; ghec #1021 C 1131s vs B2 485s)를 별도 보고한다 —
acceptance :152 "paired runs and/or multiple runner samples"의 구현. 이 대조는 confound-controlled
추정치일 뿐 1차 판정 규칙(재결 §4)을 대체하지 않는다.

**d. 사전 관측 공개(본 등록 전 본 세션 관측분 — 전부)**:
- ghec: B2 #1020 REUSED wall 485s(§1) · C #1021 EXECUTED wall 1131s(§1) · #1016 EXECUTED(wall 미인출)
- gen12: #1128(semantic, cache-carrier 분리) EXECUTED wall 974s · #1144(docs-only) REUSED 런 3건
  wall 825/579/699s — 표본 규칙상 최종 착지 런 699s만 표본, 재도크 2건(825/579s)은 경계 관측.
  재사용 레코드 `7fe9623ad931`(mint 귀속: #1128 착지 런, 원장 커밋 `e54016ab3`).

규칙(§3.b·c)은 이 값들이 아니라 epoch 전환 사실(`ci_provider_epoch_2026-10-30.md`)과 acceptance
:152 요구에서 유도됐다. 본 문서 착지 이후 수집되는 전수 표본은 등록 후 관측으로 기록된다.

## §4. 판정 규칙·어휘 (상속 + 판독 고정)

- **1차 판정(재결 §4 동결 — 권위는 10-18 재결)**: docs-only REUSED 표본 MG wall **중앙값**이
  before-baseline 717s 대비 유의한 감소 → 정책 효과 **확정**; 감소 없으면 **효과 없음 보고**(정책
  유지 여부는 별도 재결). 기준 표본 수: n≥5 PR 착지.
- **wall 정의(병행 기록)**: 1차 = `updated_at − created_at`(재결 §4 정의 "merge_group 런
  created→updated"); 병행 = `updated_at − run_started_at`(mg prereg §8 정의). 두 정의의 차가
  유의한지 최종 기록에 공개한다.
- **"유의한 감소" 판독(본 등록에서 고정)**: 중앙값 감소분이 관측 표본 분산(bootstrap 웜/콜드
  ±100-200s, post_a_d3 §6; 러너 단편 ~1.4-1.5×, acceptance:152)을 초과하는 폭이면 감소로 판독하고,
  판정 문에 근거(분산 관측치)를 명시한다.
- **어휘**: 중앙값은 **효과 추정치**다 — 모든 PR에서 동일 단축의 증명이 아니다(2차 비판 ② 수용).
  표본 수·측정 구간·분포(최소·최대·중앙값)를 수치와 함께 보고한다. semantic 착지는 분리 보고하며
  "모든 착지 단축"으로 일반화하지 않는다.
- **맥락 기록(표본당)**: PR#·런 ID·created/run_started/updated·wall(두 정의)·conclusion·4주체
  basis·epoch 태그·재도크 플래그·D3(PR `created_at`→`merged_at`)·D1(PR `created_at`→첫
  required-green; check-runs API 산출 가능 시). 산출 불가 시 이유를 기록한다.
- **Reporter 원칙**: 본 측정은 Reporter다(재결 §8-3) — 판정 권위가 아니며 어떤 게이트·required
  check·병합 권한에도 영향을 주지 않는다.

## §5. 증거 위생 (2차 비판 ① 수용 — 관측 단위 격리)

- 각 관측은 **PR 번호 + Actions run ID + 잡 ID**로 귀속하고, 마커는 ANSI 제거 원문 그대로
  인용한다(`gh api --allow-escape-sequences` + sed — `docs/spec/gh_run_observation_quirks.md` Q3).
- B(#1020/런 39635671834)·C(#1021/런 39639158902)·#1016·측정 표본의 로그·판정을 서로 섞지 않는다 —
  최종 기록 JSON의 `landings[]` 항목별 분리(v4 interim 스키마 계승).
- 관측은 전부 GET-only. 재현 명령을 §8에 등재한다.

## §6. P95 절차 (2차 비판 ③ 수용 — 통계적 한계 명시)

- P95는 **N≥30 도달 전까지 미산출**이다(RESID-09 어휘 "잠정·미산출"). 도달 시: live-window 전수
  관측(체리피킹 금지), Hyndman–Fan R-7, **표본 수·측정 구간을 수치와 함께** 보고한다.
- **해석 한계(고정)**: n=30은 등록 절차상 계산 가능 최소 표본 수이지 안정적 장기 추정이 아니다 —
  30표본 P95를 장기 성능 보증으로 해석하지 않는다.
- P95 산출 전의 SLO(480s) 위치 보고: 현재 표본 분포(중앙값·최대·참조 밴드)로 "SLO 대비 위치 —
  P95 미산출" 상태를 정직 보고한다. semantic 착지(~700s+)가 p95를 지배할 가능성은 그대로 기록한다
  (임계 조정 금지 — SLO는 policy이며 본 측정은 Reporter다).

## §7. 실패·정직 경로 (fail-honest)

- 전수 관측에서 재사용 오작동·fail-closed 미발화(예: 무레코드인데 REUSED 자칭)가 관측되면 이
  슬라이스는 **결함 보고로 닫힌다** — 수리는 별도 슬라이스(epoch cutover + J1-J4 판정 동반)로
  이관하고 성공 선언 없이 상태만 기록한다.
- 표본이 n<5로 부족하면: **사전선언 차량 PR**(N-제외 docs-only `docs/evidence/*.md` — 본 등록의
  승인된 표본 메커니즘이며 극장이 아님: 목적을 PR 본문에 명시)으로 보충한다. 유기적 착지 관측과
  차량 표본은 구분 표기한다.
- 큐 이탈·런 실패는 실패로 그대로 보고한다. org ruleset SHA-exact 핀 회전이 비행 중 발생하면
  f5eb8c70b 선례(신규 head SHA 재도크)로 회복하고 그 경과를 기록한다.

## §8. 착지 계획·사전선언·재현 명령

- **본 PR 착지 = 신규 표본 사전선언**: 본 PR(`docs/evidence/*.md` 단독, N-제외)의 최종 착지
  admission-gate merge_group 런은 기대 **REUSED** 표본으로 등재된다(직전 착지 #1144가 발화·재사용 중인
  현 세대 레코드 `7fe9623ad931` 계열). 착지 후 본 문서는 편집하지 않는다.
- **최종 기록 PR**(측정 완료 후, 별도 PR): `docs/evidence/judgment_key_v5_adjudication_<date>.md` +
  `data/ci_optimization/judgment_key_v5_adjudication_<date>.json`(v4 interim 스키마 계승:
  `landings[]`·`recordGenerations`·`boundaryCandidates`·`savings`·`frequency`·`reproduction`).
  `data/*.json`은 키 전진 멤버(T7)이므로 그 PR의 착지 basis는 EXECUTED일 것으로 기대하며 — 관측
  그대로 기록한다(기록 PR은 표본이 아니다).
- **재현 명령(GET-only)**:
  - 런 목록: `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" --jq '.workflow_runs[] | select(.name=="admission-gate") | [.id, .head_branch, .created_at, .run_started_at, .updated_at, .conclusion]'`
  - 잡·마커: `gh api "repos/Archright/Axiom/actions/runs/{id}/jobs" --jq '.jobs[] | [.id, .name, .conclusion]'` →
    `gh api --allow-escape-sequences "repos/Archright/Axiom/actions/jobs/{job_id}/logs" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "AXIOM_JUDGMENT_CAS|basis=|no record|go-exec|MINT_JUDGAPPEND"`
  - PR 메타: `gh api repos/Archright/Axiom/pulls/{N} --jq '[.created_at, .merged_at, .merge_commit_sha]'`
