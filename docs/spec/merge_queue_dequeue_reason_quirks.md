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
