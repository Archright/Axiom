# Merge Queue Dequeue Reason (GraphQL-only field)

**Claim.** The merge queue removal reason is not exposed by the REST
issue-timeline API, but it IS exposed by GraphQL
`RemovedFromMergeQueueEvent.reason`.

## Query (working example)

```
gh api graphql -f query='
query { repository(owner:"Archright", name:"Axiom") {
  pullRequest(number:322){ timelineItems(last:20, itemTypes:[REMOVED_FROM_MERGE_QUEUE_EVENT, ADDED_TO_MERGE_QUEUE_EVENT, MERGED_EVENT]){
    nodes{ __typename ... on RemovedFromMergeQueueEvent { createdAt reason beforeCommit{oid} actor{login} } ... on AddedToMergeQueueEvent { createdAt } ... on MergedEvent { createdAt } } } }
} }'
```

## Measured evidence (2026-11-21, PR #322)

- `AddedToMergeQueueEvent 12:06:18Z`
- `RemovedFromMergeQueueEvent 12:16:31Z reason=failed_checks beforeCommit=2609f6081d0a... actor=github-merge-queue`
- `AddedToMergeQueueEvent 12:21:25Z`
- `RemovedFromMergeQueueEvent 12:27:23Z reason=failed_checks beforeCommit=478f27d27e1f... actor=github-merge-queue`
- `AddedToMergeQueueEvent 12:40:29Z`
- `MergedEvent 12:47:45Z`
- `RemovedFromMergeQueueEvent 12:47:45Z reason=merged beforeCommit=be6c14c2...`

`merged` also arrives as a `RemovedFromMergeQueueEvent`, so a consumer must
switch on `reason`, not on the event type alone.

## Observed `reason` values

`failed_checks`, `merged`. Any other or missing value is UNKNOWN: fail closed.

## Consequence for the rearm workflow

`merge-queue-rearm.yml` currently infers the situation from merge_group run
state, and its header states that the dequeue reason is not API-visible. That
statement is outdated: the reason is available. This document changes no
behavior; it only records the fact. The rearm behavior fix is a separate
planned change.

## Limitations

- GraphQL requires pull-request read scope.
- Timeline items are paginated; use `pageInfo`.
- `reason` has no documented enum, so only the observed values are asserted
  here.
- `beforeCommit` is the current merge-group SHA at removal, and removal happens
  at group level, not per-PR inside the group.

## Related

- `docs/spec/github_delegation_residuals.md`
- `.github/workflows/merge-queue-rearm.yml`
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue

## Re-arm path observation (2026-11-22) — REST null is not absence

`merge-queue-rearm.yml` does not consume a dequeue reason at all: it classifies
TRANSIENT/PERMANENT from the merge_group check-run annotations, and its header
still states that the dequeue reason is not API-visible. The repository's
`removed_from_merge_queue` sampling is the CI census, not the re-arm path
(`data/ci_optimization/merge_queue_concurrency_2026-11-21_after_n10/summary.json`,
`observationGaps`): 33 events were sampled with

```
gh api "repos/Archright/Axiom/issues/<pr>/timeline?per_page=100" --paginate
```

and **all 33 carried no reason field** (all null). That null is a property of
the sampled REST event shape; it does **not** prove that the API has no reason,
and it says nothing about the GraphQL field.

기존 사용 경로에서는 사유를 관측하지 못했으며, GraphQL `RemovedFromMergeQueueEvent.reason` 필드의 실제 값 가용성을 추가 검증해야 한다.

### Verification of the GraphQL field (2026-11-22, read-only)

The obligation above was discharged once for this record with an authenticated,
read-only `gh api graphql` query (PR #322):

```
gh api graphql -f query='
query { repository(owner:"Archright", name:"Axiom") {
  pullRequest(number:322){ timelineItems(last:20, itemTypes:[REMOVED_FROM_MERGE_QUEUE_EVENT, ADDED_TO_MERGE_QUEUE_EVENT, MERGED_EVENT]){
    nodes{ __typename ... on RemovedFromMergeQueueEvent { createdAt reason beforeCommit{oid} actor{login} } ... on AddedToMergeQueueEvent { createdAt } ... on MergedEvent { createdAt } } } }
} }'
```

Observed result:

- `RemovedFromMergeQueueEvent 2026-11-21T12:16:31Z reason=failed_checks beforeCommit=2609f6081d0a… actor=github-merge-queue`
- `RemovedFromMergeQueueEvent 2026-11-21T12:27:23Z reason=failed_checks beforeCommit=478f27d27e1f… actor=github-merge-queue`
- `RemovedFromMergeQueueEvent 2026-11-21T12:47:45Z reason=merged beforeCommit=be6c14c2602e… actor=github-merge-queue`

Status: **VERIFIED** for this sample — the same query and values as the
2026-11-21 measurement above. The observed value set remains an observation, not
a documented enum; any other or missing value is UNKNOWN (fail closed). This
record changes no behavior: the re-arm path already uses GraphQL for PR state and
merge-queue entry state (`isInMergeQueue`, `mergeQueueEntry{state}`) but never
queries `RemovedFromMergeQueueEvent.reason`, and the re-arm behavior fix is a
separate change.
