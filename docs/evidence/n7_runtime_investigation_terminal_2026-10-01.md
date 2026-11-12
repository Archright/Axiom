# N+7 runtime 조사 terminal — "N+7 유지 — 조사 terminal 확정 (회귀 불필요)" (2026-10-01 UTC)

- **판정**: **N+7 유지 — 조사 terminal 확정 (회귀 불필요)** — 사용자 확정 결정 2026-10-01.
- **문서 성격**: N+6→N+7 CI runtime 조사의 terminal 기록. 실측 수치만 기재(런 ID·job 로그 원문·PR/commit id로 재구성 가능). 더 이상의 조사·수정 없음 — 이 파일로 조사 종결.
- **측정 규범**: 완료된 런만 REST 원문(`run_started_at`/`updated_at`/잇달아 job `started_at`·`completed_at`) + job 로그 원문 인용. 시간대 전부 UTC. 본 저장소 런은 `gh api repos/Archright/Axiom/actions/runs/<id>`로 재현 가능.
- **관련 병행 기록**: [sl0713_promotion_acceptance_2026-10-01.md](sl0713_promotion_acceptance_2026-10-01.md), [sl0713_promotion_binding_2026-10-01.md](sl0713_promotion_binding_2026-10-01.md), [ci_identity_acceptance_2026-10-01.md](ci_identity_acceptance_2026-10-01.md).

## ① Part A — 런 wall-clock 실측 (N+6 vs N+7)

`admission-gate` 런의 `run_started_at → updated_at` 구간 (전부 success, 단 36865812852):

