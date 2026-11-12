# Track 1 auto-merge 관측 기록 — PR #1250 3시점·지표 2종 (2026-11-03)

> **종류**: 관측 기록 — 상위 계약: docs/evidence/l3_go_prereg_2026-11-03.md §10 "Track 1 병행 시험 — 본 PR 차량(GitHub native auto-merge)". 본 문서는 §10 F-4(:188) "관측값(3시점·갭 2종·명령·auto-merge 상태)은 Phase C 증거 번들 또는 후속 docs PR에 착지"의 이행이다.
> **권위**: Reporter(관측·기록). 병합 admission 권위는 GitHub ruleset·merge queue다(AGENTS.md §2.3 — Authority ≠ Adapter).
> **Date**: 관측 2026-11-03 · 기록 착지 2026-11-04 · **Branch**: docs/track1-observation-20261104 · **Scope**: docs-only 비행 — 코드·워크플로우·게이트·핀·도구 변경 0건, trust surface 아님, 정상 merge queue 경로.
> **관측 규율**: GET-only · gh 네이티브 인증(AGENTS.md §2.4) · 관측 후 기준 변경 0건.

## §1. 관측 대상 (사전등록 §10 계약)

- **목적**(:178): PR green→큐 진입 갭(수동 med 60.5s, F-3)을 auto-merge로 제거 가능함을 실운영에서 관측. 시험 차량 = PR #1250 자체(docs-only·trustSurface 비적용·정상 arm 경로).
- **지표 정의**(:184): QueueEntryDelay = EnqueuedAt − RequiredChecksGreenAt · DispatchDelay = RunCreatedAt − EnqueuedAt(#1246 수동 실측 19s 참조).
- RequiredChecksGreenAt = required context 5종(admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice) check-runs completed_at의 최댓값.

## §2. 관측 프로토콜 실행

arm(gh_run_observation_quirks.md Q13 판정 규칙에 따라 arm 직전 PR state=OPEN 재검증 후 실행):

gh pr merge 1250 --auto --merge --match-head-commit 8c74275e4a0508ff2ebbc1988debb9637eb80532

→ 응답에 "merge strategy set by the merge queue" 포함(전략 선택권은 큐 소관) ·
autoMergeRequest {enabledAt 2026-11-03T13:22:53Z, enabledBy wintrover, mergeMethod MERGE} ·
타임라인 AutoMergeEnabledEvent 관측. arm은 green 약 6분 전(checks 완료 전)에 수행됐다.

## §3. 3시점 관측값

| 시점 | 값 | 관측 경로 |
|---|---|---|
| auto-merge 활성 | 2026-11-03T13:22:53Z | autoMergeRequest.enabledAt |
| RequiredChecksGreenAt | 2026-11-03T13:28:48Z | axiom-operational-slice completed_at(최댓값) — 5 required 전부 success |
| MergeQueueEntry.enqueuedAt | 2026-11-03T13:29:29Z | 라이브 창 GraphQL — 그룹 SHA ec2e90c30b01b24b6d902a54753386a7362c1bca, position 1 |
| AddedToMergeQueueEvent.createdAt | 2026-11-03T13:29:30Z | enqueuer wintrover — 병합 후에도 지속 관측(§5 [2]) |
| merge_group 런 8개 created_at | 2026-11-03T13:29:49Z | REST actions/runs?event=merge_group |
| MergedEvent(mergedAt) | 2026-11-03T13:38:24Z | mergeCommit = ec2e90c30b01b24b6d902a54753386a7362c1bca |

required 5-context verbatim(전부 success): generation-acceptance 13:22:16Z ·
debt-registry-gate 13:23:07Z · bsec-integrity 13:23:51Z · admission-check 13:26:37Z ·
axiom-operational-slice 13:28:48Z.

**지표 2종(계약 정의 그대로 계산)**:

- QueueEntryDelay = 13:29:29Z − 13:28:48Z = **41s**
- DispatchDelay = 13:29:49Z − 13:29:29Z = **20s**(#1246 수동 실측 19s와 일치)
- 파생(참고): green→merged 9m36s · enqueued→merged 8m55s · arm 이후 사람 개입 0

비교 기준(F-3 진단 코호트 — 본 기록과 합산·대체 금지):
docs/evidence/census_dual_lane_unknown_closure_2026-11-03.md:59 — auto-merge 선행 3건
(#1216·#1222·#1226) 갭 7/15/24s · 수동 12건 med 60.5s.

## §4. 3증거 readback (착지 시 2026-11-03 관측 · 핀·blob은 2026-11-04 재확인 동일)

1. **그룹 SHA 런 판정**: ec2e90c30b…의 merge_group 런 8/8 success — total_count: 8,
   conclusions {"success": 8}.
2. **main 반영(병합 시점 기록)**: main tip == ec2e90c30b01b24b6d902a54753386a7362c1bca ·
   부모 = 2f9c21693(PR #1249 merge) + 8c74275e4(PR #1250 head) · prereg blob
   1b1530e1a2c40d910b4f01660f849d17375bd61b 원격==로컬 · MergedEvent +
   RemovedFromMergeQueueEvent(reason "merged") 13:38:24Z. (이후 후속 PR로 tip은 자연 전진 —
   본 항은 병합 시점 관측이다.)
3. **양 ruleset 핀 불변**: orgs/Archright 25218071(axiom-admission-gate)·23943917
   (landing-integrity) 모두 active, workflows[].sha = 7eaa9624d128b9f10e9e40d140d5c23367dabdad.

**플랫폼 동작 관측(기록)**:

- mergeCommit == 큐 진입 시 MergeQueueEntry 그룹 SHA — **문서 보증 아님**(경험적 불변,
  본 관측 포함 5회 연속 일치). 판정은 위 3증거 구조로만 한다.
- mergeQueueEntry는 병합 후 null(라이브 창 전용) — 사후 재현 관측은
  AddedToMergeQueueEvent로 한다. autoMergeRequest도 큐 진입 후 null 판독 —
  Q9(autoMergeRequest는 liveness 신호가 아님)와 정합.
- 큐 진입은 검증을 우회하지 않는다: merge_group 재검증 8/8 +
  RemovedFromMergeQueueEvent(reason "merged").
- 저장소 "Allow auto-merge" 설정 변경 없이 큐 브랜치 auto-merge가 동작했다(사전 반박 검증
  정정: 해당 설정은 큐 브랜치 미적용).

## §5. 재현 명령 (GET-only — [1]~[3]·[5]는 관측 시 실사용 원문, [4]는 동일 판정의 재현 형태)

[1] PR 상태·auto-merge 상태:

gh pr view 1250 -R Archright/Axiom --json state,mergeStateStatus,autoMergeRequest --jq '{state, mergeStateStatus, autoMergeRequest: {enabledAt: .autoMergeRequest.enabledAt, mergeMethod: .autoMergeRequest.mergeMethod}}'

[2] 큐 타임라인(병합 후에도 큐 이벤트 관측·mergeQueueEntry는 라이브 창 전용):

gh api graphql -f query='{ repository(owner:"Archright", name:"Axiom") { pullRequest(number:1250) { mergeQueueEntry { enqueuedAt position state headCommit { oid } } timelineItems(first:20) { nodes { __typename ... on AddedToMergeQueueEvent { createdAt enqueuer { login } } ... on RemovedFromMergeQueueEvent { createdAt reason } ... on MergedEvent { createdAt } } } } } }' --jq '.data.repository.pullRequest | {mergeQueueEntry, items: [.timelineItems.nodes[] | select(.__typename != "IssueComment" and .__typename != "PullRequestCommit" and .__typename != "HeadRefPushedEvent") | {type: .__typename, createdAt, enqueuer: (.enqueuer.login // "-"), reason: (.reason // "-")}]}'

[3] required 5-context check-runs(per_page=100 필수 — Q19):

gh api 'repos/Archright/Axiom/commits/8c74275e4a0508ff2ebbc1988debb9637eb80532/check-runs?per_page=100' --jq '[.check_runs[] | select(.name=="admission-check" or .name=="bsec-integrity" or .name=="debt-registry-gate" or .name=="generation-acceptance" or .name=="axiom-operational-slice") | {name, conclusion, completed_at}]'

[4] merge_group 배치 판정(그룹 SHA = 큐 진입 시 기록값):

gh api 'repos/Archright/Axiom/actions/runs?event=merge_group&head_sha=ec2e90c30b01b24b6d902a54753386a7362c1bca&per_page=100' --jq '{total: .total_count, conclusions: [.workflow_runs[].conclusion]}'

[5] 양 ruleset 핀(docs PR은 핀 불변이 판정 조건):

gh api orgs/Archright/rulesets/25218071 --jq '{enforcement, pins: [.rules[].parameters.workflows[]? | {path, sha}]}'
gh api orgs/Archright/rulesets/23943917 --jq '{enforcement, pins: [.rules[].parameters.workflows[]? | {path, sha}]}'

## §6. 한계·불확실성

- **표본 1건** — 41s·20s는 실증 관측값이지 통계적 결론이 아니다(사전등록 §10: "표본
  1건 — 기록이 목적·일반화 금지"). 확대 판정은 별도 코호트 사전등록이 필요하다.
- 본 관측 구간(green→진입)은 #1166 공식 SLO(merge_group admission wall) **외 구간**이다 —
  SLO 코호트 불간섭 유지·합산 금지.
- 큐 처리→런 생성(DispatchDelay)·진입 지연의 공식 SLA는 미문서화(NOT DOCUMENTED) —
  본 값은 관측 참조치다.
- autoMergeRequest·mergeQueueEntry의 null 판독은 시점 의존(Q9 계열) — liveness 판정
  권위는 라이브 mergeQueueEntry·영속 타임라인 이벤트다.

**계보**: docs/evidence/l3_go_prereg_2026-11-03.md §10 F-4 → 본 관측 기록(후속 docs PR
이행). Track 1 시험은 본 기록으로 종결한다(운영 방식 실증 완료 — 이후 일반 PR의 표준
arm 경로는 docs/agents/operations.md:128 그대로).
