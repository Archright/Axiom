# N-way merge-queue convergence acceptance — 2026-10-06

## Question

Does the N-way convergence invariant hold with `strict_required_status_checks_policy=false` (freshness authority = GitHub merge queue alone, ADR-0027 P5): every landing candidate verified against its actual landing prefix, zero human branch updates, zero non-merge queue removals?

## Context

- Subject: Archright/Axiom `main` ruleset 20303214; flip executed 2026-10-05T14:59:29Z (one-field diff, pre/post snapshot verified: strict true→false, all other fields byte-identical, merge_queue and required context `admission-check` unchanged, enforcement active, bypass_actors []).
- Baseline main tip at flip (L0): `7a82d9774dbd84c6aac0aa10946bf178fe9b40bc` (merge of PR #491, the ADR-0027 P5 decision record).
- Canary: 4 concurrent PRs (#487-#490), each one commit adding `docs/evidence/canary_wN.md`, branched off the same base, armed 2026-10-05T15:00:07-20Z with `gh pr merge --auto --match-head-commit <head>`.
- Prior baseline: 19 `Merge branch 'main' into` commits in the preceding 14 days under strict=true.

## Procedure

Pre-checks: queue `entries.totalCount == 0`; PR #478 `autoMergeRequest == null`. Flip via `gh api -X PUT repos/Archright/Axiom/rulesets/20303214` (single-field diff). Arm ×4 concurrent. Observation: ~60s batched GraphQL polling (queue entries + PR timelines incl. removal `reason`), `git ls-remote` watcher on `refs/heads/gh-readonly-queue/main/*` at 15s granularity, `commits/<sha>` parent verification, rule-suite reads on `refs/heads/main`.

## Result (canonical, machine-observed)

| WS | PR | L_k (merge commit) | parents (verified) | Added→Merged (Z) | group ref (baked base) | group runs |
|---|---|---|---|---|---|---|
| W1 | #487 | `d93745b453c9e56f4c37b8b8ed9fb7defaf84d6d` | [L0, H1] ✓ | 15:00:09→15:14:15 | `pr-487-7a82d977…` (==L0) | 3× success |
| W2 | #488 | `c75fe685af9d2fe345859dc9e6b9867409798c14` | [L1, H2] ✓ | 15:00:12→15:15:15 | `pr-488-d93745b4…` (==L1) | 3× success |
| W3 | #489 | `f55a2471282bd773c438759550f461c9c61e181f` | [L2, H3] ✓ | 15:00:16→15:29:38 | `pr-489-c75fe685…` (==L2) | 3× success |
| W4 | #490 | `932ea18f2d8e78eb68b0b4f94eaad4c303811527` | [L3, H4] ✓ | 15:00:20→15:29:39 | `pr-490-f55a2471…` (==L3) | 3× success |

H1..H4 = `f47d8c4a…`, `a50d1801…`, `bcc2e0be…`, `af146085…` (full SHAs in git history of the probe branches). Enqueue→L4 total: 29m19s. Recovery budget: unused.

## Metrics

- Non-merge queue removals: **0/4** — all `RemovedFromMergeQueueEvent.reason == "merged"`.
- Human branch updates since flip: **0** — `commits?sha=main&since=2026-10-05T14:59:29Z` = exactly the 4 queue landings, zero "Merge branch 'main' into" subjects; all 4 headRefOids identical to arm-time; zero `HeadRefForcePushedEvent`.
- Prefix-exact validation: **proven prospectively** — each `gh-readonly-queue/main/pr-<N>-<sha>` ref was created before its baked-in sha existed on main, and each later became the actual merge commit verbatim (40-hex equality L1..L3; pr-487 base == L0). Ref targets chained identically (pr-488 head == L2, pr-489 head == L3, pr-490 head == L4). All refs deleted after landing (final ls-remote count 0).
- Rule-suite chain on `refs/heads/main`: unbroken pass chain L0→L4, actor wintrover, before→after = L_{k-1}→L_k for all four.

## Classification

Verified (for the declared slice: 4 concurrent marker-only workstreams, ALLGREEN queue, MERGE method, max_entries_to_merge=1).

## Non-Conclusions

Does not validate: interleaved foreign PRs, failed-check/dequeue-recovery paths, HEADGREEN grouping, batch merges (max>1), or the direct-PUT landing paths (`ax landing`, actuator) which lose the merge-time backstop under strict=false. `slice_catalog.nim` re-scope (epoch-gate deferral) and `merge_admission.json` v1.11.0 (surface-policy re-registration dependency) remain recorded follow-ups; the decision substance lives in ADR-0027 P5 (PR #491).

## Evidence pointers

Merge-group runs on `gh-readonly-queue/main/pr-<N>-*` (all success); rule-suites API `refs/heads/main`; PR timelines #487-#490; probe branches `probe/nway-canary-w1..w4` (heads unchanged since arm).
