# Static gate set moved off the pole — a parallel lane inside the same required workflow

> **Status**: landing record. This document records a placement change and the measurement that
> motivated it. It changes no policy, no gate set, and no required context.
> **Created**: 2026-11-28
> **Baseline**: `main` at `c07d8e6f` (six merge-group heads sampled, `76714453 .. 4b5878c4`)

## §0. The problem this answers

`docs/spec/ci_admission_budget_contract.md` §5.2 bounds `T_admission` at a 600 s p50 and §5.3 states the
ceiling is never a verdict input, so "stay under ten minutes" is a distributional goal, not a per-run
assertion. Measured over six `merge_group` heads, the `merge_group` span was 361-436 s p50 373 s, and
`axiom-operational-slice` was the last finisher in four of the six. Anything added to that job is added
to the queue's wall clock in full.

PR #535 put the declared static gate set (`GATES_FAST` 10 + `GATES_STATIC` 14 = 24 targets) into that
job as a single serial step, because no required check executed the declared set. The placement was
correct on authority (a required check now enforced the set) and wrong on topology (a free-standing
detector was placed on the join). Measured cost of that step, same six heads:

| head | step `Enforce the declared static gate set` | producer job total |
|---|---|---|
| `97e874d7` | 110 s | 197 s |
| `4b5878c4` | 78 s | 239 s |
| `c8b65051` | 132 s | 265 s |
| `c07d8e6f` | 133 s | 271 s |

The step is 29-50 % of the job that decides the queue's wall clock, and it was the single largest
serial term in it.

## §1. The placement rule this implements

A workflow DAG costs the **maximum** of its parallel lanes; a serial step costs its **full duration**.
The two are not interchangeable, and which one applies is decided by `needs:` alone:

- A job with no `needs:` is a lane. Its duration is absorbed by the join's wait (`max`, not `sum`).
- A step inside the join, or a job on the join's own chain, extends the wall clock by its full duration.

`readiness-verdict` is that join in this workflow and is one of the seven required contexts. So a check
added to a lane costs `max(...)` and a check added behind the join costs `sum(...)`. That is the whole
rule, and it is now stated in the workflow header so the next addition does not have to rediscover it.

Which checks may become lanes is not a style question. A check qualifies only if nothing downstream
consumes its output. The 24 static gates are detectors: they write generated files and then assert
`git diff --exit-code` equality (`Makefile:478` for the topology guard, `tools/sync_decisions.nim:285`,
`tools/sync_certs.nim:205-209`), and the producer's later steps read none of it. `readiness-verdict`
does **not** qualify: it consumes the producer's artifacts byte-for-byte (manifest re-hash,
`.binary.sha256`, `buildSourceHash` join), so removing `needs: [axiom-operational-slice]` would compute a
different verdict, not a faster one.

## §2. The change

`.github/workflows/axiom-operational-slice.yml` (single file):

| site | before | after |
|---|---|---|
| producer job | 15 steps, gate step at #9 | 14 steps, gate step removed |
| `static-gates` | absent | new job, **no `needs:`**, no job-level `if:` |
| `readiness-verdict` | `needs: [axiom-operational-slice]` | `needs: [axiom-operational-slice, static-gates]` |
| `readiness-verdict` step 1 | (none) | `Dependency verdict` guard |

### §2.1 Why the verdict reaches a required context

`static-gates` is not a registered required context, and this change does not register one. It reaches
the required surface through `readiness-verdict`, which is:

```bash
r='${{ needs.static-gates.result }}'
if [ "$r" != "success" ]; then
  echo "BLOCKED: static-gates result is '$r' (required: success) ..."
  exit 1
fi
```

Positive equality, never a denylist. `needs.<job>.result` is one of `success | failure | cancelled |
skipped`, and only `success` means the gate set ran and passed. The GitHub documentation is explicit
that a skipped job **reports success** and does not block a merge even when it is a required check; the
hazard is a `skipped` conclusion on the required context itself, so an upstream job that never ran must
be converted into a red verdict by the join rather than filtered out of a non-success list. A concrete
acceptance query that excluded `skipped` and `neutral` from "non-success" would make exactly the two
conclusions that mean "never ran" invisible, so the acceptance check below asserts `success` positively
instead.

### §2.2 Why `static-gates` cannot be skipped

- No `needs:`: there is no dependency whose failure could skip it.
- No job-level `if:`: nothing selects it away. This is the file header's rule, applied to the new job.
- `cancel-in-progress: false` (`:27`): the concurrency group cancels whole runs, never one job.
- A step failing inside it makes its conclusion `failure`, never `skipped`; a cancelled run yields
  `cancelled`, which the guard also rejects.

