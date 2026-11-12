# Mint witness identity cutover — production observation (2026-10-04)

## What was cut over

The witness artifact identity moved from the unsuffixed name to the
attempt-scoped name, and the legacy twin is gone on both sides of the
boundary:

| side | before | after |
|---|---|---|
| producer (Axiom `.github/workflows/admission-check.yml`) | `admission-check-<head>` (transition twin) **and** `admission-check-<head>-<attempt>` | `admission-check-<head>-<attempt>` only |
| consumer (Axiom `.github/workflows/certificate-mint.yml`) | resolved the unsuffixed name | resolves `admission-check-<candidate head>-<run_attempt>` only |

Chain that produced this state:

- Archright/Axiom#459 — deterministic witness identity (attempt-scoped upload, `overwrite: true`)
- Archright/Axiom#461 — mint consumer switched to `admission-check-<candidate head>-<run_attempt>` (ADR-0027 P2 explicit amendment)
- Archright/Axiom#462 — CI authority singularity
- Archright/Axiom#463 — legacy witness twin dropped; epoch/TWS pins advanced to blob `a863190d…` (merged 2026-10-04T11:35:09Z, merge `87df2df5d997cdd15a9c72dbc5db8d87ba53e417`)
- Archright/.github#46 — org `admission-check` callee pin rotated to `87df2df5…` (merged 2026-10-04T11:36:21Z)

## Why the pin rotation is a precondition, not a follow-up

Axiom PR #463 ran **green on attempt 2 while still emitting two witness
artifacts**, because the org ruleset workflow was pinned to the pre-#463
copy of `admission-check.yml`, in which the transition twin was still live:

```
run 37197572520, attempt 2 — artifacts created 2026-10-04T11:23:53Z/54Z
  admission-check-9a70c8fb7bc838230c2b2ff6d9da55ad9db74165-2   (attempt-scoped)
  admission-check-9a70c8fb7bc838230c2b2ff6d9da55ad9db74165     (legacy twin)
```

The mint resolved only the attempt-scoped name, so `MINT_ART: OK` held and
no `found 2` fired. The duplicate was inert for the consumer but is still a
second identity on the run, so the observation below is taken under the
rotated pin.

## Observation

