# Post-Candidate-A D3 분해 — 신세대 착지 5 PR (#892–#894·#895R·#898) (2026-10-17)

> **종류**: 측정 기록. **질문**: Candidate A(publish∥verdict) 채택 후 신세대 착지 5건의 D3 성분 분해 — (1) **PR-헤드 D1 쌍둥이는 사전-A 대비 축소했는가** (Candidate A는 양 장소(PR·MG)의 컨트롤러를 함께 변경), (2) 1256s 목표까지의 잔여 갭과 그 **소재(D1 vs MG-wall vs tail)**.
> **정의**: 동결 공식([d3_gap_decomposition_2026-10-17.md](d3_gap_decomposition_2026-10-17.md) — prereg [go_matrix_parallelization_2026-10-16.md](go_matrix_parallelization_prereg_2026-10-16.md) §4.1 G-B verbatim, 한 글자 변경 없음) — D1=생성→첫 required-green, preQ=생성→ADQ, D2′=ADQ→바운드 MG 런(created_at), MG wall=런 created→updated, tail=mergedAt−런 종료, D3=mergedAt−생성. 항등식 `preQ+queue-wait+MG-wall+tail = D3` — **5/5 정확 성립**.
> **권위**: 첫 green의 required 집합은 ruleset **20303214**(repo main) 선언 `admission-check`·`bsec-integrity`([landing_observe.sh](../../tools/ci/landing_observe.sh)와 동일 authority-first 규약 — 런타임 관측이 아닌 선언 소비). merge-admission 판정 권위는 GitHub(org ruleset·merge queue·native MERGE 커밋)이며 본 기록은 Reporter다. 수치는 전부 runs/jobs/check-runs API GET 관측값(초 해상도 ±1s).
> **바인딩·교차검증 (5/5)**: 각 MG 런 `head_sha == PR mergeCommit`(native MERGE, parents=2) · ADQ = merge commit **committer date** · MG 롤업 check-run `admission-check` completed_at == 런 updated_at(±1s) · 첫 green → ADQ 선행 3–10s.

## 1. 표본 — 신세대 착지 전수 5건 (2026-10-17T01:23Z–04:40Z)

