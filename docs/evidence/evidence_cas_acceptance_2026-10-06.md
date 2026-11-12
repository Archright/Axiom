# Evidence CAS acceptance — production MISS/HIT observation + HIT-path wall (2026-10-06)

## What this record is

Terminal-outcome record for the identity-keyed evidence reuse slice (Axiom
#493, SL-15 promotion). It registers the contract's two paths observed live
in production on main — **CAS MISS** (produce + store + exactly-once
append) and **CAS HIT** (reuse + rebind, no verification re-execution) —
the first HIT-path landing wall measured against the ≤ 8 min target, and
the two activation incidents (both fail-closed, both fixed, both landed).
Baseline wall record: `evidence_cas_baseline_2026-10-06.md`; activation
choreography: `evidence_cas_rollout_timeline_2026-10-06.md`.

## Production observation — both paths, one evidence key

Subject: PR #496 (incident-2 record + fix documentation). The
`pull_request` admission run produced the evidence; the `merge_group`
admission run for the same merge input reused it. Both log lines below are
verbatim job-log extractions (script-echo lines excluded).

### MISS — produce + store (run `37425228736`, `pull_request`, started 06:42:11Z)

`attest / admission-check` job log, 06:48:53Z:

```
AXIOM_EVIDENCE_CAS: MISS — produced + stored record 708295da02c2
```

`mint-publish / publish` job log, 06:50:00Z:

```
MINT_EVAPPEND: OK — evidence record appended (key 708295da02c2, append exactly-once: 1)
```

The ledger side-ref advanced with the append:
`refs/heads/axiom/evidence-cas` → `85157e9c…`.

### HIT — reuse + rebind (run `37426625460`, `merge_group`, 06:56:29→07:10:22Z)

`attest / admission-check` job log, 07:03:16Z:

```
AXIOM_EVIDENCE_CAS: HIT — reused + rebound record 708295da02c2 (evidence bytes re-verified)
```

Same evidence key `708295da02c2`. The kernel verification did **not**
re-execute on the merge_group run: the stored evidence bytes were
re-verified and bound to the current subject, admission passed, and PR #496
landed as merge commit `b2a979b47` (07:10:49Z).

## HIT-path wall #1 (run `37426625460`, `merge_group`) — 13m53s

Job timings from the Actions API (all UTC, 2026-10-06):

| job | start | end | wall |
|---|---|---|---|
| attest / build-base-artifacts | 06:56:32 | 07:01:44 | 5m12s |
| gateway / select | 06:56:33 | 06:57:30 | 57s |
| attest / admission-check (CAS **HIT** at 07:03:16) | 07:01:47 | 07:03:20 | 1m33s |
| mint-prepare / prepare | 07:03:24 | 07:03:53 | 29s |
| mint-publish / publish | 07:03:57 | 07:04:35 | 38s |
| verdict / admission-check | 07:04:38 | 07:10:16 | 5m38s |
| admission-check (aggregate) | 07:10:19 | 07:10:22 | 3s |
| **run total** | 06:56:29 | 07:10:22 | **13m53s** |

Baseline (pre-slice, #493 merge_group run `37409364909`): 12m28s.

## Honest accounting vs the ≤ 8 min target

The realized HIT saving is the attest share that evidence reuse eliminates:
1m35s → 1m33s (well under 1 minute) — consistent with the slice's own
prediction (0.5–1 min): kernel verification was a minority of the wall.
The ≤ 8 min target is **not met** by wall #1 (13m53s), and the dominant
costs sit outside this slice's scope:

- `attest / build-base-artifacts`: 5m12s — the B-build, serial before attest.
- `verdict / admission-check`: 5m38s, of which a 5m18s no-output window
  (07:04:56→07:10:14) is the `ax merge --dry-run` admission predicate
  evaluation.

Neither is an evidence-reuse factor. Shrinking them belongs to the
explicitly out-of-scope gate/policy reduction and verdict restructuring.
Follow-up candidates (separate slices): investigate the verdict predicate's
5m18s no-output window; overlap or shard the B-build.

## Activation incidents (fail-closed held under real faults)

1. **Token ingress (first post-rotation run)**: the attest step lacked
   `GITHUB_TOKEN` → ledger side-ref reads failed → run failed (no false
   PASS). Fix #494 (`5af2afd6e`): token injection at the attest step +
   TWS/manifest pin re-binding to the rotated callee blob.
2. **Empty-tree ledger root (SL-15)**: `/git/trees` 404s on a fresh ledger
   root commit (observed run `37417742964`) → first append failed
   fail-closed. Fix #495 (`f022abb1e`): `fetchTipTree` resolves the tip
   commit to its tree and normalizes `EmptyTreeSha` to a synthetic empty
   listing; non-empty 404s still fail closed. Record:
   `evidence_cas_empty_root_incident_2026-10-06.md`.

Both incidents failed closed — no unverifiable PASS — and both landed with
their own admission runs green. A duplicate follow-up PR (#497) proposing
the same empty-tree fix was closed as superseded by #495.

## Terminal outcome accounting

| contract item | status | evidence |
|---|---|---|
| MISS path produces + stores evidence in production | met | run `37425228736`, key `708295da02c2`, exactly-once append |
| HIT path reuses + rebinds without re-execution | met | run `37426625460`, same key, admission PASS, landed |
| fail-closed on fault (absence / ingress failure) | held | incidents 1–2 (failed, then fixed) |
| re-attempt lands without re-verification | met | #496 merge_group → merge commit `b2a979b47` |
| HIT-path wall ≤ 8 min (P95 of 3) | **not met (walls so far)** | wall #1 = 13m53s; dominated by out-of-slice B-build + verdict predicate |

## Reproduction

```sh
# run/job timings
gh api repos/Archright/Axiom/actions/runs/37426625460/jobs \
  --jq '.jobs[] | [.name,.conclusion,.started_at,.completed_at] | @tsv'
# CAS gate lines (job logs; exclude script-echo lines)
gh api repos/Archright/Axiom/actions/runs/37426625460/jobs --jq '.jobs[]|select(.name=="attest / admission-check")|.id' \
  | xargs -I{} curl -sL -H "Authorization: token $(gh auth token)" \
      "https://api.github.com/repos/Archright/Axiom/actions/jobs/{}/logs" \
  | grep -a "AXIOM_EVIDENCE_CAS\|MINT_EVAPPEND" | grep -av $'\033\[36;1m'
```
