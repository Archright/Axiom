# Workflow Parse-Poison Lint — PR-Venue Wiring Design (implementation deliberately excluded)

- Date: 2026-10-14
- Branch: `ci/workflow-parse-poison-lint` (base: origin/main `1b187d1a5`)
- Status: DESIGN ONLY. Wiring any lint step into a workflow file is a live
  CI execution-boundary change (§2.5 CI Self-Bootstrap Bottleneck) and is
  deliberately NOT implemented in this change set. This document is the
  committed design input for that separate §2.5 generation.
- Companion implementation (this change set, no workflow edits): parse-poison
  rule in `tools/ci/validate_workflow_shell.sh`, boundary fixtures under
  `tests/fixtures/workflow_poison/`, self-test harness
  `tools/ci/test_workflow_poison_lint.sh`, make target
  `test-workflow-poison-lint`.
- Platform quirk SSOT: docs/spec/gh_run_observation_quirks.md Q4.
  Oracle evidence: docs/evidence/admission_parse_poison_oracle_2026-10-13.md.

## 1. Defect class (all measured)

GitHub rejects at CALL-GRAPH PLANNING time any `run:` scalar that carries an
expression token AND exceeds the 21,000-char expression-length cap:
HTTP 422 "Exceeded max expression length 21000", 0 jobs, no check-run, and
the Actions workflow registry falls back to the raw file path as the name.
Token presence is the applicability condition — a token-free scalar of
26,282 chars PASSES while a 25,954-char tokenized scalar FAILS (org
parse-probe oracle). A poisoned required workflow therefore never reports
its required check and the venue stalls; the 2026-10-12 incident (~9h full
merge-queue outage, 219 failed runs) entered via PR #780
(admission-check.yml verdict leg, +1 tokenized assignment, 25,954 chars)
becoming rotation-eligible and then being pinned by a routine org pin
rotation. PyYAML AND actionlint both PASS poison files. actionlint adoption
remains REJECTED on supply-chain grounds (Makefile comment at
`check-workflow-shell-syntax`; do not re-propose).

## 2. Current invocation surface of validate_workflow_shell.sh (origin/main 1b187d1a5)

| # | Point | Venue | Mechanism |
|---|---|---|---|
| 1 | Makefile:61 `PUSH_ADMISSIBILITY_GATES` | push | single definition point of the push-time gate set; includes `check-workflow-shell-syntax` |
| 2 | Makefile:590 `check-workflow-shell-syntax` | push | thin target invoking `tools/ci/validate_workflow_shell.sh` (loud-SKIP when absent from the OID — snapshot tolerance) |
| 3 | Makefile:523 `push-admissibility` | push | consumes #2 via `$(MAKE) --no-print-directory check-workflow-shell-syntax` |
| 4 | Makefile:597 `check-push-admissibility-integrity` | push | gate-universe closure check naming #2 |
| 5 | .githooks/pre-push:45-48, 117, 124 | push | Mechanism A: detached snapshot worktree at the pushed OID + current-Makefile copy (`cp -f`) + `make -C $SNAP push-admissibility` → #3 → #2 |

`grep validate_workflow_shell .github/workflows/` on origin/main: **0 hits** —
no GitHub workflow invokes the script. Conclusion: the invariant is enforced
PUSH-TIME ONLY. PR venue: absent. Merge-queue venue: absent.

## 3. Why PR-venue availability is the lint's primary value

- The admission callee chain executes PINNED: the org required workflow
  `admission-gate.yml` (`requiredWorkflowDetection` in
  config/policy/merge_admission.json v1.14.0) workflow_calls
  admission-check.yml at the blob sha pinned in
  config/trusted_writer_set.json (`trustedAdmissionWorkflowSha`). A PR-side
  poison in admission-check.yml therefore cannot affect a RUNNING
  merge-queue chain through that PR itself — the queue executes the pinned B
  blob, not the PR's copy. Stating the boundary explicitly: **the lint does
  not protect in-flight queue executions; its value is PR-venue
  availability (pre-merge stall prevention at the source).**
- The exposure is LANDING→ROTATION: a poisoned blob that lands becomes
  rotation-eligible, and the next routine A2 atomic pair (admission-check.yml
  edit + trustedAdmissionWorkflowSha update in the same diff) points the
  live chain at it — exactly the 2026-10-12 path. PR-venue rejection breaks
  that chain at the cheapest point: the author's own PR goes red with a
  file/step/length diagnosis before the blob can ever land.
- Secondary value: a poison in ANY workflow file on a PR's merge ref makes
  that file 0-job at the PR venue; if the file is required-check-bearing
  (e.g. bsec-integrity.yml), the required check never reports and the PR
  blocks with no diagnostic. The lint, running inside a healthy workflow
  file, names the exact file/step/length for any poisoned file in the
  checkout (it scans all of .github/workflows, not just its own host).

