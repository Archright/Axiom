# Rearm follow-up: pagination, trigger policy, and observation evidence (2026-11-22)

Observation time: 2026-11-22T11:00Z-11:50Z. Repository: `Archright/Axiom` (public, GitHub Free).
Canonical main at observation: `0f9c4a3de96c4137fa3852e94829c34e272c4966`.

This record backs three changes landed together: (1) page-completeness for every list
read in `merge-queue-rearm.yml`, (2) the rename-aware trust-surface gate plus a truncation
guard (DEBT#565), and (3) the repository Actions event policy that keeps the
`pull_request_target` wake-up alive after 2026-12-02.

## 1. Landing state of the previous slice (recap, verified)

```
gh pr view 369 --json state,mergeCommit,headRefOid
  state=MERGED  mergeCommit=0f9c4a3d...  headRefOid=c05387be...

gh api repos/Archright/Axiom/actions/runs/45013627225 \
  --jq '{event,head_sha,status,conclusion}'
  event=merge_group  head_sha=0f9c4a3d...  status=completed  conclusion=success

gh api repos/Archright/Axiom/actions/runs/45013627028/jobs \
  --jq '.jobs[]|select(.name|test("script-scan|publication-integrity"))|"\(.name)=\(.conclusion)"'
  script-scan=success  publication-integrity=success
```

The `publication-integrity` run above is `event=merge_group` on the landing SHA, so the
landing-only `script-scan` leg executed (it is `skipped` on the PR venue by design) and passed.

## 2. Rearm population at observation (60 runs)

Command:

```
for r in $(gh run list --repo Archright/Axiom --workflow merge-queue-rearm.yml \
             --limit 60 --json databaseId --jq '.[].databaseId'); do
  gh run view "$r" --repo Archright/Axiom --log 2>/dev/null | grep -oE '\{"rearm".*' | head -1
done
```

Result: 60/60 runs produced a parseable verdict line. `action=arm` count: **0**.
Class: `UNKNOWN` for all 60 (no `TRANSIENT`/`PERMANENT` sample existed in this window).
Evidence-line distribution:

```
30x  pr-state:state=MERGED
12x  run-resolution:in-progress
 6x  evidence:no-anchor
 3x  trust-surface:intersection
 3x  run-resolution:conclusion=success
 2x  pr-state:state=CLOSED
 1x  required-check:success            (canary PR #379, workflow_run[merge_group])
 1x  event-normalization:wf_event=pull_request   (fail-closed refusal)
```

Post-landing samples (runs created after 2026-11-22T10:51:46Z): 6, all `action=no-arm`.
This is below the `n >= 20` statistical bar, so operational stability is `INCOMPLETE`,
not proven. The functional acceptance of the two wake-ups is separate and was observed
directly (see the canary record in the previous slice).

## 3. `gh` pagination shapes (measured with gh 2.102.0)

Array endpoint, many pages:

```
gh api --paginate "repos/Archright/Axiom/issues?state=all&per_page=2" > /tmp/pg_arr.json
jq -c 'length' /tmp/pg_arr.json     -> 379      (one merged, valid JSON array)
```

Array endpoint, one page:

```
gh api --paginate "repos/Archright/Axiom/labels?per_page=100" | jq -c 'type,length'
  "array" 12
gh api --paginate "repos/Archright/Axiom/labels?per_page=100" --jq '.[].name' | wc -l
  12
```

Object endpoint, six pages:

```
gh api --paginate "repos/Archright/Axiom/actions/workflows?per_page=5" > /tmp/pg_obj.json
jq -c 'if type=="array" then ["ARRAY",length] else ["OBJECT",keys] end' /tmp/pg_obj.json
  ["OBJECT",["total_count","workflows"]]
jq -c '.workflows|length' /tmp/pg_obj.json
  5                       <-- total_count is 28; only ONE page survives

gh api --paginate --slurp "repos/Archright/Axiom/actions/workflows?per_page=5" \
  | jq -c '[length, (.[0]|type), (.[0].workflows|length)]'
  [6,"object",5]          <-- 6 page objects; flatten with .[] | .workflows[]
```

`--paginate --slurp` and `--jq` are mutually exclusive:
``the `--slurp` option is not supported with `--jq` or `--template` ``.

## 4. Sites changed

| Site | Before | After | Consequence of the cap (measured) |
|---|---|---|---|
| PR labels, 4 reads (marker, budget, pre-arm re-read, intent) | `gh api ...?per_page=100 --jq` | `gh api --paginate ...` | **wrong verdict** if a >100-label PR ever appears; repo has 12 labels today |
| Check-run annotations | `gh api ...?per_page=100` | `gh api --paginate ...` | a `PERM_*` title beyond page 1 was invisible to the PERMANENT guard |
| Run jobs | `gh api ...?per_page=100` | `gh api --paginate --slurp` + `.[] | .jobs[]?` | missing failure anchors; bare `--paginate` here was silent truncation |
| PR files (trust surface) | `.filename` only, 40-page cap | `.filename` + `.previous_filename`, 3000-file completeness guard | a rename out of a protected path escaped the intersection |

Not changed, with reasons: the `merge_group` runs scan is bounded at 10 x 100 by an
explicit comment and resolves to UNKNOWN on a miss (fail-closed); the check-run read
already used `--paginate --slurp`; GraphQL single-PR fields have no connection to
paginate.

Verification:

```
bash tools/ci/validate_workflow_shell.sh
  SUMMARY: run blocks checked=277 failures=0 lane-guard violations=0
python3 <bash -n over every run: block>
  steps=14 syntax_failures=0
make test-fast-one T=tests/ci/test_merge_queue_rearm.nim
  37 [OK], 0 failed
```

## 5. Actions event policy (the 2026-12-02 default block)

Primary source: GitHub changelog 2026-11-02, "pull_request_target blocked by default
December 2" - public repositories, Free/Team/Enterprise Cloud, brownouts on 2026-11-09 and
2026-11-16 (16:00-18:00 UTC). No rearm run exists inside either brownout window, so no
lost event was observed; the deadline is still real.

Pre-mitigation state:

```
gh api repos/Archright/Axiom/actions/policies --jq .total_count        -> 0
gh api orgs/Archright/actions/policies --jq '[.policies[].conditions.repository_id]'
  all conditions target repository_id 1182104685; Axiom is 1454952493
grep -l pull_request_target .github/workflows/*.yml
  merge-queue-rearm.yml    (generation-acceptance.yml mentions it only in prose)
```

Post-mitigation state (repository policy, created via
`POST /repos/Archright/Axiom/actions/policies`):

```
id=16826  name=allow-merge-queue-rearm-events  source_type=Repository  enforcement=active
conditions.workflow_path.include = [".github/workflows/merge-queue-rearm.yml"]
rules[0] = restrict_action_events { allowed_events: [pull_request_target, workflow_run, workflow_dispatch] }

gh api "repos/Archright/Axiom/actions/policies?has_parents=true" --jq .total_count
  1
```

`allowed_events` is an allowlist, so all three triggers of the covered workflow are listed.
Allowing only `pull_request_target` would have blocked the `workflow_run` second wake-up and
the manual `workflow_dispatch` path.

## 6. Debt registration

`DEBT#565` was registered and closed in `data/debt_registry.json`
(category `Theater/Unenforced Claim`, source `theater_audit`, binding `registry_disposition`):
the condition-5 gate matched only `.filename` and read a page-capped listing as complete.
Projections were regenerated (`bin/debt_engine --codegen`) and the ledger synced
(`bin/debt_engine --sync-budget`).

```
bin/debt_engine --validate
  Checks: 1843 total, 1843 passed, 0 failed. Metric evaluation: 6 PASS, 0 DRIFT.
bin/debt_integrity_gate     (run without the gitignored local sidecar, i.e. CI conditions)
  nimtry -- Active Violations: (unmeasured; nimtry not run yet)
  All 23 open debts have code markers. PASS.
```

Local note: with the gitignored `data/nimtry_live_count.json` present (4383), the gate fails
the ratchet at 4381. CI never produces that sidecar, so CI reports "unmeasured" and passes.
The sidecar is a local artifact, not a repository state.

## 7. Residual UNKNOWN (not asserted)

| Item | Status | How it would be settled |
|---|---|---|
| Does a rerun (`run_attempt` 2) emit a second `workflow_run` completed event? | UNKNOWN - no attempt-2 run exists in the latest 100 runs (all events) or latest 100 merge_group runs; every observed run is attempt 1 | observe one attempt-2 run and its wake-up |
| Positive arm path (`action=arm`) on the current revision | UNVERIFIED - `REARM_APP_PRIVATE_KEY` is unprovisioned; the workflow emits `token-missing` and no-arms | deposit the key, then observe one real arm |
| Operational stability of the rearm automation | INCOMPLETE - 6 post-landing samples, `n >= 20` not met | accumulate samples; no code change |
| Exact `enablePullRequestAutoMerge` permission floor | DOCUMENTED, NOT EMPIRICALLY VERIFIED - current docs no longer expose the REST endpoint (gh uses GraphQL); `pull_requests: write` is the inferred floor and matches both the App's granted permissions and the mint request | one real arm with the minted token |

## 8. Why these facts do not change merge authority

None of the changes here alters the merge decision: the required contexts remain seven,
`admission-check` remains bound to App `5795152`, both rulesets stay `active` with
`bypass_actors: []`, and the workflow still runs trusted code only (no candidate checkout).
The pagination and trust-surface changes make an existing gate *more* complete; the event
policy restores an event delivery path that the platform is about to block by default.