Candidate A 승격(H_new=`29094836`) 재핀 창 이후, MG 증거 게이트 활성화(canary #897·#900, ruleset 재핀 `2c81072d4a`) 착지 **이전**의 완결 신세대 merge_group 착지 전수. #895는 1차 시도 red(run 38997388474, verdict predicate 부결 — [serial_chain_candidate_a_s3_adjudication_2026-10-17.md](serial_chain_candidate_a_s3_adjudication_2026-10-17.md) §4 귀인 기록) → 동일 브랜치 fix push(`62dbeab8b`, 03:40:07Z) → 재시도 run 39000589841 green → MERGE. 표본은 재시도 런으로 대표한다(**#895R**).

## 2. 성분 표 (초)

| PR | MG run | D1 | preQ | D2′=queue-wait | MG wall | tail | D3 |
|---|---|---:|---:|---:|---:|---:|---:|
| #892 | 38990981390 | 284 | 287 | 18 | 578 | 27 | **910** |
| #893 | 38993632915 | 244 | 252 | 18 | 754 | 14 | **1038** |
| #894 | 38993907587 | 296 | 306 | 18 | 661 | 6 | **991** |
| #895R | 39000589841 | 3417 | 3426 | 18 | 494 | 26 | 3964 |
| #898 | 39002722089 | 299 | 305 | 18 | 674 | 24 | **1021** |

항등식 5/5 정확(예: #892 — 287+18+578+27=910). **#895R은 분리 보고**: 그 D1·preQ·D3는 1차 red 왕복(재푸시+재-AME+재큐)을 포함하는 **착지 이벤트 시간**이지 컨트롤러 지연이 아니다 — 같은 런의 MG wall은 표본 **최단 494s**다. 이하 중앙값은 n=5와 깨끗한 n=4(#892/893/894/898)를 병기한다(사전-A 기록의 n=8/n=7 병기 관례와 동일).

## 3. 중앙값 (초)

| 집단 | D1 | preQ | D2′ | MG wall | tail | D3 |
|---|---:|---:|---:|---:|---:|---:|
| n=5 | 296 | 305 | 18 | 661 | 24 | 1021 |
| 깨끗한 n=4 | **290** | **296** | 18 | 667.5 | 19 | **1006** |

평균(깨끗한 n=4) 분해: preQ 287.5(29.0%) + queue-wait 18(1.8%) + **MG wall 666.8(67.3%)** + tail 17.8(1.8%) = D3 990.0.

## 4. 핵심 질문 — PR-헤드 D1 쌍둥이 축소: **YES**

| | 중앙값 | 범위 |
|---|---|---|
| 사전-A (n=8, #880–#887) | **437** (n=7 = **491**) | 302–588 |
| 사후-A (n=5) | **296** | 244–3417 |
| 사후-A 깨끗한 n=4 | **290** | 244–299 |

- 축소 폭: 깨끗한 n=4 기준 **−147s vs 437 / −201s vs 491**(−33.6%/−40.9%); n=5 기준 −141/−195s.
- **분포 전체 이동**: 깨끗한 4건 전부(244–299)가 사전-A 최소값(302)보다 낮다.
- 기구: 사전-A D1의 직렬 사슬 서명(mint→verdict→rollup ≈ +160s)은 PR-헤드 장소의 쌍둥이였고, Candidate A가 양 장소 컨트롤러를 함께 바꾸면서 D1에서 그대로 실현됐다. PR-헤드 재배치 관측(#895R 헤드 런): attest-rollup 03:47:42→03:49:21, **verdict 03:49:57→03:51:24**, publish 03:53:50→03:54:18 — verdict가 publish를 기다리지 않는다.
- 같은 방향 보조 관측: MG wall 깨끗한 평균 666.8 vs 사전-A 877.6(**−210.9s**) — 사내 직렬 사슬 축소(최종 레인→롤업 꼬리 {190, 284, 217, 300, 185} 중앙값 **217s**; 판정 기록 5런 표본 229s와 동일 계열, 사전-A 291 대비 −74s) + bootstrap 웜(아래 §6).

## 5. 잔여 갭 — 1256s 목표와 소재

- **깨끗한 4건 전부 목표 이내**: 910·991·1021·1038 (headroom +346/+265/+235/+218, 중앙값 여유 **−250s**). n=5 중앙값 1021도 목표 이내. → **본 창에서 목표 달성 관측**(단 n=4·웜 편향 — SLO 선언이 아니다).
- **소재(깨끗한 n=4 평균 기준)**: **MG wall 666.8s(67.3%)** ≫ preQ/D1 287.5(29.0%) ≫ queue 18(1.8%) ≈ tail 17.8(1.8%). 다음 축소 레버는 **MG wall 내부**(사내 직렬 사슬 잔여 중앙값 217s + bootstrap 콜드 편차)이고, 그다음이 preQ/D1(제품 구조 변경 필요 — 사전-A 귀속 유지). 큐 픽업 18s·tail ~19s는 GitHub 고정 역학 — 사전-A 판정(큐 파라미터 레버 소진) 재확인.
- **#895R의 3964s는 이상치가 아니라 red 1회의 실비용 관측이다**: D3 − 깨끗한 중앙값 = **+2958s**(1차 red 03:16:41 → 재푸시 03:40:07 → 재-AME 03:46:15 → 재-green 03:54:24 → 재-ADQ 03:54:33). 감소 경로는 red 예방(콘텐츠 사전 검증)이지 큐·컨트롤러가 아니다.

## 6. 정직 한계

- n=4 깨끗한 표본(+#895R) — 단일 창(2026-10-17 오전), 트래픽 희소. R-7 관례상 P95 단독 판정 금지.
- **웜 편향**: bootstrap(gateway/ci-bootstrap)이 스킵 1(#893, 웜 아티팩트 완전 재사용)+웜 3(#892 80s·#894 69s·#898 101s) vs 콜드 1(#895R 281s) — 사전-A 3/8 웜 대비 웜 편향 표본이다. 콜드 만연 시 MG wall은 +100~200s 과소 추정.
- D1의 required 집합은 ruleset 20303214 선언 기준(컨텍스트 2개). 선언 변경 시 재측정 필요.
- MG 증거 게이트 활성화(#897/#900)는 본 창 **이후** 착지 — 본 표본은 활성화 이전 세대(H_new=`29094836`) 관측이다.
- API 초 해상도 ±1s. tail 6s(#894)는 해상도 하한 근접.

## 7. 판정 (verdict)

**TARGET_MET_CLEAN_SAMPLE** — D3 중앙값 **1006s**(깨끗한 n=4) ≤ 1256s, 4/4 목표 이내(n=5 중앙값 1021도 이내); **PR-헤드 D1 쌍둥이 축소 확정**(437/491 → 290/296, −147~−201s). 잔여 최대 성분은 **MG wall 내부**(67.3%). 기계 판독 쌍생 기록: `data/ci_optimization/post_a_d3_2026-10-17.json`.

## 8. 재현

```bash
gh pr view 892 893 894 895 898 -R Archright/Axiom --json number,createdAt,mergedAt,mergeCommit 2>/dev/null \
  || for n in 892 893 894 895 898; do gh pr view $n -R Archright/Axiom --json number,createdAt,mergedAt,mergeCommit; done
for id in 38990981390 38993632915 38993907587 39000589841 39002722089; do
  gh api repos/Archright/Axiom/actions/runs/$id --jq '[.id,.head_sha,.created_at,.updated_at] | @tsv'  # head_sha==mergeCommit 바인딩
done
gh api "repos/Archright/Axiom/commits/<mergeCommit>/check-runs" --paginate \
  --jq '.check_runs[] | select(.name=="admission-check" or .name=="bsec-integrity") | [.name,.conclusion,.completed_at] | @tsv'  # D1
for n in 892 893 894 895 898; do gh api --paginate repos/Archright/Axiom/issues/$n/timeline \
  --jq '.[] | select(.event=="auto_merge_enabled") | [.created_at] | @tsv'; done  # AME
gh api orgs/Archright/rulesets/20303214 --jq '.rules[] | select(.type=="required_status_checks") | .parameters'  # required 집합
```