## 4. Required-check semantics constrain the wiring (un-skippability)

- GitHub treats a skipped or neutral conclusion as SATISFYING a required
  check — but only when the job actually REPORTS that conclusion inside an
  executed run (a job-level `if:` that evaluates false, or an upstream
  dependency that skips). A workflow that never runs at all — path-filtered,
  branch-filtered, or `[skip ci]` — reports NO check run, so the required
  check stays Pending ("Waiting for status to be reported") and blocks the
  merge. The two cases are opposite, and the path-filtered one is the
  dangerous one. (Verified against docs.github.com, "Troubleshooting required
  status checks" / "Status checks reference", 2026-10-20.) Therefore the
  wired lint must have:
  no `paths:`/`paths-ignore:` filters on the trigger, no job-level `if:`
  that can evaluate false, and no step-level condition that can skip the
  lint while the job still concludes success.
- A workflow whose FILE is poisoned produces no check-run at all. For
  ruleset required checks, "unreported" blocks merge (fail-closed, but
  diagnosis-free). Consequence: the lint cannot defend the file it lives
  in; it defends all OTHER files, and the host file's own poisoning is
  caught by absence-of-check (fail-closed).
- The lint's failure must propagate to the JOB conclusion (step failure →
  job failure → red required check). `tools/ci/validate_workflow_shell.sh`
  exits 1 on any violation or unparsable YAML — fail-closed by contract.

## 5. Candidates

