# PR Liveness Fail-Closed — V3 실행 증거 (2026-10-05)

**Slice**: V3 — PR Liveness Fail-Closed
**정본**: [docs/agents/merge_admission_observation.md](../agents/merge_admission_observation.md)
Liveness 절(종단 상태기계) · [docs/spec/merge_authority_integrity.md](../spec/merge_authority_integrity.md)
M6(판정 어휘 닫힌 집합)
**원시 스냅샷**: 세션 아티팩트(Rule Suite retention ≈1일 — 본 문서와
[merge_authority_integrity_2026-10-05.md](merge_authority_integrity_2026-10-05.md)가 장기 기록)

모든 값은 실제 명령의 관측 결과다. 추정값은 없다. 시각은 KST(UTC+9)로 통일하고 GitHub 원문
타임스탬프(`Z`)는 그대로 인용한다.

---

## 1. 동기 실측 — 읽기 API가 사유를 주지 않는 정체 구간

### 1-a. 사고 (2026-10-05 14:14:29 KST) — 49분 대기 루프

- merge queue가 entry를 가진 상태에서 main ruleset(`20303214`)에 `update` 규칙 추가 → 큐의
  ref 갱신 즉시 거절. Rule Suite `4360251067` — actor `github-merge-queue[bot]`(118344674),
  `refs/heads/main`, result **fail**, before `692056d1`. main 약 **49분** 동결.
- 관측 루프는 약 49분 동안 `queue=[empty] pr=[OPEN - -]` 정체를 반복 관측했다 — L1 green,
  PR OPEN, 큐 empty 어느 단일 신호로도 liveness를 판정할 수 없었다. 제어 계열의 종단
  상태기계가 없으면 관측기는 이 구간에서 **추측 또는 무한 대기** 중 하나에 빠진다.

### 1-b. Case B — armed · green · queue empty · BLOCKED 지속 (~40분)

- PR #482: auto-merge **armed**(2026-10-05 07:21:09Z) 이후 전 check **SUCCESS**(필수
  `admission-check` 포함, `isRequired=true`) + `mergeable: MERGEABLE` + 큐 **EMPTY** 상태로
  `BLOCKED` **지속(약 40분)**.
- **사유는 어떤 읽기 API에도 없었다**:
  - `mergeStateStatus` — reason 없는 **verdict**(`BLOCKED`)만 반환.
  - rule-suites — ref-update **시도**만 기록(큐 진입 거절 구간에 대응하는 main rule-suite의
    사유 판독은 불가).
- 사유 노출의 **유일 경로는 write-path 에러** — GraphQL mutation `enqueuePullRequest`의
  거부 응답 `"Pull request Cannot update this protected ref."`.
- 종결 실측: 큐 EMPTY 확인(M2 순서) 후 ruleset `20303214`를 control 5규칙으로 PUT 롤백
  (2026-10-05 16:57:39 KST) → 직후 동일 `enqueuePullRequest`가
  `{"mergeQueueEntry":{"position":1,"state":"QUEUED"}}` 성공 → 착지
  (merge commit `888575faa031ff54ece3cea5513675618002e415`, mergedAt `2026-10-05T08:10:53Z`,
  mergedBy `wintrover`). 상세: [merge_authority_integrity_2026-10-05.md](merge_authority_integrity_2026-10-05.md)
  E1-b · E5.
- 관측 공백(정직 기록): 성공적인 큐 착지는 `refs/heads/main` rule-suite를 발행하지 않았다 —
  "정상 착지의 rule-suite 부재" 자체가 관측 사실이다(사고 때의 fail suite `4360251067`과 대조).

## 2. MUST (M1–M7)

