---
name: ci-watch
description: Use when checking CI status, PR checks, or waiting for CircleCI/GitHub check completion (gh pr checks, circleci, verify-static, CI poll, PR merge readiness). Replace fixed wall-clock sleeps/timeouts with dynamic watch loops that exit the moment the check finishes.
---

> **정본 관계**: 이 스킬은 [merge_admission_observation.md](../../../docs/agents/merge_admission_observation.md)(관측 3층 L1/L2/L3 + Liveness 절)의 요약이자 호출 규약이다 — 절차의 정본은 그 문서이며, 이 파일은 이를 재정의하지 않는다(단방향 참조). 이 파일의 구버전이 규정한 무조건 `until ... sleep` 대기 루프는 동 문서의 hand-rolled polling 금지(15행)와 충돌했고, 2026-10-05 큐 정체 사고(~49분 무판정 루프)의 원인이었다. 아래 절차는 그 금지를 준수한다 — 관측 → 판정 → 재관측 최대 1회, 무조건 sleep 루프 없음.

# CI / PR 체크 대기 — 관측 1라운드 fail-closed 판정 (HARD RULE)

PR checks·머지 완료 대기는 루프가 아니라 **관측 라운드**다. 고정 벽시계 sleep(`sleep 90 && gh pr checks 2`)도, "MERGED 될 때까지" 도는 무조건 `until` 루프도 금지다 — 후자는 차단된 PR 앞에서 영원히 돌며 제어권을 반환하지 않는다.

- 원칙: **관측 1라운드 → 우선순위 판정 → 재관측은 사유가 있을 때 최대 1회** → 판정 불가면 즉시 FAIL CLOSED(정지 + 마지막 raw facts 출력 + 제어권 반환)
- 관측 명령은 GET/GraphQL query만 — 본 스킬의 monitor write calls = 0. auto-merge arm은 operator 행위로 본 스킬에서 수행하지 않는다(명령의 정본은 operator 절차 — docs/agents/rules_workflow.md §Auto-Merge Default Policy, docs/agents/operations.md; 변이 명령 리터럴을 모니터 표면에 복제하지 않는다)
- 재관측 interval ≥ 30초(`--interval 30` 항상 명시 — 정본 문서 관측 규칙)
- wall-clock timeout은 보조 안전망일 뿐, 판정의 핵심 의미론이 아니다

## 관측 명령 (GET/GraphQL query만 — 1회 스냅샷)

```bash
gh pr view <N> --json state,mergedAt,mergeCommit,mergeable,mergeStateStatus,autoMergeRequest,reviewDecision,statusCheckRollup,latestReviews
gh pr checks <N> --required     # --watch 없이 1회 스냅샷 (exit code: 0=성공, 비0=실패·pending)
gh api repos/<ORG>/<REPO>/commits/<HEAD_SHA>/status      # combined status
gh api repos/<ORG>/<REPO>/commits/<HEAD_SHA>/check-runs  # check run status·conclusion
```

판정 근거용 권위 관측:

```bash
gh api graphql -f query='
query($owner:String!,$name:String!,$num:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$num){
      state mergedAt
      mergeCommit{oid}
      mergeable mergeStateStatus
      autoMergeRequest{enabled}
      reviewDecision
      isInMergeQueue mergeQueueEntry{state position}
      commits(last:1){nodes{commit{oid parents(first:2){totalCount}}}}
    }
  }
}' -f owner=<ORG> -f name=<REPO> -F num=<N>
```

- required 여부의 해석자는 GraphQL `CheckRun.isRequired(pullRequestNumber:)`다(정본 문서 authority-per-fact 표) — 체크 이름 유사성·`gh pr checks` 롤업은 근거가 아니다
- `gh pr checks <N> --required --watch --interval 30`의 진입 조건: **직전 라운드 판정이 WAIT(진행 증거 존재 ∧ identity 변동)일 때 1회**. `--watch`는 내부 폴링 루프이므로 진행 증거 없이 진입하면 hand-rolled polling과 같아진다. 특정 run의 직접 관측은 `gh run watch <RUN_ID> --exit-status --interval 30`

## 관측 1라운드 판정 (우선순위 순, 매 라운드 위부터 평가)