### C1 — step inside bsec-integrity.yml (job `bsec-integrity`) — RECOMMENDED
- File: .github/workflows/bsec-integrity.yml. Triggers: pull_request(main)
  + merge_group, NO path filters (header documents the required-check
  posture: "a workflow-level skip would leave the required check
  unreported"). Permissions: contents: read. The bare job id IS the required
  check name.
- Trust surface: LISTED — config/policy/merge_admission.json v1.14.0
  trustSurface includes .github/workflows/bsec-integrity.yml;
  requiredValidations lists {workflowPath: bsec-integrity.yml, job:
  bsec-integrity, acceptableConclusion: success}.
- Wiring: one unconditional step immediately after checkout:
  `- name: "[check] workflow parse-poison lint (tokenized run scalar > 21000)"`
  / `run: bash tools/ci/validate_workflow_shell.sh`
- (a) fires on every PR to main and every merge_group entry — total venue
  coverage for merge-relevant events, including PRs that touch no workflow
  file ("ideally always", for the venues that can land poison).
- (b) cannot be skipped: no filters today; unconditional step; the job
  conclusion is the required verdict.
- (c) influences a REQUIRED check: yes — job `bsec-integrity`.
- Catches poison in ANY of the 16 workflow files at the merge ref (full
  checkout scan), including files that never execute at the PR venue
  (admission-check.yml, certificate-mint.yml are workflow_call-only there) —
  the #780 class would have been caught red at the PR.
- §2.5: editing a live execution boundary → ONE coherent generation cutover;
  the workflow edit must land atomically with a complete lint generation
  (rule + fixtures + harness already committed in the preceding generation),
  no in-place partial flip, no mixing with unrelated CI edits.
- Cost: the lint is ~0.2-1.5s (python3+yaml scan + bash -n; measured locally
  at ~1.4s for fixtures + 16 workflows), inside a 10-minute job budget.
- Residual (outside the accidental-defect threat model): a PR can EDIT
  bsec-integrity.yml itself to remove the step (repo-level file, not
  org-pinned). If adversarial-PR neutralization is ever in scope, only the
  org-required-workflow chain executes with default-branch authority — that
  is an org-side surface, outside repository authority.

### C2 — repository_surface.yml — REJECTED as the enforcement venue
- PR-triggered (pull_request only), but the file header states it is an
  advisory observation check ("required check 아님") and requiredValidations
  does not list it. Trust surface: LISTED in v1.14.0 trustSurface — but
  trust-surface membership is not required-check authority. Fails
  requirement (c): a red lint here never blocks merge. Adding a lint step
  there is harmless extra observation yet still costs a §2.5 generation for
  zero enforcement gain over C1. Not recommended.

### C3 — new tiny workflow (e.g. .github/workflows/workflow-poison-lint.yml)
- (a)+(b) achievable in-file (pull_request + merge_group, no filters,
  unconditional job), but (c) requires GitHub-side ruleset/required-check
  registration — merge-admission authority is GitHub (§2.3); until
  registered it is an unbound observation layer ("required checks가 0건이면
  UNKNOWN / NOT READY — SUCCESS로 해석하지 않는다"). Adds a NEW execution
  boundary (its own §2.5 cutover) duplicating C1's venue, plus a 17th file
  the lint itself must then scan. Rejected as primary; acceptable only as a
  post-C1 dedicated surface if bsec's runtime budget ever becomes a concern.

### C4 — considered and rejected: step inside admission-check.yml (attest stage)
- Would enforce on the live pinned chain at the queue venue, but
  admission-check.yml edits are A2-rotation-coupled (blob sha atomic pair
  with trustedAdmissionWorkflowSha in config/trusted_writer_set.json) — the
  highest-friction surface in the repo — and its PR-venue runs execute the
  pinned B blob, so there is no PR-venue availability gain over C1.
  Strictly dominated by C1.

## 6. Recommendation

C1. Landing order (each a coherent §2.5 generation):
1. THIS change set (no workflow edits): rule + fixtures + harness + make
   target. Push-time protection is already active through the existing
   PUSH_ADMISSIBILITY_GATES wiring (#2/#3 in §2).
2. Wiring generation: the single C1 step in bsec-integrity.yml, nothing
   else, landing only after (1) is on main, so the behavior pinned at the
   cutover OID is complete.
3. Post-cutover observation: confirm the step's PASS line on the next PR's
   bsec-integrity run (observational evidence, not authority).

## 7. Verification record (this change set — all local, no push)

- Self-test harness: `make test-workflow-poison-lint` → PASS
  (fixture matrix 5/5 + sweep 0 violations over 16 workflows).
- Existing behavior unchanged: `tools/ci/validate_workflow_shell.sh` default
  run over .github/workflows → 167 run blocks checked, 0 failures;
  `--self-test` → PASS.

### Fixture matrix (committed files; parsed-scalar lengths verified byte-exact)

| Fixture | Form | Token | Scalar len | Verdict |
|---|---|---|---|---|
| poison_21001_tokenized.yml | block | yes | 21,001 | FAIL (length=21001) |
| boundary_21000_tokenized.yml | block | yes | 21,000 | PASS (at-cap is not over-cap under > rule) |
| boundary_20999_tokenized.yml | plain | yes | 20,999 | PASS |
| control_30000_token_free.yml | plain | no | 30,004 | PASS (token-free class is cap-exempt) |
| poison_regression_25954.yml | block | yes | 25,954 | FAIL (PR #780 regression shape) |

### False-positive sweep — per-file max TOKENIZED run-scalar length (16 files, 0 violations; overall max 14,049)

| File | Max tokenized len | Holder (job:step) |
|---|---|---|
| admission-check.yml | 14,049 | admission-check:[check] Re-derive admission identity (B/H/treeOID — fail-closed) |
| bsec-integrity.yml | 266 | bsec-integrity:[env] export verifier inputs |
| certificate-mint.yml | 6,066 | prepare:(1) Derive B/H via run API + PR API (no M — pre-landing mint) |
| ci-cache-publisher.yml | 2,302 | publish:Publish verdict log (acceleration only — no evidence claim) |
| closure-watcher.yml | 0 | — (no tokenized scalar) |
| diagnostic-authority.yml | 684 | delegated-diagnostics:[evidence] Record issuance evidence (token never printed) |
| gateway-jobs-measure.yml | 1,075 | provision:B-layer fingerprint manifest (save-side, in-payload) |
| h4-routing-measure.yml | 4,040 | measure:Measured R2 — admission job-2 kernel (B-built bin/ax) |
| hardware-falsification-smoke.yml | 0 | — |
| merge-queue-rearm.yml | 0 | — |
| observation.yml | 3,649 | observe:[observe] Observe (3-state verdict → job conclusion mapping) |
| probe-merge-queue.yml | 2,667 | probe-capture:Dump merge-group payload (artifact + job summary) |
| release-ship.yml | 0 | — |
| repository_surface.yml | 0 | — |
| runner-pool-acceptance.yml | 4,915 | select:Produce oracle evidence (5-axis, B-built deriver on H-as-data) |
| trusted-writer-set.yml | 0 | — |

The sweep's overall max (14,049, admission-check.yml) matches the predicted
value exactly — no near-cap tokenized scalar exists on main today; the
smallest margin is admission-check.yml itself at 6,952 chars of headroom.

## 8. Residual unknowns

1. Exact 21,000 boundary (">" vs ">="): not locally determinable; the rule
   mirrors the platform error text and fails on length > 21000. The only
   local-adjacent oracle is the org parse-probe dispatch. Recorded in the
   quirk SSOT (docs/spec/gh_run_observation_quirks.md Q4).
2. C1 adversarial neutralization (a PR editing its own required workflow) is
   outside the accidental-defect threat model; the only cure would be
   org-required-workflow authority (org-side, out of repository scope).
