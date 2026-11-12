# G2 S3 재판정 (post-Lever-B) — 동결 기준 그대로 (2026-10-17)

> **종류**: 측정·판정 기록. `go_matrix_s3_performance_verdict_2026-10-16.md`의 후속 — 동일 동결 공식·기준, 기준 재조정 없음.
> **창**: `created_at ≥ 2026-10-16T08:23:16Z`(가드 수정 착지 — `g1_s3_publisher_verification_2026-10-17.md` §1 사실 정정)부터 수집 시각까지 관측된 **n=7** (첫 2런은 구가드 창에 포함되나 전부 success·D4에 이상 없어 표본 유지, 민감도 병기).
> **권위**: API 초 해상도(±1s). 기계 판독: `data/merge_latency/g2matrix_post_leverb_readjud_2026-10-17.json`.

## 1. 표 (7런·7 PR 1:1, 초)

| MG run | PR | 종류 | D3 | lane-0 GO | lane-1 GO | setup 0/1 | D4-comp | wall |
|---|---|---|---:|---:|---:|---|---:|---:|
| 38867729895 | #880 | docs+config | 1589 | 334.5 | 242.2 | 44/51 | 385.5 | 947 |
| 38871419937 | #881 | code(ci) | 1389 | 330.5 | 245.9 | 52/53 | 383.5 | 1019 |
| 38874492382 | #882 | docs | 1377 | 333.5 | 136.5 | 49/67 | 400.5 | 1000 |
| 38885317769 | #883 | code | 1396 | 261.8 | 229.5 | 88/50 | 349.8 | 752 |
| 38885912015 | #884 | docs | 1346 | 332.8 | 246.7 | 48/43 | 380.8 | 902 |
| 38891209338 | #885 | code | 1292 | 260.4 | 241.2 | 79/51 | 339.4 | 716 |
| 38913175446 | #886 | docs+data | 1564 | 334.5 | 242.6 | 46/45 | 380.5 | 951 |

## 2. 3축 판정 (동결 문언 그대로)

| 축 | 기준 | 관측 | 판정 |
|---|---|---|---|
| (a) D4-composite 중앙값 | ≤ 400s | **380.8s** (P95-R7 396.0, 범위 339.4–400.5) | **PASS** |
| (b) D3 중앙값 | ≤ 1256s | **1389.0s** (기준선 1556 대비 −167s) | **FAIL** |
| (c) 레인 귀인 admission red | 0 | **0** (7/7 success, 레인 잡 실패 0) | **PASS** |

**실패 양상의 질적 변화**: publisher 사망 창(S3)에서 D3 중앙값은 기준선 대비 **+171s 악화**(1727s)였으나, 부활 후 **−167s 개선**(1389s; S3 창 대비 −338s). ≥300s 요구에는 미달 — **잔여 갭의 위치는 D1 preflight·큐 대기 구간** (D3 = PR 생성→머지 전체이며 GO/D4는 이미 목표 내). 세대 유지 결정(S3 §6.3)의 전제가 유지되는 방향.

## 3. 정직 한계

n=7(R-7 P95는 최상위 2값 보간 — 단독 판정 금지) · 4/7 docs-PR 혼입(코드 전용 민감도 n=3도 중앙값 동일 1389s) · D3 미분해(D1/큐 성분) · #880은 Lever-B cutover 기록 PR 자신 · 트래픽 희소(#885–#886 간 2.7h 공백).

## 4. 하니스 갭 (별도 차량 필요 — 본 기록에서 수정하지 않음)

`tools/ci/merge_latency_audit.sh`가 org 게이트 개명(`admission-gate.yml` → `admission-gate-v2.yml`, PR #881) 이후 런에 대해 워크플로 경로 가드에서 fail-closed 거부 — 본 표는 S3 §2(3)과 동일한 승인 1차 채널(레인 로그 `duration_ms` + jobs API steps[])로 산출했다.

> **해소 기록 (2026-10-17)**: Gap A(경로 가드)는 `harness_v2_gate_recognition_2026-10-17.md`에서 해소 — 4개 가드 사이트를 allowlist `^(.*/)?admission-gate(-v2)?[.]yml$`로 전환(§2.5 비례 차량: 본 기록 참조), 동일 창(10-16 09:00Z..24:00Z) 스캔이 0건 → **6건 복원**, 음성 대조(landing-integrity 런 38977368334)는 계속 HARD-FAIL. Gap B(레인 소싱 — `go_step=null`·`UNKNOWN_LOG`)는 prereg §10 Q2 승인 차량으로 별도 설계 대기. 검증 산출물: `data/merge_latency/harness_v2_validation_2026-10-17.{runs.jsonl,summary.json}`.

## 5. 재현

```bash
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" --jq '.workflow_runs[] | select(.name|test("admission-gate")) | [.id,.conclusion,.created_at,.updated_at,.head_sha]'
gh api --allow-escape-sequences /repos/Archright/Axiom/actions/jobs/<LANE_JOB_ID>/logs | grep -E "\[admission-tests\] LANE .* duration_ms="
gh pr list -R Archright/Axiom --state merged --json number,createdAt,mergedAt,mergeCommit --limit 30
```
