# 인시던트 감사 기록 — PR #814 / #815 main 직접 병합 (2026-10-13)

- 문서: `docs/incidents/2026-10-13_pr814_pr815_direct_merge_audit.md`
- 사건 일자: 2026-10-13 / 기록 작성: 2026-10-14
- 성격: merge-path 보호 통제를 우회한 main 직접 병합에 대한 사후 감사 기록
- 분류: §3 — 소유자 직접 머지(비상 우회 패턴), `docs/agents/quality-gates.md:69` 사후 문서화 요건 적용 대상
- 특기 사항: **본 문서의 착지 자체가 Gate 1 병합 경로 통제 시험의 페이로드다** (§4, §5)

## 1. 확정 사실

아래 각 항목은 근거 ID(EV-n)를 부착한다. 모든 EV는 GitHub REST API GET 관측이며,
원시 JSON 스냅샷은 로컬 세션 증거로 `~/.cache/axiom/gate1_evidence/`에 보관된다.

### 1.1 직접 병합 사실

- [EV-1] PR #814: 2026-10-13T13:10:38Z MERGED. mergedBy=wintrover, mergeCommit=`fdd8703c84dca6195ddfd5925f5da678b03cf4eb`, head=`7d131271646dec5fa35253dea99ac74a4183fb16`. committer=web-flow(웹 병합).
- [EV-2] PR #815: 2026-10-13T13:10:43Z MERGED. mergedBy=wintrover, mergeCommit=`aa051134359ee37e50bf30bcc58187c58aa6fe3a`, head=`026eaafc6598f468fff997b97763dd4a02ab7e3f`. committer=web-flow(웹 병합).
- [EV-3] 두 PR 모두 리뷰 0건 — `GET /pulls/814/reviews`, `GET /pulls/815/reviews` 모두 빈 배열.

### 1.2 병합 직전 merge_group 평가 — 3회×2 전부 실패

