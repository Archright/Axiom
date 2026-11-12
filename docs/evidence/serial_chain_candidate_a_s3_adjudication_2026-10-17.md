# Candidate A S3 판정 — publish∥verdict 신세대 ≥5-run 동결 게이트 채택 기록 (2026-10-17)

> **종류**: 실행 증거 (사전등록 판정 기록, S3 adjudication record) — 사전등록 [serial_chain_dag_prereg_2026-10-17.md](serial_chain_dag_prereg_2026-10-17.md)(PR #889) §5의 판정 게이트(관측 전 고정 — 사후 조정 금지)를 후보 A 착지 후 신세대 production merge_group 관측으로 판정한다. 본 문서는 게이트를 재정의·재조정하지 않는다(동결 문자 준수 — frozen letter, no retuning). 승격 사실 기록은 [generation_promotion_hnew_2026-10-17.md](generation_promotion_hnew_2026-10-17.md).
> **권위**: 판정 기준의 권위는 사전등록 §5(등록 시점 고정)에 있다. merge-admission 판정 권위는 GitHub(org ruleset · merge queue · native MERGE 커밋 — Authority ≠ Adapter)이며 본 기록은 Reporter다. 수치는 전부 runs/jobs API GET 관측값이다(§7 재현).
> **판정**: **ADOPTED — 세대 유지 (H_new = `29094836`)**. GO = (i) ∧ (ii) ∧ (iii) 전부 충족 — 병렬 관측 PASS(4/5), post-lane 꼬리 중앙값 절감 **−62 s > 30 s**, 레인 귀인 admission red **0/5**.

---

## 1. 표본 — 신세대 admission-gate merge_group 완결 런 5건

**선정 기준**: H_new 재핀 이후의 완결 신세대 merge_group 런 전수(2026-10-17, 생성 시각순). 양 org ruleset의 H_new 재핀 readback은 2026-10-17T00:35Z이고 첫 신세대 런은 01:28:08Z다 — 5건 전부 신세대 핀 창이다.

| n | run | PR | queue head | created (UTC) | 결론 | publish∥verdict 겹침 | 꼬리 |
|---|---|---|---|---|---|---:|---:|
| 1 | 38990981390 | #892 | pr-892-c9cca265 | 01:28:08 | success | **49 s** | 190 s |
| 2 | 38993632915 | #893 | pr-893-34d7362 | 02:06:50 | success | **43 s** | 284 s |
| 3 | 38993907587 | #894 | pr-894-d2a4a6f | 02:10:58 | success | **40 s** | 217 s |
| 4 | 38997388474 | #895 (1차 시도) | pr-895-90614e7 | 03:04:41 | failure | **40 s** | 229 s |
| 5 | 39000589841 | #895 (재시도) | pr-895-90614e7 | 03:54:51 | success | 0 (순차 — §2) | 300 s |

- **겹침** = min(publish completed, verdict completed) − max(publish started, verdict started) — 음수면 0(비겹침).
- **꼬리** = 마지막 `go-critical-lane` completed → 호출부 롤업 `admission-check`(접두사 없는 필수 체크) completed. 초, API second granularity(±1 s).
- 런 4는 같은 헤드(pr-895-90614e7)의 재시도 런 5로 회수됐다 — §4.

## 2. 게이트 (i) 병렬 관측 — PASS (4/5)

`mint-publish / publish`와 `verdict / admission-check`의 실행 구간이 **4/5 런에서 겹쳤다**(49/43/40/40 s — 사전등록 §5-(i) 구조 성립의 직접 관측). 4런 모두 양 잡 동시 시작~근접 시작으로 publish 종료 전 verdict가 진행 중이었다.

**런 5(39000589841)는 순차로 실현됐다 — DAG-일관**: verdict(04:00:50→04:01:32)는 mint-prepare 종료(04:00:46) 직후 시작했고, publish(04:02:16→04:02:59)는 자신의 **다른** 선행인 gateway ci-bootstrap(03:57:32→04:02:13, 281 s) 대기로 늦어졌다. verdict의 needs(`[mint-prepare, closure-deriver, anchor-resolve]`)는 03:56:38(closure-deriver)·04:00:46(prepare)에 모두 충족됐다. 즉 제거된 엣지의 실현이 이 런에서는 **겹침이 아니라 재배치**(verdict가 publish를 기다리지 않고 gateway 대기 그림자에서 먼저 실행)로 나타났다 — verdict의 실행 위치가 publish에 구속되지 않는다는 needs 변경의 효과 자체는 동일하게 관측되며, 겹침 실현 여부는 선행 잡 타이밍이 결정한다. 반사실(구 직렬 순서 publish→verdict 유지)로는 verdict가 publish 뒤에 재삽입된다(+42 s 잡 + 잡 갭) — 꼬리 ~344 s 대 관측 300 s = **−44 s**로, 겹침 없이도 엣지 제거가 절감을 실현했다.

## 3. 게이트 (ii) post-lane 꼬리 중앙값 절감 — PASS

꼬리 {190, 284, 217, 229, 300} → **중앙값 229 s**. 직렬 세대 기준 중앙값 **291 s**(254–331, n=8 — [d3_gap_decomposition_2026-10-17.md](d3_gap_decomposition_2026-10-17.md), 사전등록 §1 동일 값) 대비 절감 **−62 s > 30 s 문턱**(사전등록 §5-(ii) 등록 시점 고정: n=8 range 77 s → σ̂≈27 s → 중앙값 SE≈15.1 s → 2×SE≈30 s). **PASS.**

정직 노트: 런 5의 꼬리 300 s는 gateway ci-bootstrap 281 s가 꼬리 창과 겹친 케이스다(사전등록 §2의 3-run 창에서는 gateway가 3–7분 먼저 종료해 비구속이었다). 후보 A 외 성분이 꼬리에 가산된 표본이지만 중앙값 판정은 이를 포함해도 문턱(30 s)을 2배 이상 넘는다.

## 4. 게이트 (iii) 레인 귀인 admission red — PASS (0/5)

5런 중 admission red는 1건(런 4, 38997388474). **레인(go-critical-lane) 계통으로 귀인되는 red는 0이다.**

- **실패 지점**: `verdict / admission-check` 스텝 28 **"[check] Admission predicate evaluation (MergeAdmissible verdict → check conclusion)"** — predicate 자체의 부결. 호출부 롤업 `admission-check`은 fail-closed 연쇄로 실패([mg_red_forensics_2026-10-14.md](mg_red_forensics_2026-10-14.md) 어휘로 귀인 기록).
- **귀속: PR #895 자체 콘텐츠** — 착지 판정 증거 게이트 세대의 자기 검증 런이다(merge_group venue 판정재사용 차단·SSOT 서브젝트 집합 동등성·admission-check.yml 세대 전환 + 핀 원자 회전 — [ci_epoch_record_mg_evidence_gate_2026-10-17.md](ci_epoch_record_mg_evidence_gate_2026-10-17.md)). 해당 런에서 publish는 success였고 겹침(40 s)도 정상 관측됐다 — verdict∥publish 변경과 무관.
- **회수**: 1차 큐 시도 red → 동일 헤드 재시도(런 5) green → **MERGED 2026-10-17T04:03:31Z**(native merge 커밋 `338c54150` — 현 main HEAD).

**감시 항목(사전등록 §3) — 원장-폴백 경합**: publish∥verdict가 된 4런에서 verdict predicate는 모두 green으로 도달했다(--cert fetch `continue-on-error`의 원장 폴백 경합 발화 없음). **관측된 red 없음 — 유일 red는 #895 자체 콘텐츠**(상기). fail-closed 가용성 비용의 실현은 0이다.

## 5. 판정 — ADOPTED (세대 유지) · D3 함의(예측치로만) · SLO 미선언

GO = (i) ∧ (ii) ∧ (iii) 충족 → **ADOPTED — 세대 유지**(H_new = `29094836bc4488280d98c22665470dcb2e54da1a`). 사전등록 §5의 FAIL 시 frozen 세대 rollback 조항은 발동하지 않는다.

- **D3 함의 — 예측치로만 기록한다(관측 아님)**: 꼬리 −62 s를 D3 중앙값(n=7 기준 1389 s — `data/ci_optimization/round2_diagnostics_2026-10-17.json`, [go_matrix_s3_readjud_post_leverb_2026-10-17.md](go_matrix_s3_readjud_post_leverb_2026-10-17.md))에 선형 반영하면 **~1327 s** — 1256 s 목표 **미달**. 잔여 갭 ~71 s는 후속 후보 B·D′(사전등록 §6 — 별도 슬라이스, 본 판정으로 승인되지 않음)의 영역이다.
- **SLO 480 s 선언이 아니다** — 사전등록 §5 명시 대로 ≥5회 관측은 **초기 검증 게이트**일 뿐 P95 입증이 아니다(n=5; R-7 P95 단독 판정 금지 관례 — [go_matrix_parallelization_prereg_2026-10-16.md](go_matrix_parallelization_prereg_2026-10-16.md) 보고 규칙). SLO 선언에는 더 큰 표본의 지속 관측이 필요하다 — 별도 과제.

## 6. J1–J4 처분 — vacuous-with-basis

J1 semantic parity · J2 evidence equivalence · J3 cache soundness · J4 worker determinism(`docs/spec/ci_optimization_tcb_judgments.md:17-20`)에 대해: 후보 A는 **callee 핀을 변경하지 않았다**(`admission-check.yml@64f78ab7` · `certificate-mint.yml@9aaee76f0` · `runner-pool@ba773d0631` — [generation_promotion_hnew_2026-10-17.md](generation_promotion_hnew_2026-10-17.md) §3) · verdict = `ax merge --dry-run --json` exit 계약 불변(사전등록 §4-1). 실행-의미론 입력이 불변이므로 **J1–J4는 이 근거와 함께 공허하게(vacuously) 적용**된다 — 전칸은 동 문서 §6.

## 7. 재현 명령

```bash
# §1 표본 — 5런 확인 (신세대 창: 첫 런 2026-10-17T01:28:08Z, 재핀 readback 00:35Z 이후)
for id in 38990981390 38993632915 38993907587 38997388474 39000589841; do
  gh api repos/Archright/Axiom/actions/runs/$id \
    --jq '[.id, .event, .conclusion, .created_at, .head_branch] | @tsv'
done

# §2 겹침·§3 꼬리 — 잡 타임라인
#   겹침 = min(publish.completed_at, verdict.completed_at) − max(publish.started_at, verdict.started_at)
#   꼬리 = max(go-critical-lane .completed_at) − (접두사 없는 롤업 잡 `admission-check` .completed_at)
gh api repos/Archright/Axiom/actions/runs/38990981390/jobs \
  --jq '.jobs[] | [.name, .started_at, .completed_at, .conclusion] | @tsv'
#   (나머지 4런도 동일 — 38993632915 / 38993907587 / 38997388474 / 39000589841)

# §4 유일 red의 실패 스텝 + PR #895 회수
gh api "repos/Archright/Axiom/actions/runs/38997388474/jobs?per_page=100" \
  --jq '.jobs[] | select(.conclusion=="failure") | {job: .name,
        failed_steps: [.steps[] | select(.conclusion=="failure") | {number, name}]}'
gh api repos/Archright/Axiom/pulls/895 --jq '{merged_at, merge_commit_sha}'

# 세대·승격 근거
gh api /orgs/Archright/rulesets/25218071 --jq '.rules[] | select(.type=="workflows") | .parameters'
gh api repos/Archright/.github/pulls/227 --jq '{merged_at, merge_commit_sha}'
```

---

*본 문서는 사전등록 §5 동결 게이트의 판정 기록이다 — 게이트의 사후 조정은 인정되지 않는다. 판정 기준 원본은 [serial_chain_dag_prereg_2026-10-17.md](serial_chain_dag_prereg_2026-10-17.md)이며 본 문서는 이를 변경하지 않는다. 기계판독 쌍생 기록: `data/ci_optimization/candidate_a_s3_adjudication_2026-10-17.json`.*