| ID | MUST |
|---|---|
| **M1** | liveness 판정의 권위는 GitHub이며, **단일 관측층(L1 green)의 성공은 liveness가 아니다** — required check SUCCESS + `isRequired:true` 상태의 PR이 OPEN으로 남는 것은 실측됨(PR #478, PR #482의 OPEN 구간). |
| **M2** | `merge_commit_sha` **단독으로 착지를 판정하지 않는다** — 착지 판정은 종단 상태기계의 SUCCESS(MERGED 관측: `state=="MERGED"` ∧ `mergeCommit.oid` 존재)와 결합할 때만 유효하다. |
| **M3** | `WAIT`는 **증거 identity의 변동 진행이 관측될 때만** 사용한다 — 시간 경과·재관측 횟수·추측한 서사는 WAIT 근거가 아니다. |
| **M4** | 판정 어휘는 본 문서 §3의 **닫힌 6종**뿐이다 — 그 밖의 어휘로 판정하지 않는다. |
| **M5** | **판정(verdict)과 사유(reason)를 같은 말로 쓰지 않는다** — 읽기 API에 사유가 없으면 blocker 이름을 판정에 결합하지 않는다(Case B: 사유는 write-path 에러로만 노출). |
| **M6** | `UNKNOWN`은 **성공 가능 상태가 아니다** — FAIL CLOSED, **즉시 정지**한다. 재관측 루프로 정지를 회피하지 않는다. |
| **M7** | **monitor write = 0** — 모니터는 GET/GraphQL query만 issuing한다. 정적 검증: `make check-monitor-purity`(게이트 PASS + negative FAIL — C1). 단, 이는 코드 경로의 정적 검증이며 호출 identity의 token scope 강제가 아니므로 **Tier 0 정직 기록**(스펙 §6·§10)을 유지한다. |

## 3. 판정 표 (종단 상태기계 — 요약)

| 판정 | 조건 |
|---|---|
| `SUCCESS` | MERGED 관측 — L3 종단(`state=="MERGED"` ∧ `mergeCommit.oid` 존재) |
| `FAIL` | 명시 blocker 관측 — `BLOCKED_BY_*`가 관측 사실로 뒷받침될 때 |
| `RECOMPUTING` | required 검증이 완료 결론을 내지 않은 상태(미완료 · 재실행 진행) |
| `LANDING_PENDING_ENQUEUE` | required 전부 SUCCESS + mergeable이나 큐 미착지 · 미MERGED 구간 (PR #482 OPEN 구간 · PR #478 실측) |
| `WAIT` | 증거 identity의 변동 진행 관측 시에만 (M3) |
| `UNKNOWN` | 위 어느 판정의 근거도 없음 → **FAIL CLOSED, 즉시 정지** (M6) |

## 4. Acceptance

| # | 조건 | 상태 |
|---|---|---|
| **C1** | purity 게이트 PASS + negative FAIL — `make check-monitor-purity` | **PASS**(2026-10-05 실측): `make check-monitor-purity` → `files=3 violations=0 exempt-lines=5` exit 0. negative: 스캔 표면(SKILL.md)에 `gh api -X PUT repos/...` 라인 삽입 → `[VIOLATION] .opencode/skills/ci-watch/SKILL.md:85 (pattern: -X PUT)` `violations=1` **exit 1** 확인 후 원복 → 재실행 exit 0 복귀. 면제 마커는 `tools/merge_ruleset_drift_monitor.nim`의 operator 안내 문자열(5행)에만 사용 — SKILL.md는 마커 없이 재기술로 해소. 부수: `make check-push-admissibility-integrity` PASS(유니버스 등록 확인) |
| **C2** | arm 전 관측 1라운드 → 기대 `UNKNOWN(NO_SIGNAL_YET)` 정지 | **PASS**(2026-10-05 18:32:31 KST 실측): 관측 1라운드 — raw facts: `state=OPEN`, 전 check `COMPLETED`(SUCCESS 10 · SKIPPED 8 — path 필터 생략은 충족 해석), `mergeStateStatus=CLEAN`, `mergeable=MERGEABLE`, `autoMergeRequest=null`, `isInMergeQueue=false`, 큐 entries `[]`. 진행 증거 0(진행 중 체크·pending run·큐 entry 모두 부재) ∧ 차단 증거 0 → 판정표 6행 `UNKNOWN`, evidence-kind=`NO_SIGNAL_YET` → **즉시 정지, 두 번째 라운드·`--watch` 미진입, 제어권 반환**. 대기의 근거가 전혀 없는 상태임을 라운드 1회로 확정 — 구버전 "실패 check 없음 → 대기" 레시피가 이 상태에서 무한 대기했을 자리다. 정지 후 operator 행위(arm)로 착지 계속(§Auto-Merge Default Policy) |
| **C3** | MERGED 관측 + merge commit 2-parent | **PASS**(2026-10-05 실측): 라운드 4(18:47:26 KST)에서 `state=MERGED` ∧ `mergedAt=2026-10-05T09:46:13Z` ∧ `mergeCommit.oid=0541e6f4357f00b4c2ce2fc529f17fecbe37b342` — SUCCESS 3요소 충족(`mergedBy=wintrover`, 큐 경로) |
| **C4** | merge commit 2-parent 검증 (MERGE 방법) | **PASS**: `git log -1 --format=%P 0541e6f` → `42aceb79170e26a57cb018297944b953b161d0d7 74b3f2b728ef803cedd95caf7d6b8ba2f2193bbc` — 부모 2개(이전 main + PR head), 네이티브 MERGE 확정 |
| **C5** | rule-suites 착지 구간 `update:fail` 0건 (착지 직후 수집) | **PASS**(2026-10-05 18:48:19 KST 수집): 착지 suite `4363455435` — `result=pass`, `before 42aceb791 → after 0541e6f43`, rule_evaluations 전부 pass(`required_status_checks` · `pull_request` · `deletion` · `workflows`×2). 착지 window 내 `{update, fail}` 0건. fail suite 3건은 전부 착지 window 밖(4361198253=T1 직접 push 거부 프로브, 4360251067·4359728935=사고대). **E5 정정 데이터**: 성공 착지도 pass suite를 발행함(`4362082437`→888575faa, `4362205564`→42aceb791, `4363455435`→0541e6f) — merge_authority_integrity 증거 E5의 "성공 착지는 main rule-suite를 발행하지 않는다"는 당일 캡처 범위 아티팩트였음 |
| **C6** | main 착지 커밋 canonical 실행 green | **PASS**(정직 기록 — 계획 전제 대체): `runner-pool-acceptance.yml`은 ADR-0025 Amendment B로 push@main 트리거가 제거됨(워크플로 헤더: "머지 이벤트에는 이 워크플로를 포함 아무것도 발화하지 않으며, 착지 = 순수 GitHub 네이티브 ref 이동"). 따라서 정본 실행 = merge_group `admission-gate` run `37290994593`(head `0541e6f43`): 15잡 전부 completed — 성공 8(`gateway/select` · `attest/build-base-artifacts` · `gateway/ci-bootstrap` · `attest/admission-check` · `mint-prepare/prepare` · `mint-publish/publish` · `verdict/admission-check` · `admission-check`) · path-filter skip 7 — 최종 `admission-check` success(09:45:48Z) 25초 후 네이티브 착지(09:46:13Z). 부수: `ci-cache-publisher` workflow_run success(09:45:52Z) |
| **C7** | self-hosting — main 정본 절차로 후속 PR 관측·착지 | **PASS**(2026-10-05 실측, 두 번째 데이터 포인트 — PR #484): 라운드 체인 전체 재현 — WAIT(체크 3개 IN_PROGRESS, 18:57:15) → checks green(`gh pr checks --watch` exit 0, 19:10:22) → **arm 전 1라운드 `UNKNOWN(NO_SIGNAL_YET)` 즉시 정지**(19:10:44: `CLEAN`·`autoMergeRequest=null`·큐 empty·진행·차단 증거 0) → operator arm(19:11, head `ff2c4562e0130b3039b1c70a8e1392fd99cdf75b`) → 큐 entry `AWAITING_CHECKS, position=1`(19:11:34, **WAIT** — entry identity) → merge group `admission-gate` run `37294961065` 라운드 관측(잡 전이로 identity 변동 3회: `updated_at` 10:11:29→10:16:31→10:19:20Z, 최종 `admission-check` 잡 in_progress) → 라운드 5(19:24:02): run `success`(10:22:44Z) ∧ **`state=MERGED` ∧ `mergedAt=10:23:10Z` ∧ `mergeCommit.oid=56fdef215ed13cc9101c4282fa098acda93df941` → SUCCESS**. 부속: 2-parent(`0541e6f4` + `ff2c4562e`), 착지 suite `4363968222`(pass, actor `wintrover`, arm 시각 19:11:03 평가 — E5 정정과 부합) |
| **C8** | 증거 파일 2건 완성 | **PASS**: 본 파일 C1–C7 전 행이 실측값으로 기입 완료(미관측 슬롯 0). C2–C6 기입·E5/E6 정정은 PR #484(merge commit `56fdef215…`)로 착지, C7 행은 본 PR로 착지. 모든 값의 근거는 각 행 기재의 GitHub 권위 신호이며 파일 자체는 authority가 아니다 |