The one `if:` in the new job is the pre-existing S5 eligibility gate (`steps.setup-tc.outputs.b-cache-hit
== 'true'`). That is not a gating conditional: on the false branch the job takes the cold-build path and
compiles the supply itself, which is the same contract the producer job has carried since S5 was
introduced. It never means "do not check".

### §2.3 Supply policy is duplicated, not simplified

`ci/checker.mk:493-506` states the `AXIOM_S5_BUILD_SKIP=1` contract: the **caller** must have passed the
B-verify (4 binary `--check-provenance` probes plus the 5-member SHA-256 fingerprint) before it may set
the flag, and a caller that sets it without verifying fails loudly rather than skipping quietly. A
"cheaper" variant for the new lane would be a second and weaker supply policy inside one workflow, so
the block is copied verbatim. It needs `bin/ax` (`check-scope-consistency` runs `bin/ax scope`), so the
supply block must precede the gate step; it does not need Lean, so there is no `lake build`.

## §3. Measured cost of the new lane

The lane is not free: it pays its own checkout, provisioning, and supply step. Decomposed from the same
six heads' step timings:

| term | value | source |
|---|---|---|
| checkout | 5 s (3-10) | step #2 |
| provisioning (`setup-axiom-toolchain`) | 28 s (24-46) | step #3 |
| `ci-compile` (S5 skip lane) | 9 s (5-9) | step #6 |
| `git restore build_metadata.json` | 1 s | step #8 |
| gate work | 102 s (78-133) | step #9 |
| job overhead | ~10 s | Set up / Post / Complete |
| **lane total** | **~155 s (116-208)** | |

Provisioning is not the dominant term (28 of 155 s), and `provision-scope: 'nim'` is not a lever: it
changes `a_key` (`action.yml:271`), which feeds `a_fp`, which feeds `b_key` (`:372`), so narrowing the
scope forces both cache layers to miss. The 24 gates shell out to 21-22 distinct `nim c` invocations, and
`check-cert-integrity` / `check-cert-integrity-fast` compile the **same** `bin/cert_integrity_gate`
output twice; that redundancy is inside the gate set's own definition and is deliberately not touched by
a placement change.

## §4. Predicted result

| term | before | after |
|---|---|---|
| producer | 271 s | ~138 s |
| `static-gates` lane | - | ~155 s |
| `readiness-verdict` starts at | 271 s | max(138, 155) = **155 s** |
| `readiness-verdict` | 158 s | 158 s |
| **workflow span** | **429 s** | **~313 s** |

`admission-gate` is the co-pole (308-397 s across the same heads), so the realized queue-level gain is
capped below the workflow-level gain. The prediction is therefore stated as: the `axiom-operational-slice`
span falls from 373 s median to no more than 340 s, and `static-gates` is observed running concurrently
with the producer rather than after it. Both are checked on real post-landing runs, not asserted here.

Because the lane is within ~17 s of the producer's shrunken length, the two are near-balanced by
construction. If the lane turns out longer than the producer by more than ~40 s, the next candidate to
move onto it is the R3 relocation measurement (11 s) or the L4 observation-reuse contract (4 s) - both are
independently-scoped detectors, and moving them rebalances the lanes without another rotation.

## §5. Invariant preservation

| invariant | how it is kept |
|---|---|
| required context set unchanged | seven contexts, same names, same producers; `static-gates` is not registered |
| `config/policy/merge_admission.json` unchanged | the two `axiom-operational-slice.yml` entries (`axiom-operational-slice`, `readiness-verdict`) still name jobs that exist |
| fail-closed preserved | the join's positive-equality guard turns any non-`success` result into a red required check |
| gate set unchanged | 24 gates, one definition (`Makefile:628`); no gate added, removed, or weakened |
| no new authority | no new workflow file, no new required check, no new policy file |
| `trust_surface_manifest.json` unchanged | the workflow was already a member; no path added or removed |

## §6. Not claimed here

- The 600 s figure is a p50 ceiling, not a per-run guarantee. A single 713 s `merge_group` observation
  exists in the baseline window and is decomposed in
  `docs/evidence/merge_queue_build_serialization_2026-11-27.md` §10.4 as a slow single job
  (`attest / build-base-artifacts` 374 s against a 76 s normal), not as a gate-count effect. This change
  does not address that class of outlier.
- The redundant double compile of `bin/cert_integrity_gate` inside the gate set is named above and left
  alone. It is a property of `GATES_STATIC`'s definition, and editing it would change what the gate set
  is, which is a different decision from where it runs.
- Post-landing acceptance is measured on real runs and recorded in the follow-up row; this document
  states the prediction and the mechanism, not the outcome.