- [EV-4] #814 merge_group 실행 3건 모두 `failure`: 38401843972(created 13:02:33Z), 38402599853(13:08:26Z), 38402732819(13:09:29Z). 큐 브랜치 `gh-readonly-queue/main/pr-814-ba773d0631b5757525b16d8fd62e220492e98e76`.
- [EV-5] #815 merge_group 실행 3건 모두 `failure`: 38401846277(created 13:02:35Z), 38402601651(13:08:27Z), 38402734886(13:09:30Z).
- [EV-6] 실패 지점(run 38401843972 jobs 관측): `mint-publish / publish` job의 step **"(P7b) [SL-15] evidence record → evidence CAS ledger append (exactly-once)"** failure → `verdict / admission-check`의 "[check] Admission predicate evaluation (MergeAdmissible verdict → check conclusion)" failure → 집계 check `admission-check`의 "[verdict] Every needed job must be success (skipped -> FAILURE, never green)" failure. 그 외 게이트 job(closure-deriver, attest/build-base-artifacts, gateway/*, attest/admission-check, mint-prepare/*)은 모두 success.
- [EV-7] run 38402732819의 종료 기록(updated_at)이 2026-10-13T13:22:47Z — 병합(13:10:38Z/13:10:43Z) **이후**에 기록됨. 즉 마지막 merge_group 평가가 아직 완료되지 않은 시점에 병합이 일어났다.

### 1.3 직접 병합의 입헌(admission) 근거로 관측된 것

- [EV-8] head_sha `ba773d0631b5757525b16d8fd62e220492e98e76`(merge_group 커밋) 기준 admission-gate SUCCESS: run 38365917625, created 2026-10-13T07:56:31Z, updated_at 08:14:57Z — 병합 시점 약 4시간 56분 전의 성공. #814 직접 병합은 이 **약 5시간 전 head-sha 체크 성공**으로 수용된 것으로 관측되며, 직전의 merge_group 신규 실패(EV-4/EV-5)는 직접 병합을 차단하지 못했다.

### 1.4 merge queue 이벤트

- [EV-9] 두 PR 모두 큐 added/removed ×3 반복. 최종 removal: #814 13:09:47Z, #815 13:09:50Z. 그 약 48~53초 뒤(13:10:38Z/13:10:43Z) 큐 밖에서 직접 병합됨.

### 1.5 설정 변경 흔적과 관측 한계

- [EV-10] repo ruleset 20303214(이름 "main", target branch, enforcement=active)의 updated_at = **2026-10-13T13:10:45Z**(KST 22:10:45.264+09:00) — #815 병합(13:10:43Z) 2초 후, #814 병합(13:10:38Z) 7초 후. GitHub는 ruleset 변경 이력 API를 제공하지 않아 **변경 전후 내용은 복구 불가**.
- [EV-11] org audit log: 조회는 가능하나 pagination/필터가 실효 동작하지 않아 2026-10-14T06:41Z 이후 데이터만 확보됨. ruleset usage/insights 계열 API는 404.

### 1.6 현재 보호 설정 스냅샷 (2026-10-14T13:44Z 기준 GET)

- [EV-12] ruleset 20303214 "main": `bypass_actors: []`, rules = `deletion`, `non_fast_forward`, `pull_request`(required_approving_review_count=0, allowed_merge_methods=["merge"], require_extra_approval_for_unattributed_changes=true, require_last_push_approval=false, required_review_thread_resolution=false), `required_status_checks`(context: `admission-check`, `bsec-integrity`; strict_required_status_checks_policy=false), `merge_queue`(merge_method=MERGE, max_entries_to_build=2, min/max_entries_to_merge=1/1, min_entries_to_merge_wait_minutes=0, grouping_strategy=ALLGREEN, check_response_timeout_minutes=120).
- [EV-13] legacy branch protection `GET /branches/main/protection` → HTTP 404 "Branch not protected" — 레거시 보호는 존재하지 않으며, ruleset만이 병합 경로 통제다.
- [EV-14] org-level rulesets: 24233738 "axiom-admission-gate"(active, conditions null), 23943917 "landing-integrity"(active, conditions null).

### 1.7 관측 타임라인 (2026-10-13, UTC)

| 시각 | 사건 | 근거 |
|---|---|---|
| 07:56:31Z | admission-gate merge_group run 38365917625 시작(head ba773d063) | EV-8 |
| 08:14:57Z | 위 run SUCCESS — 이것이 직접 병합 시점까지 유효한 마지막 head-sha 성공 | EV-8 |
| 13:02:33Z / 13:02:35Z | #814/#815 merge_group 1차 평가 시작 (→ failure) | EV-4/EV-5 |
| 13:08:26Z / 13:08:27Z | merge_group 2차 평가 시작 (→ failure) | EV-4/EV-5 |
| 13:09:29Z / 13:09:30Z | merge_group 3차 평가 시작 (→ failure; #814분 종료 13:22:47Z, #815분 13:27:33Z) | EV-4/EV-5/EV-7 |
| 13:09:47Z / 13:09:50Z | 큐 최종 removal (#814 / #815) | EV-9 |
| 13:10:38Z | **PR #814 main 직접 병합** (리뷰 0건) | EV-1/EV-3 |
| 13:10:43Z | **PR #815 main 직접 병합** (리뷰 0건) | EV-2/EV-3 |
| 13:10:45Z | ruleset 20303214 updated_at (내용 복구 불가) | EV-10 |
| 13:22:47Z | run 38402732819 failure 종료 기록 — 병합 뒤에 도래한 판정 | EV-7 |

## 2. 미확정 사항 (잔여)

- (a) 2026-10-13T13:10:45Z ruleset 20303214 변경 **내용** (EV-10: 이력 복구 불가).
- (b) 직접 병합을 허용한 **정확한 메커니즘** — 병합 시점의 ruleset 설정이 현재 스냅샷(EV-12)과 달랐을 가능성을 포함한다. 예: merge_queue 규칙의 일시적 미설정/파라미터 차이, 그 외 규칙 구성 차이. 확정된 것은 "당시 서버가 큐 밖 직접 병합을 수용했다"는 관측뿐이다.
- (c) 직전 설정과 현재 설정의 **차이** — 변경 전 스냅샷 부재로 재구성 불가.

## 3. 분류

- **소유자(wintrover) 직접 머지**다. 에이전트 활동의 증거는 없다(웹 커밋 web-flow, 리뷰 0건, 병합 직후 ruleset 편집 흔적 — EV-1/EV-2/EV-3/EV-10).
- `docs/agents/quality-gates.md:69`의 비상 우회(bypass) **사후 문서화 요건 적용 대상**이며, 본 문서가 그 이행이다.

## 4. Gate 1 병합 경로 통제 시험 (본 문서 = 페이로드)

- 목적: 현재 ruleset 20303214(EV-12) 상태에서 merge queue를 우회한 **직접 병합 시도가 서버에서 거부되는지**를 관측한다(통제 유효성 검증).
- 방법: 본 문서만을 담은 docs PR을 대상으로 (TEST 1) PR head 체크 green 상태에서 `gh pr merge --merge --match-head-commit <head>` 직접 병합 시도 → 거부 시(기대) (TEST 2) `gh pr merge --auto --match-head-commit <head>`로 큐 정상 병합을 관측한다.
- 제약: 시험은 신규 docs 파일 1개만을 변경본으로 운반하며(non-trust path), `.github/`·`config/policy/`·ruleset 설정에는 일체 접촉하지 않는다.
- 판정 기준: TEST 1이 **거부**(merge queue / not permitted 계열 오류)면 통제 유효 CONFIRMED. TEST 1이 **수용**되면 통제 실패 재현으로 기록하고 추가 병합 시도·설정 변경 없이 read-only 조사만 수행한다.
- 원문 결과는 §5에 기입되며, 본 문서의 착지 경로(큐 경유 여부) 자체가 시험 결과의 일부다.

## 5. Gate 1 결과 기입란

### TEST 1 — 큐 우회 직접 병합 시도 (관측 시각 2026-10-14T14:15:17Z)

- 전제 상태: PR head `1408ddaaa2a68fb3eacbffb7c317715ebc90edd3`, pull_request venue 체크 전부 green(집계 `admission-check` pass 포함, admission-gate run 38576485470 — 최초 attest/admission-check 1회 실패는 CANDIDATE_MERGE_BASE_UNRESOLVED(runner git fetch flake, round 1/8)로 코드 무관; rerun-failed-jobs HTTP 201 (2026-10-14T14:08:41Z) 후 green 회복), `mergeable_state=clean`.
- 명령: `gh pr merge 828 --repo Archright/Axiom --merge --match-head-commit 1408ddaaa2a68fb3eacbffb7c317715ebc90edd3` (직접 병합 시도, `--auto` 아님)
- 원문 응답 (exit code 0):
  ```
  ! The merge strategy for main is set by the merge queue
  ```
- 관측 결과: **병합 없음 — 거부/큐 전환 CONFIRMED.** GET /pulls/828 (2026-10-14T14:15:43Z): `state=open, merged=false, merged_at=null`. gh는 직접 병합 merge API 호출을 수행하지 않고 PR을 merge queue에 넣음(timeline `added_to_merge_queue` 2026-10-14T14:15:20Z). 즉 merge queue가 설정된 현재 ruleset(EV-12)에서 큐 우회 직접 병합은 수행되지 않았다. #814/#815 당시(EV-1/EV-2)와 대조적으로 현재 병합 경로 통제는 유효하게 관측된다.
- 한계 명시: 이 관측은 gh CLI 경로다. gh가 메시지 없이 서버 merge API를 직접 호출하지 않았으므로, 서버 원시 merge API(PUT /pulls/N/merge)의 거부 여부는 본 시험으로 확정되지 않는다(추가 시도는 수행하지 않음 — 시험 범위 밖).

### TEST 2 — 큐 정상 병합 (`--auto`) — 관측 결과 (2026-10-14T14:21~15:00Z)

- 절차: TEST 1의 부작용으로 14:15:20Z 큐 진입 → 문서 갱신을 위해 14:19:50Z dequeue(GraphQL `dequeuePullRequest`) → head 갱신(78e866b43) 후 14:21:23Z `gh pr merge 828 --repo Archright/Axiom --auto --match-head-commit 78e866b439dfa20599d6e3e1736165eb13792af4` (exit 0, 무출력, auto-merge 활성) → head 체크 전부 green 회복 후 14:27:41Z 자동 큐 재진입.
- 1차 merge_group 평가 (그룹 브랜치 `gh-readonly-queue/main/pr-828-1b187d1a5...`, 14:28:01Z 생성): landing-integrity·probe-merge-queue·bsec-integrity·observer-manifest-consistency는 전부 success, **admission-gate run 38580760673 FAILURE (14:44:05Z)** → 14:44:28Z 큐 자동 이탈. 실패 체인: `attest / admission-check` job — **GO-critical admission 테스트 `tests/unit/test_s1a_lean_golden.nim` (make test-fast-one non-zero, 27.9s)** 1/4 실패 → mint-prepare/publish·verdict·집계 admission-check 연쇄 실패. 동일 잡의 `test_d2_golden.nim`은 235.6s 전체 실행 후 PASS.
- 2차 merge_group 평가 (14:47:19Z 생성, 재진입 후): 나머지 4개 success, **admission-gate run 38583637985 FAILURE (14:59:48Z)** → 15:00:17Z 큐 자동 이탈. 실패 체인: 동일 job — **3/4 실패 (`proof_integrity_test.nim` + `test_s1a_lean_golden.nim` + 1, 레인이 전부 ~29-47s에 조기 종료)** → 동일 연쇄 실패. 1차(1/4, s1a만)와 2차(3/4)에서 **실패 레인 조합이 달라졌다** — 코드는 동일하고(docs-only), pull_request venue에서는 동일 코드가 전부 green이다.
- 판정: **TEST 2(양성 대조) 미달성 — merge_group venue가 계통적으로 red.** 이것은 #814/#815 직전 상황(EV-4/EV-5: docs/code 무관하게 merge_group만 6/6 실패)과 동일한 조건의 재현이다. 직접 병합은 차단되는데(TEST 1) 큐 정상 경로는 현재 통과 불가 — 즉 본 문서가 담긴 PR도 큐로는 착지할 수 없다(문서-관측 아이러니: 본 §5 기록 자체가 그 증거다). 원인 규명(GO-critical 테스트의 venue 간 불일치)은 범위 밖 follow-up이다.
- 본 착지 시도: §5 본 기록을 포함한 커밋으로 3번째(최종) 큐 시도를 수행했다 — 결과는 최종 보고에 기입한다(성공 시 MG run id + merge commit oid, 실패 시 PR은 open 상태로 잔존).

### 부록 — TEST 2 판정 재귀속 (2026-10-17)

전수 포렌식(`docs/evidence/mg_venue_divergence_forensics_2026-10-17.md`)이 §5 TEST-2의 "merge_group venue가 계통적으로 red" 관측을 재귀속했다: ① **설계상 평가 비대칭** — PR venue 판정은 preflight leg(ADR-0032)로 전체 착지 술어(ROT_*·mint 결속)를 실행하지 않으므로 "PR green"이 실패 술어를 평가한 적이 없다(다른 결과가 아니라 다른 평가) ② **사건 군집 산물** — 본 TEST 2가 #828 콜드-링크 사건 창(14:15–15:14Z)에서 수행됐고, 관측된 레인 조기 종료·조합 변동은 그 레짐의 서명이다(당일 revert+재핀으로 종결). **2026-10-15T04:23:39Z 이후 46+7런 0 실패 — 발산은 더 이상 재현되지 않는다.** 잔여 UNKNOWN 1건(#814 P7b MINT_EVAPPEND, 동일 트리 MG-only)만 재발 감시로 남는다.