Subject: Axiom PR #465 (`docs/mint-identity-cutover-2026-10-04`), head
`2e5871fa04eca7c95e97037bfb872573c5a9d528`, base `87df2df5…` (#463).

Runs (all `pull_request` event, actor `wintrover`):

| run | workflow | what |
|---|---|---|
| 37199503298 | landing-integrity | pass, attempt 1, unchanged by re-run |
| 37199503329 | repository-surface | pass, attempt 1, unchanged by re-run |
| 37199503612 | admission-gate | attempt 1 `failure` (by design), attempt 2 `success` |

`admission-gate` run 37199503612: created 2026-10-04T11:39:59Z, attempt 1
started 11:39:59Z, attempt 2 started 11:50:06Z, completed 12:00:40Z.

### Attempt 1 — the designed bootstrap (mint green, admission reads one attempt late)

| job | conclusion |
|---|---|
| `admission / build-base-artifacts` | success |
| `gateway / select` | success |
| `mint-prepare / prepare` | success |
| `mint-publish / publish` | success |
| `admission / admission-check` | **failure** |
| `admission-check` (aggregator) | **failure** |

Verdict, verbatim from `admission / admission-check` job 111428813024 at
2026-10-04T11:48:09Z:

```json
{"prNumber":465,"headSha":"2e5871fa04eca7c95e97037bfb872573c5a9d528","baseSha":"87df2df5d997cdd15a9c72dbc5db8d87ba53e417","verdict":{"result":"mergeAborted","reasonCode":"NO_CERT","reason":"no subject-continuity certificate for this PR/subject — certified admission requires one (re-attest)"},"qualification":"UNSPECIFIED","rotationCheck":null,"rotationNote":"closure inputs absent (AXIOM_DERIVED_H_PATH/AXIOM_DERIVED_B_PATH/AXIOM_PIN_H_PATH) — rotation Pass skipped"}
```

The producer half succeeded on attempt 1 — `mint-prepare / prepare` job
111429431122, 2026-10-04T11:48:42Z:

```
MINT_ART: artifact id=11302388503 name=admission-check-2e5871fa04eca7c95e97037bfb872573c5a9d528-1 expired=false
MINT_ART: OK — witness sha-pinned + provenance (H/B/run/pr) fully matched; mergeSha field = M_observed (gate input via its tree — step (3b))
```

`NO_CERT` is therefore not a failure of the cutover: the certificate did not
exist yet when admission read it. It is the designed 2-attempt bootstrap —
mint publishes the subject-continuity certificate and admission consumes it
on the next attempt.

### Attempt 2 — fully green on a full re-run, no manual artifact deletion

Re-run via `POST /repos/Archright/Axiom/actions/runs/37199503612/rerun`
(HTTP 201), all jobs, no intervention of any kind.

| job | started → completed (Z) | conclusion |
|---|---|---|
| `gateway / select` | 11:50:11 → 11:51:07 | success |
| `admission / build-base-artifacts` | 11:50:11 → 11:53:58 | success |
| `admission / admission-check` | 11:54:02 → 11:59:33 | **success** |
| `mint-prepare / prepare` | 11:59:37 → 12:00:08 | success |
| `mint-publish / publish` | 12:00:11 → 12:00:32 | success |
| `admission-check` (aggregator) | 12:00:36 → 12:00:40 | **success** |

Verdict, verbatim from `admission / admission-check` job 111430358891 at
2026-10-04T11:59:28Z:

```json
{"prNumber":465,"headSha":"2e5871fa04eca7c95e97037bfb872573c5a9d528","baseSha":"87df2df5d997cdd15a9c72dbc5db8d87ba53e417","verdict":{"result":"mergeGo","reasonCode":"GO","reason":"admission passes cleared (base freshness bound to main 87df2df5d997; GitHub re-binds at merge time)"},"qualification":"UNSPECIFIED","rotationCheck":null,"rotationNote":"closure inputs absent (AXIOM_DERIVED_H_PATH/AXIOM_DERIVED_B_PATH/AXIOM_PIN_H_PATH) — rotation Pass skipped"}
```

### Artifact evidence

`GET /repos/Archright/Axiom/actions/runs/37199503612/artifacts`,
`total_count = 6`:

| id | name | created (Z) | size |
|---|---|---|---|
| 11302678018 | `tested-tree-digest` | 11:50:29 | 185 B |
| 11301864560 | `ci-select-verifier` | 11:51:06 | 207265 B |
| 11301599620 | `ci-select-decision` | 11:51:05 | 2815 B |
| 11302618531 | `admission-check-base-artifacts` | 11:53:57 | 85689448 B |
| 11302609228 | `admission-check-2e5871fa04eca7c95e97037bfb872573c5a9d528-2` | 11:59:29 | 2750 B |
| 11302477778 | `subject-certificate-2` | 12:00:05 | 3544288 B |

Exactly **one** witness artifact, `admission-check-2e5871fa…-2`. No
unsuffixed `admission-check-2e5871fa…` name is present on attempt 2 — that
is the twin this cutover removes, and it is absent. `MINT_ART` on attempt 2
(`mint-prepare / prepare` job 111431244416, 2026-10-04T12:00:03Z):

```
MINT_ART: artifact id=11302609228 name=admission-check-2e5871fa04eca7c95e97037bfb872573c5a9d528-2 expired=false
MINT_ART: OK — witness sha-pinned + provenance (H/B/run/pr) fully matched; mergeSha field = M_observed (gate input via its tree — step (3b))
```

Attempt 1 showed the same shape: `admission-check-2e5871fa…-1` and
`subject-certificate-1`, and no unsuffixed name.

### Negative results

- No `MINT_ART: … found 2` on any attempt of this run.
- No artifact was deleted by a human or by script. The re-run is a bare
  `POST …/rerun`.
- The legacy unsuffixed witness name was never emitted under this pin.

### Deviation from the expected pattern

None in outcome. One mechanical note: GitHub's `…/runs/{id}/artifacts` and
`…/runs/{id}/jobs` surfaces return only the current attempt after a re-run,
so the attempt-1 rows quoted above were captured before the re-run and from
the attempt-1 job logs directly (job ids 111428813024, 111429431122,
111429523381). This is an API-surface property, not an Axiom behaviour.

## Scope

This record is an observation log. It asserts no gate behaviour on its own;
the authority for admission is the Axiom admission-check verdict recorded by
GitHub, quoted here verbatim.