| 런 | 이벤트 | 역할 / head | 구간(UTC) | 소요 | 비고 |
|---|---|---|---|---|---|
| 36843080711 | merge_group | N+6 acceptance (head af92be0e52) | 09:29:35 → 09:38:09 | **8m34s** | N+6 최대 |
| 36860372830 | merge_group | N+6 acceptance (head 1be4e4654c) | 12:13:49 → 12:20:32 | **6m43s** | N+6 최소 |
| 36862460241 | merge_group | N+7 (head 9c4164bb0f = #425 merge) | 12:32:38 → 12:40:41 | **8m03s** | N+7 최초 |
| 36866697276 | pull_request | N+7 #426 PR 재런 (head 84edcb98b4) | 13:10:00 → 13:16:34 | **6m34s** | N+7 최소 |
| 36867758299 | merge_group | N+7 #426 MG (head a577fda364) | 13:18:45 → 13:27:17 | **8m32s** | N+7 최대 |
| 36865812852 | pull_request | N+7 #426 PR 1차 (head 84edcb98b4) | 13:01:54 → 13:09:15 | 7m21s | **failure — 503 (Part B-①)** |
| 36866190021 | pull_request | v44 #427 PR (head 8eca9428c5) | created 13:05:18 → 13:28:50 | 대기+6m38s | **러너 큐 대기 16m54s (Part B-③)** |

- **N+6 acceptance 대역: 6.7~8.6m** (6m43s ~ 8m34s).
- **N+7 admission-gate 대역: 6m34s~8m32s (run 구간 실측; 사용자 확정 기록 6m34s~8m34s — 동일 대역)** — N+6 대역과 동일, **변화 없음**.
- 런 수준 wall은 admission/boundary job이 지배(아래 Part C 참조) — mint-publish 신규 발화는 대역에 영향 없음.

## ② Part B — "20분" 보고 실체 분해 (3개 성분, 전부 개별 실측)

기존 보고에서 "N+7이 20분"으로 읽힌 wall은 단일 런이 아니라 다음 3개 성분의 합산 인상이다:

1. **1차 런 503 (7m21s 손실)** — run 36865812852, mint-publish/publish job 110383334118 로그 원문:
   `curl: (22) The requested URL returned error: 503` (13:09:04Z) → `MINT_PUB_BIND: FAIL — admission artifact zip download failed (fail-closed)`.
   실패 지점 = certificate-mint.yml **(P4) [X]3 field binding 스텝의 admission artifact zip 다운로드** (`|| fail "admission artifact zip download failed"`, blob 9c4164bb0f 기준 **:1230**). GitHub 일시 503 — 재시도/분류 정책 미정의 (**DEBT#474**).
2. **org callee pin 회전 대기창** — N+7 승격(#425, 12:41:05Z) 후 org `admission-gate.yml`의 certificate-mint callee pin이 회전되기 전까지 #426은 fail-closed: org PR #40 `chore(ci): rotate certificate-mint callee pin to N+7 (9c4164bb) — SL-0713 promotion acceptance unblock` (merged=true; org API mergedAt 미노출) — 해소 13:09:40Z (직후 재런 36866697276이 13:10:00에 시작). pin 회전 절차가 epoch 승격과 같은 논리 단위로 결속되지 않으면 acceptance 차단 창 발생 (**DEBT#473**).
3. **v44 런 러너 큐 대기 17m** — run 36866190021 (#427 PR, head 8eca9428c5): `created_at` 13:05:18Z → 최초 job `started_at` 13:22:12Z = **16m54s 큐 대기 ≈ 17m**, 이후 wall 6m38s (job 합계 기록 6m31s) — 신규 어뷰저블 러너의 큐 지연(실행 자체 소요 아님).

→ 성분 ①+②+③의 합이 "20분" 보고의 실체이며, admission-gate 런 자체 소요는 Part A 대역 그대로.

## ③ Part C — N+7 신규 실행: mint-publish P0/P5/P6/P7 (SL-0713) 발화

- N+6 epoch까지 SL-0713 소관 스텝(P0/P5/P6/P7)은 `NO-FIRE`(미발화)였고, N+7 승격(#425, `feat(epoch): SL-0713 epoch N+7 승격 — certificate continuity publish (D6 exactly-once + [B2]) implemented — NO_CERT 해소`)으로 **발화 전환**.
- 실측: run 36866697276 mint-publish/publish job(110386337498) 로그에서 신규 스텝 전부 OK —
  `MINT_PUB_A0`(13:16:19.06Z) → `MINT_PUB_ART`·`DIGEST`·`AX`·`BIND`·`TREE`·`JOBS` → `MINT_PUB: OK — ledger append (first issuance, append 1)`(13:16:25.65Z) — **로그 구간 ≈6s** (B=9c4164bb0f32… H=84edcb98b44d… run_id=36866697276 pr=426 cert_sha256=f104582d… append 1).
- `MINT_PUB_JOBS: OK — gateway lane (6 jobs, skipped 5 [SL-09 notYet-implemented lane jobs (scope_sl09 if:false)])` — skipped 5건은 SL-09 notYet 귀속.
- **critical path 기여 0**: 런 wall을 지배하는 구간은 admission(G2a 원자 페어·cert mint 준비)·gateway lane(~분 단위)이며, mint-publish 발화(초 단위)는 지연에 영향 없음.

## ④ Part D — authority plane 변경 4건 / execution DAG 무변경

N+6 acceptance(#420~#424 구간) 이후 N+7 admission-gate까지의 변경(전부 기록용):

| # | 변경 | 대상 | 랜딩 |
|---|---|---|---|
| 1 | implementedSlices + SL-0713 | `config/policy/epoch_manifest.json` | #425 (9c4164bb0f, 12:41:05Z) |
| 2 | catalog (slice 등록) | `src/gate/slice_catalog.nim` | #425 |
| 3 | (P6) 조건식 — mode=none reconciliation | `.github/workflows/certificate-mint.yml` (+60줄) | #425 |
| 4 | org callee pin 회전 | org `admission-gate.yml` certificate-mint callee pin → 9c4164bb0f | org PR #40 (13:09:40Z 해소) |

명시적 선행: #424 `chore(policy): surface v43 — SL-0713 승격 evidence 표면 선등록(2단계 선등록)` (merge 12:20:58Z), #427 `chore(surface): v44` (merge 13:37:44Z), #428 `v45` (merge 14:01:13Z).

- **execution DAG 무변경**: job 토폴로지·job 수(admission 2 / gateway lane 6~7 / mint-prepare 2 / mint-publish 2 + admission-check)는 N+6과 동일. mint-publish 스텝은 기존 스텝의 발화 조건(scope) 변화일 뿐 실행 경계 추가/삭제 없음.

## ⑤ 회귀 조건 판정 (조사 정의 R1~R6)

- 조사에서 정의한 회귀 조건 R1~R6 중 **R3·R4 불성립** 확인(위 Part A~D 실측에 근거).
- **R3·R4 불성립 → 회귀 불필요 → N+7 유지** (사용자 확정 2026-10-01). 회귀 수행 안 함.

## ⑥ follow-up debt 3건 등재 (follow-up only — 본 조사에서 해소/수정하지 않음)

| DEBT | 항목 | 핵심 실측 근거 |
|---|---|---|
| **DEBT#472** | P6 skip-set identity 미검증 — SL-09 승격 시 재점검 | certificate-mint.yml:1381-1417 @9c4164bb — skipped lane **사유 존재**(SL-09 notYet / mode=none envelope)만 검증, skip 집합 identity(구성·n_skip) 미검증 — mode=none(5 skipped)과 normal(4 skipped) 구분 불가. 관측: `MINT_PUB_JOBS: … skipped 5 [SL-09 notYet]` (36866697276) |
| **DEBT#473** | org callee pin synchronization 절차 미정의 | org PR #40까지 #426 fail-closed (36865812852 실패 이후 36866697276 성공 전 13:09:40Z 해소) — epoch 승격과 pin 회전이 분리 랜딩 → acceptance 차단 창 |
| **DEBT#474** | 503 retry policy 미정의 — mint P4 artifact 다운로드 transient fail-closed 재시도 정책 | run 36865812852: `curl: (22) … 503` → `MINT_PUB_BIND: FAIL — admission artifact zip download failed` (job 110383334118, 13:09:04Z; certificate-mint.yml:1230 @9c4164bb) — 7m21s 손실 |

## ⑦ 관련 run / PR id 색인 (재구성 가능)

- **런(본 저장소)**: 36843080711 · 36860372830 · 36862460241 · 36866697276 · 36867758299 · 36865812852 · 36866190021 (v44, 36866189171/36866189145 동일 브랜치 선행 런) · job 110386337498(36866697276 mint-publish) · job 110383334118(36865812852 mint-publish)
- **PR(본 저장소)**: #425 (N+7 승격, merge 9c4164bb0f32f7b6) · #426 (C11 acceptance, merge a577fda364, 13:27:40Z) · #424 (v43 선등록, merge 1be4e4654c) · #427 (v44, merge 13:37:44Z) · #428 (v45, merge fc15b99705e24, 14:01:13Z)
- **org(Archright/.github)**: PR #40 `chore(ci): rotate certificate-mint callee pin to N+7 (9c4164bb) — SL-0713 promotion acceptance unblock` (merged=true; org API mergedAt 미노출 — 해소 시각 13:09:40Z는 재런 시작 13:10:00Z와 정합)
- **커밋**: 9c4164bb0 (N+7 승격 merge), beedff6ec (#425 구성 커밋 — "feat(epoch): N+7 promotion — SL-0713 … (P6) mode=none reconciliation …")

## ⑧ UNKNOWN / 잔여

1. org admission-gate.yml의 repository-surface 미노출 항목(org 권한 스코프, token 404 선례 — org 표면은 조사 관측 원문만) — DEBT#473에서 절차 정의 소관.
2. 모드=none(5 skipped)·normal(4 skipped) skip 집합의 정본 정의 — SL-09 승격 시 재점검(DEBT#472).
3. 러너 큐 대기 16m54s의 큐 정책(어뷰저블 풀) 원인 — v44 런 일회성 관측, 재발 시 별도 추적(본 조사 스코프 밖).
4. 503 재시도가 있었다면의 성공 경로 — 미실측(DEBT#474 해소 시 실증 대기).