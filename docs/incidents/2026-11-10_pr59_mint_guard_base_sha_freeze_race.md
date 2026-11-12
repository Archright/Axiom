# 인시던트 감사 기록 — PR #59 mint 가드 base.sha 동결 경쟁 (2026-11-10)

- 문서: `docs/incidents/2026-11-10_pr59_mint_guard_base_sha_freeze_race.md`
- 사건 일자: 2026-11-10 / 기록 작성: 2026-11-10
- 성격: PR #59(workstream/closure-toolchain-hash, DEBT#522 클로저 툴체인 정체성 캐시 — `docs/evidence/closure_toolchain_identity_cache_2026-11-10.md`)의 PR-head 검증이 org admission-gate `mint-prepare` A0 활성 가드에서 fail-closed된 현상의 원인·회복 경위 기록. κ workstream 회복의 follow-up으로 2026-11-08 인시던트 문서 §5 운영 대응 절차의 4항(증거 보존 — 본 문서 형식(EV-n)으로 `docs/incidents/`에 추가 기록)에 따라 등록한다
- 분류: §2.3(merge-admission 관측 계약) — main 활발기에 PR open~마지막 이벤트 창 내 타 착지가 있으면 PR REST `base.sha` 동결 스냅샷과 anchor-resolve의 실시간 tip 비교가 구조적으로 불일치함을 보인 사례. 회복은 conflict 해소 → 조용한 창 close→reopen(base.sha 갱신) → push(synchronize)로 관측됨
- 특기 사항: reopened 이벤트의 워크플로우 무발파(2회)는 GitHub 문서화된 "merge conflict 시 조건부 스킵"의 정상 동작이다(변이 아님 — §1.6). mint 체인은 diff 내용과 무관하게 발파된다(선행 docs 전용 PR #55 관측: `mint-prepare / prepare` success, 런 `42743994316`) — 본 문서의 착지 PR도 창 내 main 전진이 있으면 동일 경쟁에 노출되며 §5 절차가 그대로 적용된다

모든 시각은 UTC. 근거 ID(EV-n)는 아래 관측에 대응하며, 원시 관측은 GitHub REST API GET(`pulls/{n}`, `actions/runs`, `actions/runs/{id}/jobs`, `actions/jobs/{id}/logs`, `issues/{n}/timeline`)과 `git log`로 2026-11-10 획득했다. org ruleset 파생 런은 `gh run view`가 404(`gh_run_observation_quirks.md` Q8)이므로 전부 REST 직접 조회로 관측했고, 잡 로그는 Q3에 따라 `--allow-escape-sequences` + ANSI 제거로 취득했다.

## 1. 확정 사실

### 1.1 현상 — PR-head admission-gate 2연속 failure, 나머지는 전부 green

- [EV-1] PR #59(head_ref `workstream/closure-toolchain-hash`) opened 2026-11-10T03:30:53Z, base `main`. 병합 전까지 이 브랜치의 pull_request 런 버스트는 정확히 3회다: 03:30:57Z(opened, head `8cfd7e8`) 12종, 03:34:35Z(synchronize, head `ace197c`) 12종, 05:02:57Z(synchronize, head `13b29e1`) 12종. 각 버스트에서 admission-gate 외 11종(org landing-integrity 포함)은 전부 success/skip인데 **admission-gate만 1·2 버스트에서 failure** — 실패 잡은 `mint-prepare / prepare`(job `129612274261`, `129613997038`).
- [EV-2] 3 버스트 외에 이 브랜치의 워크플로우 런은 존재하지 않는다 — 04:13:25Z·04:59:35Z 두 번의 reopen에서 생성된 런 0건(§1.6).

### 1.2 가드의 비교 구조 — 두 표면(baseSha 입력 vs PR REST base.sha)

- [EV-3] mint-prepare A0 가드(잡 로그 원문)는 workflow_call 입력 `baseSha`(= org 게이트 `anchor-resolve` 잡이 런 시점에 조회한 실시간 main tip B*)와 **mint 시점에 API로 재조회한 PR REST 객체의 `base.sha`**(`jq -r '.base.sha'`)를 비교한다: `[ "$p_base" = "$BASE_SHA" ] || fail "PR #$PR_NUMBER base.sha '${p_base:0:12}' != baseSha input '${BASE_SHA:0:12}'"`. head도 동일 구조(`head.sha` vs `headSha` 입력)이며, 성공 시 `MINT_A0_ACTIVATION: OK — workflow_call supplied facts re-verified via API`를 출력한다.
- [EV-4] anchor-resolve가 조회한 B* 실측: 런 1(잡 03:31:01~05Z) `baseSha: 6d4a963…`, 런 2(잡 03:34:39~44Z) `baseSha: 15cb666…`, 런 3 `baseSha: 5ff3ce7…` — 각각 런 개시 시점 실시간 main tip과 일치한다(§1.3).
- [EV-5] PR REST `base.sha` 실측: open 시점 `6d4a963`(tip 03:14:39Z `6d4a963`와 일치) → **synchronize push 후에도 불변**(런 2의 가드가 03:39:59Z에 `6d4a963` 판독 — push가 03:34:3x에 있었음) → 04:59:35Z reopen 후 `5ff3ce7`(최종 관측값, 04:54:27Z tip과 일치). 즉 PR REST `base.sha`는 open/reopen에만 갱신되는 동결 스냅샷이며 push(synchronize)는 갱신하지 않는다.

### 1.3 main 전진 타임라인 — 경쟁의 구조

- [EV-6] merged_at 실측(tip 전진): 03:14:39Z `6d4a963`(PR #54) → 03:32:50Z `15cb666`(PR #55) → 03:44:09Z `2f3d256`(#57) → 04:03:20Z `bf4b3c9`(#56) → 04:08:39Z `4909e75`(#53) → 04:23:08Z `1332419`(#58) → 04:41:25Z `e5c0ef5`(#60) → 04:54:27Z `5ff3ce7`(#61) → 05:56:35Z `3368a69`(#62) → 06:03:15Z `f519fa1`(PR #59 착지). PR #59의 PR-head 검증 창(03:30:53~05:02:57Z) 동안 **7회의 타 착지**가 main을 전진시켰다.
- [EV-7] 첫 불일치는 PR #55의 큐 착지(03:32:50Z)가 만들었다: PR #59 open(03:30:53Z) 직후 4초에 생성된 opened 런(03:30:57Z)의 anchor-resolve는 아직 `6d4a963`을 조회(§1.4 런 1), 그 사이 03:32:50Z main이 `15cb666`로 전진 — 03:34:35Z synchronize 런의 anchor-resolve는 `15cb666`을 조회하고 가드는 동결된 `6d4a963`과 비교했다.

### 1.4 두 실패 서명 (잡 로그 원문)

- [EV-8] 런 1 `42749935687`(03:30:57Z, head `8cfd7e8`, attempt=1): `MINT_A0_ACTIVATION: FAIL — PR #59 head.sha 'ace197c7d6ba' != headSha input '8cfd7e838167' (fail-closed)`(03:34:58Z) — 런 진행 중 head 전진(`ace197c` push → 03:34:35Z 런 2 생성)을 잡은 head 불일치 변종. 이 런의 baseSha 입력 `6d4a963`은 당시 PR `base.sha`(런 2가 03:39:59Z에 동일값 판독, EV-5)와 일치했다 — base 검사에 도달하기 전에 head 검사가 실패했다.
- [EV-9] 런 2 `42750333468`(03:34:35Z, head `ace197c`, attempt=1): `MINT_A0_ACTIVATION: FAIL — PR #59 base.sha '6d4a96348d5f' != baseSha input '15cb666c9405' (fail-closed)`(03:39:59Z) — **본 건의 본체 서명**(base.sha 동결 vs B* 실시간). head는 일치했다.

### 1.5 회복 — conflict 해소 → 조용한 창 close→reopen → push

- [EV-10] conflict 해소 체인(로컬 커밋 3건, 05:02:5x 1회 push): `0e257ed`(04:25:32Z, "merge main 4909e75: debt registry projections regenerated (engine codegen+sync-budget, validate 1610/1610)"), `ad4d42b`(04:34:22Z, "Merge remote-tracking branch 'origin/main'"), `13b29e1`(04:56:38Z, "Merge remote-tracking branch 'origin/main'") — 전진한 main과의 충돌을 origin/main 병합 + debt engine 재생성으로 해소했다(`0e257ed` 커밋 메시지가 "debt registry projections regenerated (engine codegen+sync-budget, validate 1610/1610)"을 기록).
- [EV-11] close→reopen 2회(issues timeline): 04:13:23Z closed → 04:13:25Z reopened, 04:59:33Z closed → 04:59:35Z reopened. 최종 유효 갱신은 04:59:35Z reopen이다(갱신된 base `5ff3ce7`, 다음 tip 전진 05:56:35Z까지 62분 안정). 1차 reopen(04:13)의 갱신값은 관측 보존이 없어 확정하지 않는다(§3(b)) — main이 그 후 3회 더 전진(1332419→e5c0ef5→5ff3ce7)했으므로 reopen 갱신은 즉시 낡을 수 있음이 이 구조 자체로 실측된다.
- [EV-12] 조용한 창 관측: 04:30:00Z~05:10:00Z에 생성된 merge_group 런 0건; main tip `5ff3ce7` 안정 창 04:54:27Z~05:56:35Z. 2차 reopen(04:59:35Z)과 push(05:02:57Z)는 모두 이 창 안에서 수행됐다.
- [EV-13] 회복 런 `42759635203`(05:02:57Z synchronize, head `13b29e1`): `mint-prepare / prepare` job `129643865514`(05:08:25~05:08:50Z) — `baseSha: 5ff3ce7e…` 입력 = PR REST `base.sha` `5ff3ce7` 일치 → `MINT_A0_ACTIVATION: OK — workflow_call supplied facts re-verified via API (runId=42759635203 pr=#59 event=pull_request path=.github/workflows/admission-gate-v2.yml)`(05:08:28.997Z). 런 결론 success.
- [EV-14] 큐 페이즈: added_to_merge_queue 05:37:54Z; merge_group 런 9건 05:38:10Z 생성(큐 브랜치 `gh-readonly-queue/main/pr-59-3368a696…`, head_sha `f519fa11`, 전부 success — admission-gate `42763363179` 포함). 큐는 스펙큘레이티브 스택(Q2)으로 PR #62 그룹 `3368a69` 위에 그룹 `f519fa1`을 구축했다(커미터 05:37:54Z) → PR #62 착지(05:56:35Z) 후 **PR #59 MERGED 06:03:15Z**, merge commit `f519fa11` parents=`3368a696`+`13b29e153`(`git log -1 --pretty=%P` 관측) — 2-parent 정상 경로, bypass 없음.

### 1.6 reopened 무발파(2회)의 정체 — 문서화된 조건부 스킵

- [EV-15] 04:13:25Z·04:59:35Z reopen 어느 쪽도 워크플로우 런을 생성하지 않았다(EV-2). 두 시점의 원격 head는 `ace197c`(구 main 기반)였고 conflict 해소 체인은 아직 push되지 않은 상태였다(05:02:5x push, EV-10) — reopen 무발파 관측과 문서화된 조건부 스킵(merge conflict)의 조합이 이 상태의 기계적 설명이다. GitHub 공식 문서: "Workflows will not run on pull_request activity if the pull request has a merge conflict. The merge conflict must be resolved first."(§6 인용) — 2026-11-08 인시던트 문서 §6가 인용한 바로 그 조건부 스킵의 정상 발화다(미발파 변이 아님). reopen의 목적은 런 발파가 아니라 **PR REST `base.sha` 갱신**(EV-5)이었고, 런 발파는 conflict 해소 후 push(synchronize)가 담당했다.

## 2. 근본 원인 판정

- **판정: 설계된 fail-closed의 정상 동작 + base 스냅샷 표면 경쟁.** 가드는 "mint는 승인된 base에 결속되어야 한다"는 계약(`docs/evidence/oct_outage_gpa_regression_mapping.md` M7 — "검사는 옳고(승인된 base에 결속되어야 한다), 오탐은 base 이동의 결과다")을 정확히 집행했다. 결함은 in-repo 어디에도 없다 — 회복이 코드·워크플로우 무변경으로 완결됐다(§7).
- **경쟁의 비대칭**: B*(anchor-resolve)는 매 런 실시간 tip을 조회하고, PR REST `base.sha`는 open/reopen에만 갱신된다. main이 활발한 날 PR open~마지막 이벤트 창에 타 착지가 1건이라도 있으면 base 불일치는 **구조적으로 확정**이며 rerun·push로 해소 불가다: push는 head만 바꾼다(런 2 실측 — synchronize 후에도 동결값 판독), rerun은 B*를 재조회해 동결 `base.sha`와 다시 비교한다(rerun 의미론 — Q5; 본 건에서 rerun 시도는 관측되지 않았다: 두 실패 런 모두 attempt=1이므로 rerun 무효는 기제 추론이지 관측이 아니다).
- **표면 3종 구분(선행 기록과의 정합)**: (i) **이벤트 페이로드 base** — reopen 미갱신·synchronize로만 전진(`gh_run_observation_quirks.md` Q6, `jcas_phase1_observation_run_index.md` A⁻ `37878074796`): ADM_IDENTITY류 검사가 소비하는 표면. (ii) **PR REST 객체 `base.sha`** — open/reopen 갱신·push 미갱신(본 건 EV-5): mint-prepare A0가 "re-verified via API"로 **mint 시점에 재조회**하는 표면. (iii) **merge ref `refs/pull/N/merge`** — close/reopen 미갱신(`l3_go_split_impl_2026-11-04.md` §6.7). Q6의 "reopen은 base.sha를 갱신하지 않음"은 (i)에 대하여 참이고 (ii)에 대하여 본 건이 반례 관측을 제공한다 — 서로 모순이 아니라 **표면이 다르다**. 이 구분이 본 변종의 핵심이다.
- **회복 경로의 변종성**: 같은 MINT_A0 false red 클래스의 문서화된 선행 회복은 (a) `gh_automerge_merge_queue_quirks.md` Q9 / PR #1208 — fresh head push + `gh pr update-branch` 동기화 후 재진입, (b) `judgment_reuse_pr_bcd_landing_2026-10-31.md` / PR #1150 — rebase+재push+재arm. 본 건은 conflict를 로컬 병합으로 해소한 뒤 남은 blocker가 동결 `base.sha` 하나였고, 이를 **close→reopen**(2026-11-08 인시던트 문서 §5의 3항 "회복 — close→ reopen 재발행"의 공식 절차)로 갱신했다. close→reopen이 회복 경로가 되는 것은 가드의 비교 표면이 REST 객체이기 때문이다 — 표면 (i)에 묶인 검사에는 reopen이 무효하고 synchronize만 유효하다(Q6).
- **`base.sha` 갱신의 근거 성격**: open/reopen 시 갱신은 본 건의 기계 관측(EV-5/11/13)이지 GitHub 공식 문서에 명문화된 동작이 아니다(NOT_DOCUMENTED — §6). 재검증 절차는 본 문서 §5의 4항.

## 3. 미확정 사항 (잔여)

- (a) PR REST `base.sha` 갱신을 유발하는 연산의 완전한 목록 — open/reopen은 본 건에서 관측됨; `gh pr update-branch`(동기화 API)의 갱신 여부는 Q9 #1208의 녹색 결과로 시사되나 본 건에서 독립 검증하지 않았다.
- (b) 04:13 1차 close→reopen 시점의 `base.sha` 값 — 중간 스냅샷 미보존(최종값 `5ff3ce7`과 04:59 reopen 시점 tip 일치로만 확정).
- (c) 본 건에서 rerun 시도는 0회(attempt=1×2) — §2의 rerun 무효 서술은 Q5 의미론에 근거한 기제 추론이다.

## 4. 재현 조건 (관측 기반)

- 필요조건(전부 본 건에서 관측됨): main 대상 PR open(base.sha 동결) + open~마지막 PR-head 런 창 내 **타 착지 1건 이상** + admission-gate(mint 체인 포함) PR-head 런 발파. 이 조건에서 mint-prepare A0의 base 불일치 fail-closed는 결정론적으로 발생한다 — 단 anchor-resolve가 착지 전 tip을 조회한 opened 런은 base 입력이 일치할 수 있다(런 1 — 그 경우 head가 전진 중이면 head 불일치로, 정지 상태면 통과로 갈린다).
- 활성화 관찰: 2026-11-10 03:30~05:56Z main 활발기(9착지/2.5시간)의 PR #59에서 재현. diff 내용(docs/code)은 이 경쟁의 판별 인자가 아니다 — docs 전용 PR #55도 `mint-prepare / prepare`를 실행·성공했다(잡 목록 관측, 런 `42743994316`). 노출을 결정하는 것은 창 내 main 전진 여부뿐이며, 본 문서의 착지 PR도 창 내 전진이 있으면 §5 절차의 대상이 된다.

## 5. 운영 대응 절차 (재발 시) — close→reopen 회복 경로

1. **진단(GET만)**: 실패 잡 로그에서 서명을 원문으로 확인한다 — `MINT_A0_ACTIVATION: FAIL — PR #N base.sha 'X' != baseSha input 'Y'`(base 동결) / `head.sha … != headSha input …`(head 전진). org ruleset 런은 REST로 조회한다(Q8: `gh api repos/Archright/Axiom/actions/runs/{id}/jobs` + `actions/jobs/{id}/logs --allow-escape-sequences`, Q3).
2. **rerun 금지·push만으로는 불충분**: push는 head를 바꾸지만 `base.sha` 동결값은 그대로다(런 2 실측). rerun은 B*를 재조회해 동결값과 다시 비교한다(Q5; §3(c)).
3. **conflict 해소 선행**: 동결 base와 현 tip 사이에 충돌이 있으면 origin/main 병합(필요시 debt engine 재생성 체인 — `--codegen`+`--sync-budget`+`--validate`)으로 해소한다. conflict 상태에서는 pull_request 워크플로우가 문서화된 조건부 스킵으로 발파되지 않는다(§1.6) — reopen의 갱신 효과는 남지만 런 발파는 conflict 해소 후 push가 담당한다.
4. **조용한 창 관측 후 close→ reopen**: `gh api repos/Archright/Axiom/pulls/<N> --jq .base.sha`와 `gh api repos/Archright/Axiom/git/ref/heads/main --jq .object.sha`가 일치하는 안정 창(타 착지·active merge_group 부재 관측, 재관측 간격 ≥30s)에서 `gh pr close <N> && gh pr reopen <N>` — 2026-11-08 인시던트 문서 §5의 3항 "회복 — close→ reopen 재발행" 준용. reopen 갱신은 즉시 낡을 수 있으므로(EV-11) **push 직전 마지막 연산**으로 수행한다.
5. **push(synchronize)로 재판정**: 해소 체인을 push해 새 런을 발파하고, `MINT_A0_ACTIVATION: OK`(runId·pr 원문)을 기계 관측한 뒤에만 진행한다(§2.3 — 단일 관측층 성공만으로 완료를 주장하지 않는다).
6. **증거 보존**: 재발 시 런 ID·서명 원문·`base.sha` 전이·tip 전진 표를 본 문서 형식(EV-n)으로 `docs/incidents/`에 추가 기록한다(2026-11-08 문서 §5의 4항 준용).

## 6. 공식 문서 인용

- [Events that trigger workflows — pull_request](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows): "By default, a workflow only runs when a `pull_request` event's activity type is `opened`, `synchronize`, or `reopened`." + **"Workflows will not run on pull_request activity if the pull request has a merge conflict. The merge conflict must be resolved first."** — §1.6 reopened 무발파의 규범 근거(2026-11-08 인시던트 문서 §6와 동일 인용).
- [Re-running workflows and jobs](https://docs.github.com/en/actions/how-to/managing-workflow-runs/re-running-workflows-and-jobs): 재실행은 원 이벤트의 SHA/ref 의미론을 재사용 — §2 rerun 무효 기제의 근거 체인(Q5 인용).
- **NOT_DOCUMENTED**: PR REST 객체 `base.sha`의 갱신 시점(open/reopen)은 공식 문서에 명문화되어 있지 않다 — 본 문서의 갱신 서술은 전부 기계 관측(EV-5/11/13)에 근거한다. merge queue의 스펙큘레이티브 스택은 [Merging a pull request with a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)와 Q2 관측 체인을 따른다.

## 7. 변경 필요 여부

- **in-repo 수정 불필요** — 가드는 설계 계약(fail-closed base 결속)을 정확히 집행했고 회복은 운영 절차만으로 완결됐다(§5). mint-prepare A0 활성 가드 구현은 org `Archright/.github` 측 소관이며 본 저장소의 수정 대상이 아니다.
- 대응은 §5의 절차(진단 → conflict 해소 → 조용한 창 reopen → push → OK 원문 관측)로 충분하다. 본 문서가 base 동결 변종의 표준 회복 근거 기록이다.
