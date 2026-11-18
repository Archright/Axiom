# Fresh Prove Observation Contract (`axiom.fresh-prove.v1`)

Status: ACTIVE (2026-11-18, `workstream/vs-auth-fresh`).
Judgment SSOT: `tools/ci/fresh_prove_verdict.nim`.
Observation surface: `.github/workflows/fresh-prove-observation.yml`.
`--fresh` wiring: `src/cli/axiom_engine.nim`, `src/verification/batch_uap/loop_driver.nim`,
`src/verification/batch_uap/certificate_hydration_runner.nim`, `src/core/orchestrator/orchestrator_vault.nim`.

## 1. Purpose

A fresh full-scope prove answers one question: **for the exact subject commit, what did
the verification engine actually prove in this run — not what an earlier run recorded?**

The contract separates four facts that must never be conflated:

1. a prove was *executed*;
2. the prove *succeeded*;
3. the success is *valid for the current source*;
4. GitHub *enforces* the result.

This slice observes (1)–(3). Fact (4) is unchanged: merge authority remains the GitHub
ruleset + merge queue. Independent evidence verification and required-check promotion are
the separate `#549` epoch.

## 2. Authority boundary

- **Non-required, non-authoritative.** The workflow publishes no admission check, no
  check run, and no merge verdict. It is a `contents: read` observation surface.
- **No `merge_group` trigger** (`pull_request`, `push: main`, `workflow_dispatch` only).
  Decision #20(a) classifies a non-required, `contents:read` observation workflow as not
  an authority surface; v101 closed the DEBT#545 class where a merge_group-triggered
  CONTROLLED exact would nullify the `.github/**` FROZEN glob. Merge-queue binding is a
  `#549` decision, not an implicit consequence of this file.
- **Self-report on `pull_request`.** GitHub runs the `pull_request` workflow file from the
  PR merge commit, so a PR can alter what its own run reports. The result is PR-code
  self-report, never independent evidence. (`workflow_dispatch` checks do not satisfy PR
  required checks — GitHub platform behavior.)
- **No ruleset, App, trust-surface manifest, or required-context change.** The live
  7-context contract and `config/policy/trust_surface_manifest.json` are untouched.

## 3. `--fresh` semantics

`ax prove --fresh` means: **no verification result produced by an earlier invocation may
satisfy any unit of this run.** Four reuse paths are bypassed:

| # | Reuse path | Bypass |
|---|---|---|
| 1 | vault verified-set hydration | `hydrateRunVault(..., fresh = true)` re-initializes the verified set instead of loading stored certificates |
| 2 | vault spec priming | `loop_driver` skips `primeTransitiveFingerprintCache` entirely (the certificate-bearing module is not modified) |
| 3 | certificate hydration pre-pass | `runCertificateHydrationPrePass(..., fresh = true)` returns before hydrating |
| 4 | global stage-1 summary cache | `summaryCache.clear()` before the work plan executes |

Build and dependency caches are **not** verification results. They remain allowed when
their identity is bound into the build/toolchain identity; `--fresh` removes verdict reuse,
not compilation reuse. Reintroducing any of the four paths requires a new marker version
and new tests.

## 4. Freshness marker

`ax report --json` carries:

```json
"freshness": {
  "contract": "axiom.fresh-prove.v1",
  "fresh": true,
  "reuseBypass": ["vault-verified-set", "vault-spec-priming",
                   "certificate-hydration", "summary-cache"],
  "authoritative": false
}
```

The projection never trusts the marker as a verdict. A missing marker is a contract
violation (`freshness-marker-absent`); `fresh: false` is `freshness-not-requested` — either
one makes PROVED impossible. `authoritative: false` is the report's own statement that the
marker is not merge authority.

## 5. States

| State | Condition |
|---|---|
| `PROVED` | every `REQUIRED` unit is `SATISFIED` with `satisfactionSource == FRESH` **and** all global conditions in §6 hold |
| `REFUTED` | a unit is `UNSATISFIED` **and** a machine-readable refutation witness exists for it (`witnessFor(nodeReports, unitId)`) |
| `OUT_OF_SCOPE` | the unit is `NOT_REQUIRED` **and** its id is explicitly listed in the approved `scopeContract.outOfScope` |
| `UNKNOWN` | everything else |

`NOT_REQUIRED` alone is **not** `OUT_OF_SCOPE` — without an explicit scope-contract
exclusion it is `UNKNOWN` (`not-required-without-scope-contract`). In particular:

- `SATISFIED` + `REUSED` (or any non-FRESH source) → `UNKNOWN`, never PROVED.
- `UNSATISFIED` without a machine-readable witness (e.g. `EA_UNSUPPORTED`,
  `ckIfStmt` unsupported, timeout, solver failure, bare `failed`) → `UNKNOWN`, never
  REFUTED. **A failed execution is not a refutation.**
- `PENDING`, `CONTESTED`, `UNRESOLVED` → `UNKNOWN`.

