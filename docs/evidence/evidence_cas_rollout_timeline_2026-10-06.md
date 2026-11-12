# Evidence CAS rollout timeline — callee generation boundaries (2026-10-06)

## What this record is

The activation record of the identity-keyed evidence reuse slice (Axiom
#493): which callee generation the org required workflow executed at each
point of the day, and why the pins moved. All times UTC. This is the
companion to `evidence_cas_baseline_2026-10-06.md` (which carries the
landing-latency baseline and the first-run incident).

## Callee generation timeline

| time | org change | admission-check pin | certificate-mint pin | state |
|---|---|---|---|---|
| — 03:49 | — | `692056d1` | `db9afe5a` | pre-SL15 (NO-FIRE) |
| 03:49 | `.github` #50 (`5e295ea3`) | `ac8abb407` | `ac8abb407` | SL-15 armed, attest wiring defect |
| ~04:37 | `.github` #51 (`9e7af82f`) | `692056d1` | `db9afe5a` | temporary rollback (pre-SL15) |
| after #494 | `.github` #52 (`fa35775e`) | `5af2afd6e` | `5af2afd6e` | SL-15 re-armed, wiring fix included |
| 09:02:58 | `.github` #55 (`939e494`) | `692056d1` | `db9afe5a` | emergency rollback — axiom-b cache evicted 07:25Z, single-writer publisher, no re-seeding path; job2 attest died on every PR |
| 10:07:00 | `.github` #56 (`aadce265`) | `22ae6bd3` | `22ae6bd3` | re-armed on the provenance-fix generation (#502: executed-member reduction, key v1 unchanged) |

`runner-pool-acceptance.yml` pin (`7b14e5c6`) was never moved — untouched
by the slice.

## Axiom main side

- `ac8abb407` — PR #493, the slice itself (Evidence CAS + provisioning
  slim). Its own runs were NO-FIRE (base predates the promotion).
- `5af2afd6e` — PR #494, the witness-only attest `GITHUB_TOKEN` wiring fix
  + TWS/manifest atomic rebind (epoch gate enforced) + this evidence
  family. Landed through the documented rollback choreography after the
  first post-#50 production run failed fail-closed (see baseline record).

## Why the rollback was the sanctioned path

The org wrapper executes the callee from its SHA pin, so a fix carried on
a PR branch cannot heal that PR's own checks — the fix must reach main
first, which requires a green admission on a generation that predates the
fix. Rolling the pins back to the pre-SL15 generation restored exactly the
NO-FIRE admission state that held before activation; no required check was
bypassed, no check was suppressed, and the forward rotation completed the
choreography once the fix was on main.

## Observation status at record time

This PR is the first landing under the re-armed generation. Its
`pull_request` run is a fresh semantic identity (expected MISS — produce +
store), its `merge_group` run is the same tree (expected HIT — reuse +
rebind without kernel re-execution). Results are recorded in the follow-up
observation record.
