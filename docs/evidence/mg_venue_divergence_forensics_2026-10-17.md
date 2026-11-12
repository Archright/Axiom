# merge_group red / pull_request green 발산 — 근본 원인 규명 (2026-10-17)

> **종류**: 포렌식 관측 기록. **대상**: `docs/incidents/2026-10-13_pr814_pr815_direct_merge_audit.md` §5 TEST-2의 미해결 후속("merge_group venue가 계통적으로 red" — 근인 규명은 범위 밖 follow-up로 남았음).
> **방법**: 읽기 전용 gh GET, 완결 런 로그만, 전수 조사(10-13T00:00Z → 수집 시각; 10-16 15:00Z와 10-17 두 차례 새로고침 사이 신규 merge_group 런 0 — 전수 성립).
> **권위**: 본 기록은 Reporter다 — 관측이지 병합 판정이 아니다.

## 1. 실패 전수 (admission-gate merge_group)

132런 = 85 success / **47 failure — 전부 2026-10-15T04:23:39Z 이전** (10-13: 36, 10-14: 9, 10-15: 2). **G2 h4 결함 창(10-15 18:21→19:34Z) 0 실패** / **post-G2-fix 25런·post-Lever-B 7런 전부 success** — 발산은 더 이상 발생하지 않는다.

실패 클래스(47건): **R** 착지-술어 회전 거부(ROT_ALLOWLIST/ROT_NEW_PIN) 15 · **M** mint fail-closed(MINT_PUB_TREE 계열 6 + P7b 증거 번들 3) · **A** attest 내용/캐시(콜드-링크 #828 포함) · **F** `CANDIDATE_MERGE_BASE_UNRESOLVED` 계통 플레이크 · **I** 평가 중 push(stale cert) · **X** 아티팩트 결손(#829). 17/47은 오류 원문 직접 확인, 나머지는 실패 잡 위상(attest-first/mint-only/verdict-only)으로 분류.

## 2. red-MG/green-PR 쌍 — 26/26 전수

실패 26개 상이 헤드마다 pull_request 이벤트 admission-gate 런이 정확히 1건씩 **success(attempt 1)** 로 존재(해당 헤드의 첫 MG 실패 이전 완결). 트리 동일성: #814·#838은 **양 venue 바이트 동일**(tree(group)==tree(head)) — 트리 차이만으로는 패턴 설명 불가.

## 3. 근본 원인 판정

"MG 체계적 red / PR green"은 **단일 결함이 아니다**:

1. **설계상 평가 비대칭 (ADR-0032)** — PR venue 판정은 **preflight leg**이다. 양 venue의 PR 판정 로그는 전부 `PREFLIGHT PASS — … preflight success ≠ landing evidence — the canonical verdict is the merge_group verdict, ADR-0032 (a),(f)`로 종결. 전체 착지 술어(회전/클로저 ROT_*, 인증 headSha 결속, mint 증거 결속)는 **merge_group에서만 정본**으로 실행된다. 즉 R(15)·M(9)류가 실패한 술어를 "PR green"은 **애초에 실행하지 않았다** — "동일 코드, 다른 결과"가 아니라 **"다른 평가"**였다 (`docs/adr/0032-admission-venue-split.md`).
2. **사건 군집 산물 (전부 종결)** — #828/#829 콜드-링크 레이스(revert+재핀으로 종결, `mg_red_forensics_2026-10-14.md`) · 계통 플레이크 · 회전 거부는 정상 fail-closed 결과(재앵커된 헤드로 전부 green 착지; #813/#816은 CLOSED — **게이트가 옳았다**).
3. **트리 차이 (부차적, 실재)** — #812/#827은 진행 중 main 위 스택으로 group tree ≠ head tree — 평가 대상 자체가 달랐다.
4. **잔여 UNKNOWN 1건** — #814의 P7b `MINT_EVAPPEND: FAIL — sha256(bundle wire) != witness evidenceDigest` ×3(MG-only, 동일 트리). witness가 `provenance.prHeadSha`를 실어 MG/PR subject-identity 불일치가 개연하나 레인 전사 로그 소실로 원문 증명 불가 — 재발 감시 항목으로 기록.
   **[해소 — 2026-10-17]**: `docs/evidence/p7b_mint_evappend_resolution_2026-10-17.md`가 본 UNKNOWN을 소명했다 — 근본 원인은 **복제 다이제스트 정의 버그**(v2 7멤버 와이어 확장 직후 소비자의 4멤버 재유도; prHeadSha 가설은 반증 — witness digest가 3런 동일). MG-only 발현은 P7b의 landing 전용 실행 비대칙. 트리거는 당일 수정 커밋으로 제거됨(ADR-0034 계보). 보존 아티팩트 3런으로 바이트급 재현 완료.

## 4. 수정 표면

- **venue 결함으로서는 수정 불필요** — s1a의 MG 사망은 전부 되돌려진 병렬 레짐의 것이며 post-G2-fix 46런 0 레인 red. 워크플로 수정 대상 없음.
- **문서 정정이 실산출물** — 사고 문서 TEST-2 판정의 재귀속(본 PR의 부록 갱신): "계통적 red"는 ① preflight/정본 비대칭(설계) ② 사건 시대의 회전·병렬·플레이크 실패의 합성이었다.
- **경화 후보(별도, 비긴급)**: 계통 심화 상한(F류 — `gh_run_observation_quirks` Q5/Q6), MG 실패의 레인 전사 보존, P7b 결속 재발 감시.

## 5. 재현

```bash
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" --paginate --jq '.workflow_runs[] | select(.name|test("admission-gate") and .conclusion!="success") | [.id,.created_at,.head_branch,.conclusion]'
gh api "/repos/Archright/Axiom/actions/runs/<id>/jobs" --jq '.jobs[] | select(.conclusion=="failure") | [.name,.id]'
gh api --allow-escape-sequences /repos/Archright/Axiom/actions/jobs/<JOB_ID>/logs | tail -80
```