The four states are not interchangeable and are never collapsed into an exit-code pair.

## 6. PROVED — all conditions required

The judge emits `PROVED` only when **all** of the following hold
(`tools/ci/fresh_prove_verdict.nim`, `projectVerdict`):

1. `requiredCount > 0` — an empty required set is not a proof;
2. every required unit is `PROVED` (`provedCount == requiredCount`) and no unit is
   `REFUTED`, `UNKNOWN`, or `OUT_OF_SCOPE`;
3. accounting is clean: `satisfiedCount == requiredCount` and
   `unsatisfiedCount == pendingCount == contestedCount == notAttemptedCount ==
   proofFailedCount == unresolvedDecisionCount == 0`;
4. no accounting anomalies;
5. the freshness contract holds: marker present, `fresh == true`, and
   `satisfiedByReused == 0`;
6. `closure.closureComplete == true`;
7. the VDA run outcome is `verificationComplete == true` and `verdict == "PASS"`;
8. the declared scope lock is fully covered (`coverage.complete == true` — every declared
   symbol is accounted for, with no unclassified gaps);
9. the subject SHA is present.

`verified > 0` is **not** a PROVED condition. Partial coverage is `UNKNOWN` and the
missing set is reported. The declared scope is the `data/verification_scope.lock` set;
omitting `--target` does not by itself prove that the engine executed every required
proposition — condition 8 is the mechanical check.

## 7. Canonical evidence vs execution provenance

The output separates two payloads:

- **Canonical evidence payload** (deterministic; the digest subject): subject SHA/tree,
  scope-lock digest, verifier identity (binary/source/engine build), freshness binding,
  run accounting, closure, sorted unit rows, `canonicalRunDigest`.
- **Provenance** (not in the digest): `runId`, `attempt`, `runUrl`, `runner`,
  `generatedAt`.

Invariant: for the same subject, scope, verifier, and configuration, the canonical
evidence digest is identical across runs and across cache state. `H(P1) == H(P2)` while
the provenance records may differ. Measured 2026-11-18: two fresh runs produced
`canonicalEvidenceDigest = a808f503bea1fdcde14b16b5450325459991773233be73543a7c54e05464ca8a`
with different `runId`s.

## 8. Exit codes and conclusion mapping

| Verdict | Exit | `checkConclusion` (artifact) | Observation job |
|---|---|---|---|
| `PROVED` | 0 | `success` | green |
| `REFUTED` | 1 | `failure` | red |
| `UNKNOWN` / `OUT_OF_SCOPE` | 3 | `neutral` (contract violation ⇒ `failure`) | green + warning annotation |
| usage / IO error | 2 | n/a | red (observation pipeline failure) |

The workflow does not create check runs (`checks: write` is deliberately absent), so the
artifact and the job log/summary are the observation surface. A red job therefore means
REFUTED or an observation-pipeline failure; the artifact distinguishes them.

## 9. Empirical baseline (2026-11-18, local `vs/auth-fresh`)

- Warm baseline copy, `AXIOM_PROVE_WORKERS=1`, three runs on the same tree: warm plain
  38.8 s (exit 1), fresh 25.8 s (exit 1), fresh 25.9 s (exit 1).
- All three runs: `satisfiedByReused = 0`, `satisfiedByFresh = 2`,
  `freshExecutionCount = 3`, `verified = 2`, `failedCount = 1`, canonical verdict `FAIL`.
- Freshness marker present only on the `--fresh` runs (`fresh:true`,
  `reuseBypass` = the four paths); the plain run reports `fresh:false`, `reuseBypass:[]`.
- Projection of the fresh state: `UNKNOWN` (exit 3), `neutral`,
  units 5 / required 5 / proved 2 / unknown 3; reasons `pending-contested`,
  `unsatisfied-without-refutation-witness`, `vda-not-pass`, `closure-incomplete`,
  `scope-coverage-incomplete`; coverage 17/40 (23 missing).
- **Measurement caveat.** The current canonical vault's certificates carry
  `verificationTier` and no `vcHash`, so `certificateAccepted` returns false on the legacy
  path and warm reuse does not actually occur in this baseline. `--fresh` therefore makes
  no observable timing difference today on this path. The earlier "warm 45–52 s" figure
  describes a different measurement scope and must not be used as this slice's baseline.
  A cache-hit/vault-reuse fixture is required before claiming a reuse-bypass speedup.

## 10. Residuals (not resolved by this contract)

- `#547` — `ckIfStmt` unsupported: a real proof-coverage limitation. The honest result is
  `UNKNOWN`, never `REFUTED` and never a silent scope reduction.
- `#551` — IR v1.3 boolean `Switch` collapse boundary: a verifier-language decision.
- `#549` — fresh full-scope promotion to required/merge_queue, trust-surface pinning, and
  independent App verification: a CI-authority epoch decision.
- `#548` — cache/judge separation beyond the four paths: policy work.