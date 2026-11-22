# Merge-group job inventory — 2026-11-22

Observed generation: `5a5fbfd760d0105314e44dfdc8c64e61118c4fe5` (`5a5fbfd7`), PR #322, admission-gate run [`44902266464`](https://github.com/Archright/Axiom/actions/runs/44902266464) (`failure`). This is the failing generation named in the work order. It dispatches all 8 merge_group workflows, so the 44-job population is complete.

The machine-readable inventory is [`jobs.json`](jobs.json). It records, for every job: `name`, `workflow`, `workflowPath`, `proposition`, `evidenceArtifact`, `consumer`, `startedAt`, `completedAt`, `runnerSeconds`, `executed`, and (for skipped jobs) `skipReason`.

## Measured counts

| workflow | jobs | executed | skipped | executed runner-seconds |
|---|---:|---:|---:|---:|
| admission-gate (`admission-gate-v2.yml`) | 26 | 14 | 12 | 819 |
| publication-integrity | 10 | 10 | 0 | 1027 |
| probe-merge-queue | 2 | 1 | 1 | 8 |
| axiom-operational-slice | 2 | 2 | 0 | 406 |
| bsec-integrity | 1 | 1 | 0 | 69 |
| generation-acceptance | 1 | 1 | 0 | 15 |
| debt-registry-gate | 1 | 1 | 0 | 81 |
| observer-manifest-consistency (`observation.yml`) | 1 | 1 | 0 | 78 |
| **total** | **44** | **31** | **13** | **2503** |

The measured split is **31 executed / 13 skipped**, exactly the earlier count. No discrepancy needs a separate denominator.

Method: enumerate `actions/runs?head_sha=5a5fbfd760d0105314e44dfdc8c64e61118c4fe5` (8 runs), then call `actions/runs/<run_id>/jobs?per_page=100&filter=latest` for each. `executed = conclusion != "skipped"`; `runnerSeconds = max(0, completed_at - started_at)` for executed jobs. Re-running those commands reproduces the table.

## Skipped jobs

The 13 skipped jobs are definitions whose `if:` condition was false for this venue/stage:

- `probe-judge` (non-merge_group only)
- `anchor-resolve` (pull_request only)
- `gateway / ci-bootstrap`, `gateway / candidate-build-arm`, `gateway / gateway-shard`, `gateway / gateway-identity-gate`, `gateway / proof-reconcile` (selection succeeded without bootstrap; SL-09 scope false)
- `mint-prepare / publish`, `mint-publish / prepare` (callee stage mismatch)
- `verdict / admission-independents`, `verdict / go-critical-lane`, `verdict / go-critical-rollup`, `verdict / build-base-artifacts` (attest-stage-only jobs inside the verdict call)

**Skipped jobs consume zero runner-seconds and are reported as success when required** — a skipped required check does not block a merge. Deleting skipped jobs is therefore **not** a throughput optimization: their runner-seconds are already 0, and removing the definitions would delete conditional paths used by other venues/stages without reducing generated run time.

## Duplicate-computation candidates (nothing removed)

Removal criterion: **same proposition + same input identity + same evidence meaning, with J1–J4 all PASS.** No job was removed or changed.

- `CAND-1` — `attest / build-base-artifacts` vs `axiom-operational-slice`. Both build verifier binaries from the same B closure and the 2026-11-03 census measured an exact B-cache hit. Criterion not met on current evidence: same build input, different propositions (admission witness vs operational acceptance) and different evidence meaning; J3 has exact-hit evidence, J1/J2/J4 are not evaluated.
- `CAND-2` — `attest / admission-check` vs `verdict / admission-check`. Same reusable workflow definition, but the stage inputs are mutually exclusive: attest runs witness steps, verdict runs the predicate. The 13 `verdict/*` skips are that stage gate, not a second execution.

Examined pairs that are **not** candidates: bsec parse-poison lint vs publication `script-scan` (different propositions); generation-acceptance vs gateway `select` (acceptance vs test-scope selection); `observe` vs App trust surface (manifest.d consistency vs trust-surface blob equality); license-scan shards vs `license-scan` (partition + rollup, not recomputation).

## Limits

- Propositions/consumers come from the workflow definitions at the pinned callee SHAs and repository contracts; this is not a claim that every step ran.
- The generation's other failure check-runs (publication-integrity, script-scan) are recorded in `../app_verdict_attribution_2026-11-21/merge_group/summary.json`; this inventory does not attribute their causes.
- Skipped timestamps are platform skip markers, not execution intervals; skipped runner-seconds are defined as 0 rather than derived from them.