1. **SUCCESS**: GraphQL `pullRequest.state == MERGED`(또는 REST `state=="closed" && merged==true`) ∧ `mergedAt` ∧ `mergeCommit.oid` → 정지. `merge_commit_sha` 단독으로 SUCCESS를 선언하지 않는다 — 병합 전에도 test merge commit으로 non-null일 수 있다(GitHub 공식 문서). MERGE 방법이면 merge commit의 parent 수 == 2를 부가 검증(`parents(first:2){totalCount}` 또는 REST commit의 parents 길이).
2. **FAIL**: 필수(required) context의 conclusion ∈ {failure, timed_out, cancelled, action_required} ∪ `mergeStateStatus==DIRTY` ∪ 필수 리뷰 CHANGES_REQUESTED ∪ strict 정책(`strict_required_status_checks_policy: true`)하의 BEHIND → 정지, evidence-kind=OBSERVED_BLOCKER.
3. **RECOMPUTING**: `mergeable==null` ∨ `mergeStateStatus==UNKNOWN` → 같은 head SHA로 재관측 1회만 허용(30초 이상 지연). 그 뒤에도 재계산 중이면 UNKNOWN.
4. **LANDING_PENDING_ENQUEUE**: `autoMergeRequest` 존재 ∧ 필수 요구 전부 충족 ∧ 큐 entry 없음 → 지연 재관측 1회만 허용(30초 이상). 그 뒤에도 entry 없으면 UNKNOWN. auto-merge armed 단독은 진행 증거가 아니다(2026-10-05 실측: armed + 전 check SUCCESS + 큐 empty 상태로 수십 분 정체).
5. **WAIT**: 진행 증거가 존재하고 그 **identity가 직전 관측 대비 변동했을 때만** 재관측 1회 허용. 진행 증거: check run status ∈ {queued, in_progress, waiting, requested, pending} / workflow run status ∈ {queued, in_progress, requested, waiting, pending} / combined status pending("Waiting for status to be reported") / merge queue entry의 state·position 변동 / (check suite status=queued ∧ run conclusion=failure → 재시행 중). identity가 무변동이면 WAIT 권한 없음 → 6번. 증거별 age 상한(GitHub 작성 타임스탬프 기준) 초과 → STALE_EVIDENCE → UNKNOWN.
6. **UNKNOWN → FAIL CLOSED**: 정지, 마지막 raw facts를 그대로 출력, 제어권 반환. **두 번째 라운드 없음.** evidence-kind = `NO_SIGNAL_YET`(진행·차단 신호 모두 없음) / `REASON_UNAVAILABLE`(차단됐으나 사유가 읽기 API에 없음 — enqueue 거부, 큐 제거 등) / `STALE_EVIDENCE`.

## FAIL이 아닌 것

- UNSTABLE(비필수 check 실패) · DRAFT · skipped/neutral(충족으로 간주) · stale(무시) — FAIL로 판정하지 않는다
- BLOCKED-without-reason("Merging is blocked"인데 사유가 읽기 API에 없음)은 FAIL이 아니라 **UNKNOWN(REASON_UNAVAILABLE)** — PR이 죽은 게 아니라 설명 불가라는 뜻이다. 차단 사유의 유일 권위는 rule suite 판독(`GET /repos/<ORG>/<REPO>/rulesets/rule-suites`의 `rule_evaluations[].details`)이며 retention은 약 1일이다
- 원인 taxonomy(BLOCKED_BY_REQUIRED_CHECK / BLOCKED_BY_REVIEW / BLOCKED_BY_AUTHORITY / BLOCKED_BY_QUEUE)는 reason/evidence-kind 속성으로 유지한다 — 관측 사실이 뒷받침할 때만 붙인다
- 레거시 제어 어휘 READY/NOT_READY는 이 스킬의 출력에서 폐기 — 판정 어휘는 SUCCESS/FAIL/RECOMPUTING/LANDING_PENDING_ENQUEUE/WAIT/UNKNOWN + evidence-kind로 닫는다

## bash 도구 timeout 매개변수 규칙

- bash 도구 호출의 `timeout` 필드는 상한 안전망(실패 방어선) 용도로만 — 예: `timeout: 600000` (10분 상한)
- 그 값은 "예상 완료 시간 + 넉넉한 여유"가 아니라 "관측 라운드가 자체 종료하지 못하면 무언가 잘못됨"의 경계여야 한다
- wall-clock timeout은 보조일 뿐 핵심 의미론이 아니다 — 판정은 관측 기반 상태·타임스탬프로 내리고, timeout은 멈춘 라운드를 회수해 제어권을 돌려주는 역할만 한다

## 배경 (왜 이 규칙이 있는가)

2026-08-05 PR#2 수렴 작업에서 `sleep 90 && gh pr checks 2` 패턴이 CI 런타임과 어긋나
불필요한 폴링이 반복됐다. CircleCI verify-static은 보통 1~2분 안에 끝나지만 이전 폴링은
고정 간격이라 결과 확인이 지연되거나, 반대로 완료 전에 확인해 빈 결과를 봤다.

2026-10-05: 본 스킬 구버전의 레시피(`until gh pr view <N> --json state -q .state | grep -q MERGED; do sleep 5; done`)가 "Merging is blocked" 상태의 PR 앞에서 `queue=[empty] pr=[OPEN - -]`를 ~49분간 루프했다. 원인은 셋이다: (1) 성공 조건만 보는 무조건 until 루프, (2) 차단 사유를 읽지 않는 판정, (3) 재관측 상한 부재. 같은 날 실측에서 auto-merge armed + 전 check SUCCESS + 큐 empty 상태가 수십 분 지속됐다 — armed는 진행 증거가 아니다. 위 절차는 이 세 원인을 모두 닫는다.

## 체크

- 대기 코드/명령에 `until <조건>; do sleep <N>; done` 무조건 루프가 보이면 위반 → 관측 1라운드 판정 절차로 교체 (hand-rolled polling 금지 준수: 관측 → 판정 → 재관측 최대 1회)
- 관측은 GET/GraphQL query만, monitor write calls = 0, 재관측 interval ≥ 30초
- SUCCESS 선언 전 3요소(state==MERGED ∧ mergedAt ∧ mergeCommit.oid) 확인 — merge_commit_sha 단독 금지, MERGE 방법이면 parent 수 2 부가 검증
- 판정 불가(UNKNOWN)는 반드시 정지 + raw facts 출력 + 제어권 반환 — 추가 라운드로 메우지 않는다
- 출력 어휘: SUCCESS/FAIL/RECOMPUTING/LANDING_PENDING_ENQUEUE/WAIT/UNKNOWN + evidence-kind — READY/NOT_READY 사용 금지
