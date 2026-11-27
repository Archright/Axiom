# Venue execution contract — what a green required check means at each merge venue

> **Status**: Normative (v1, 2026-11-27). Defines what the seven required contexts
> assert at each merge venue, and the obligations that follow from one platform fact:
> GitHub reports a **skipped job as `Success`**, and a required check in that state does
> not block a merge.
> **Required-context authority**: `config/policy/merge_admission.json` (seven contexts:
> six `requiredValidations` jobs plus the `admission-check` verdict published through
> `requiredWorkflowDetection.verdictJob`). This contract adds no context, no check, no
> verdict, and no gate tool, and amends none of the seven.
> **Venue-split precedent**: [ADR-0032](../adr/0032-admission-venue-split.md) (admission),
> [ADR-0043](../adr/0043-publication-venue-split.md) (publication). This contract
> re-opens neither decision. It states the skip obligations those splits already carry,
> and constrains how a *future* split may be expressed.
> **Measurement**: [pr518_venue_execution_measurement_2026-11-27.md](../evidence/pr518_venue_execution_measurement_2026-11-27.md)
> (n=1 PR/merge-group pair, PR #518 — observation, not a performance claim).
> **Protection grade**: this document belongs to neither the trust surface manifest,
> `trustSurface`, nor the checker closure — a revision requires no trust rotation. The
> machine enforcement it refers to (R2/R3 in `tools/ci/validate_workflow_shell.sh`,
> `docs/spec/ci_admission_budget_contract.md` §4) is unchanged by it.
> **Language**: authored in English per [ADR-0045](../adr/0045-english-only-canonical-main.md).

---

## §1. The platform facts this contract rests on

All four are GitHub's documented behaviour, not this repository's invention.

**F1 — a conditional skip is a green.** "A job that is skipped will report its status
as 'Success'. It will not prevent a pull request from merging, even if it is a required
check."
(https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions)

**F2 — a filter skip is a deadlock, not a green.** A workflow skipped by `paths`,
`paths-ignore`, or `branches-ignore` leaves its checks in a **Pending** state, which
blocks merging
(https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs).
F1 and F2 are the two halves of the same trap and they fail in opposite directions: the
filter fails loudly (nothing merges), the conditional job fails silently (the merge
proceeds without the work).

**F3 — `skipped` and `neutral` satisfy a required check.** "Required status checks must
have a `successful`, `skipped`, or `neutral` status"
(https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).
A conclusion-based reader therefore cannot distinguish "this work passed" from "this
work did not run" by status alone; the distinction exists only in the per-job record.

**F4 — `merge_group` is a separate event on the group commit.** "The `merge_group` event
is separate from the `pull_request` and `push` events"; without it "status checks will
not be triggered when you add a pull request to a merge queue". On that event
`GITHUB_SHA` is the merge-group head — the temporary queue commit that would be pushed
to the base branch — and `github.event.merge_group.head_sha` / `base_sha` name the group
head and its parent. The queue evaluates required checks on that commit, not on the
pull-request head
(https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group).

**F5 — `needs` propagates a skip.** "If a job fails or is skipped, all jobs that need it
are skipped unless the jobs use a conditional expression that causes the job to
continue." This is why every aggregator in this repository carries `if: always()` or
`if: !cancelled()` and re-derives its dependencies' results explicitly instead of
letting the platform's default propagation publish a green.

---

## §2. Venues

| venue | trigger | role | required contexts that must report |
|---|---|---|---|
| **PR** | `pull_request` | queue-entry filter: cheap, fast, fails early | all seven, on the PR head |
| **landing** | `merge_group` | **the canonical verdict**: the only landing-eligibility judgment | all seven, on the group commit |
| post-merge | `push` | observation and evidence, not admission | not required |
| maintenance | `schedule`, `workflow_dispatch` | full-surface runs off the critical path | not required |

**V1 — the venue is decided inside the job, never by skipping the required context.**
`admission-check.yml` resolves it in a `[venue]` step that is the **first step** of each
of the three jobs that run on both venues (`build-base-artifacts`,
`admission-independents`, `admission-check`): `pull_request` → `preflight`,
`merge_group`/`workflow_call` → `landing`, any other event → fail-closed exit 1. The two
GO-lane jobs skip at the **job** level instead, which is admissible only because they are
sub-jobs of a required context rather than the required context itself (§3.2, and R3 is
keyed on the policy's `(workflowPath, job)` pairs). `publication-integrity.yml` keeps
every dimension job unconditional and tells the evaluator the venue instead
(`tools/ci/publication_report.nim` `--venue`, a required closed enum). Both are instances
of this rule; neither relies on the platform's skip semantics to select a venue.

**V2 — PR green is not landing evidence.** Landing eligibility has exactly one canonical
producer: the `admission-check` verdict computed at the landing venue on the group
commit. A pass at the PR venue means "the preflight subset that ran passed"; it is not
evidence that the landing verification would pass, and it must never be cited as such
([ADR-0032](../adr/0032-admission-venue-split.md) (a),(f)).

---

## §3. The seven required contexts, by venue

`job` is the id that publishes the context — the pair `(workflowPath, job)` is what
`config/policy/merge_admission.json` names and what R3 is keyed on.

| # | context | workflow | job | PR venue | landing venue |
|---|---|---|---|---|---|
| 1 | `admission-check` | `.github/workflows/admission-gate-v2.yml` | `admission-check` (`if: always()`) | runs | runs |
| 2 | `axiom-operational-slice` | `.github/workflows/axiom-operational-slice.yml` | `axiom-operational-slice` | runs | runs |
| 3 | `readiness-verdict` | same | `readiness-verdict` (`needs: [axiom-operational-slice]`) | runs, after #2 | runs, after #2 |
| 4 | `publication-integrity` | `.github/workflows/publication-integrity.yml` | `publication-integrity` (`if: !cancelled()`) | runs (1 of 6 dimensions) | runs (6 of 6) |
| 5 | `bsec-integrity` | `.github/workflows/bsec-integrity.yml` | `bsec-integrity` | runs | runs |
| 6 | `debt-registry-gate` | `.github/workflows/debt-registry-gate.yml` | `debt-registry-gate` | runs | runs |
| 7 | `generation-acceptance` | `.github/workflows/generation-acceptance.yml` | `generation-acceptance` | runs | runs |

**No required `job` is conditionally skippable** (R3, machine-enforced): its `if:` may be
only absent, `always()`, `!cancelled()`, or a `&&`-conjunction of those. Row 1's `gateway`
need is a reusable-workflow call whose own `executed-jobs` rollup publishes an explicit
per-unit basis (`name=skipped(sl09_not_promoted)`) rather than relying on the callee's
worst-leg result.

Rows 5–7 carry no venue predicate at all: `bsec-integrity.yml` states "NO conditional
`if:` skip on the job", and `debt-registry-gate.yml` / `generation-acceptance.yml`
declare no job-level `if:`. The `generation-acceptance` fast path is **data-derived**
(server-side changed-file list, no surface delta), not venue-derived — it takes the same
branch on both venues.

### §3.1 The `needs:` edge that defines the wall

`readiness-verdict` declares `needs: [axiom-operational-slice]`
(`.github/workflows/axiom-operational-slice.yml:319-320`). Both job ids are required
contexts of the **same** workflow, so that workflow's wall is the **sum** of the two jobs,
not the maximum: the second half cannot start until the first finishes, and both must
report. This is why `axiom-operational-slice` is the primary measured target for the
admission wall (`docs/spec/ci_critical_path_metric.md` §1.1) — it is a serial chain by
declaration, not by scheduling accident. A second instance of the same shape is the
`admission-check` aggregate, whose `needs:` names seven callee jobs and whose first step
converts each result into an explicit judgment (`if: always()`, then a 7-fold conjunction
that fails on `skipped`/`cancelled`/`failed`).

### §3.2 Skip units — every skip, its compensation, and its basis

A **skip unit** is any job or step inside a required context whose execution is
conditionally suppressed. Each one is registered here; a skip unit that is not in this
table is a contract violation (§5, Q3).

| skip unit | venue skipped | condition locus | what runs instead (compensation) |
|---|---|---|---|
| `go-critical-lane` (2-lane matrix), `go-critical-rollup` | PR | `admission-check.yml:3973`, `:4782` — `always() && stage=='attest' && (merge_group \|\| workflow_call)` | The landing venue runs both lanes. At PR, `[preflight] Attest-leg static contrast` (`:1723`) asserts the TWS pin pair (`git hash-object admission-check.yml` == `trustedAdmissionWorkflowSha`) and `certRequired == true`; `[preflight] Verdict-leg static contrast` (`:2199`) asserts policy SSOT and the stage-dispatch structure; `[preflight] Rotation-pin H2 contrast` (`:2289`) asserts the rotation pin. The static contrast is **not** a substitute for the GO lanes — it asserts pin and policy posture, not the admission-contract tests. The full-execution compensation is the later venue. |
| `anchor-resolve` | landing | `admission-gate-v2.yml:210-211` — `github.event_name == 'pull_request'` | PR runs it and supplies the run-scoped `B_STAR`; at the landing venue the anchor stays event-frozen (ADR-0027 P4). The aggregate asserts this exact asymmetry inline: `skipped` is admitted **only** when `event_name != 'pull_request'` (`admission-gate-v2.yml:761-766`). |
| `[guard] Every direct need must be success` step | PR | `admission-check.yml:813-814` — `stage=='attest' && venue=='landing'` | **none, and that is the honest statement**: the PR venue never converts a skipped lane into a judgment. It is safe only because the GO lanes are the sole lane skip and the landing venue re-runs them with the guard active. |
| `license-scan-shards`, `license-scan`, `dependency-scan`, `provenance`, `sbom`, `script-scan` | PR | `.github/workflows/publication-integrity.yml:204,306,437,519,570,642` | The landing venue runs all six. The aggregator job runs on **both** venues and is told the venue; the required set is a closed enum in `tools/ci/publication_report.nim` (`PreflightDimensions = ["secret-scan"]`; `LandingEvents` → all six). A `success` for a dimension the venue does not require is a **BLOCKER**, not credit. |
| `gateway/candidate-build-arm`, `gateway-shard`, `gateway-identity-gate`, `gateway/proof-reconcile` | both | `.github/workflows/runner-pool-acceptance.yml` — `needs.sl09-scope.outputs.scope_sl09 == 'true'` | The callee's `executed-jobs` rollup runs on both venues and publishes an explicit per-unit basis; a skip outside `sl09_not_promoted` fails closed. Scope, not venue — recorded here because a reader of the run will see these skipped in both venues. |
| the `stage` sections of the three reusable calls — `verdict/build-base-artifacts`, `verdict/admission-independents`, `verdict/go-critical-lane`, `verdict/go-critical-rollup`, `mint-publish/prepare`, `mint-prepare/publish` | both | `admission-check.yml` job `if:` — the `inputs.stage == 'attest'` / `'verdict'` conjunct; the `mint-*` calls select a section by the `stage:` input | Admissible because **the sibling section of the same call executes on the same venue**: `attest/*`, `mint-prepare/prepare`, `mint-publish/publish` ran on both. `stage` is a required workflow input, so a call that omits it fails at plan time rather than skipping silently. |

**V3 — a skip unit is legitimate only with a named basis and a compensation.** The basis
is either (a) *the later venue executes the same unit* — the landing venue is the
canonical verdict, so a PR-only skip is bounded; or (b) *an executed step on the skipping
venue asserts a named property of what was skipped*, and that step prints what it checked
(`PREFLIGHT PASS — …` lines, ADR-0032 (f) item 1). A skip with neither is theater and is
a §0.9 violation.

**V4 — no required context may be skipped at the landing venue.** The only admitted
landing-venue skip is `anchor-resolve`, and the aggregate asserts it inline. This is not a
stylistic preference: the landing venue is the canonical verdict, so a skip there has no
later venue to compensate it, and F1 turns it into a permanent silent pass.

**V5 — step-level `if:` is not machine-enforced.** R3 (`tools/ci/validate_workflow_shell.sh`)
decides the **job-level** `if:` of the `(workflowPath, job)` pairs the policy names
(`check_required_rules` reads `jobs.<id>.if` only). It does not read step `if:` values.
Every step-level skip inside a required job is therefore review-enforced and must appear
in §3.2; the table is the enforcement, not the validator.

---

## §4. What a green required check asserts, per venue

| venue | a green `admission-check` asserts |
|---|---|
| PR | identity re-derivation + TWS pin pairing + policy SSOT + the static contrasts + every non-skipped lane passed. **Not** landing eligibility. |
| landing | the full canonical chain on the group commit: base artifacts, GO-critical lanes, admission independents, the minted certificate, the `ax merge` predicate, the gateway rollup. Skipped lanes are red (`[guard]`). |
| post-merge `push` | nothing about admission; the run is evidence, not authority. |

Consequence, stated plainly because it is the point of this document: **everything that
stands between a bad pull request and the merge queue is the PR-time required check**, and
that check is by construction the weaker of the two — it is the one whose sub-units are
allowed to skip. The PR venue buys *liveness* (a defective PR is rejected before it
occupies a queue slot); the landing venue buys *soundness* (the group commit is verified
as it will land). Neither substitutes for the other, and a PR green that is read as
landing evidence is exactly the misreading F1 makes possible.

---

## §5. Adding a venue split — the four questions

A change that makes any unit of a required context run on only one venue must answer all
four in the PR body, and update §3.2 in the same commit.

1. **Which venue is canonical for this unit?** If the answer is "the landing venue only",
   the unit may skip at PR (V3a). If it is "both", it may not skip at either.
2. **Is the unit a job the policy names?** If yes, R3 forbids the split outright — the
   venue must be resolved *inside* the job (§2 V1). A split is expressible only below the
   required `job`.
3. **What is the compensation, and does it execute?** Name the step (with the string it
   prints) or the later venue. "It is covered elsewhere" is not an answer; §3.2 names a
   locus.
4. **What does the aggregate assert about the skip?** Preferred: the aggregate
   re-derives the dependency's result and admits exactly one skip under exactly one event
   predicate (`admission-gate-v2.yml` `anchor-resolve` is the model). Acceptable: the
   skipped unit is a dimension of a job that always runs, and the job's evaluator is given
   the venue as a required argument (`publication_report.nim` is the model).
   Unacceptable: nothing asserts it, and the platform's F1 is what makes it green.

Failure of any question = the change is a silent pass and is rejected on review. The
budget rules of `docs/spec/ci_admission_budget_contract.md` §4 (R2, R3) bound the same
defect from the placement side; this section bounds it from the evidence side.

---

## §6. Change authority for a required context

| object | authority | cost of a change |
|---|---|---|
| `(workflowPath, job id, context name)` in the ruleset | GitHub ruleset `27097366` | **no re-registration** while the triple is unchanged — [ADR-0043](../adr/0043-publication-venue-split.md) (d). The context name *is* the job id; adding a job-level `name:` key would break it. |
| `.github/workflows/admission-check.yml` content | `config/trusted_writer_set.json` `trustedAdmissionWorkflowSha` + `config/policy/epoch_manifest.json` `productionExecutionPin` | atomic pair rotation (A2). The preflight step at `admission-check.yml:1723` fails closed unless the pair equals the blob at B. |
| any path in `config/policy/trust_surface_manifest.json` | the App's `blob(G) == blob(B_mg)` condition | break-glass: a PR that edits these paths cannot land through the normal queue (`docs/spec/break_glass_protocol.md`; precedent `docs/evidence/breakglass_trust_surface_landing_2026-11-20.md`). |
| this document | review | none — outside the trust surface, the manifest, and the checker closure. |

---

## §7. Loci this contract does not decide

- **The App's PR-venue judgment set.** `docs/agents/axiom_admission_verifier_ops.md:38`
  states that `admission-check` is published on both the PR head and `G`, and that the PR
  venue is a preflight. Which predicates the App itself evaluates in the PR venue (as
  opposed to the run it observes) is not documented in this repository: **UNKNOWN**.
  Invariant V2 does not depend on it — the landing venue's verdict is the canonical one.
- **Step-level `if:` coverage** — V5. Review-enforced.
- **`check_response_timeout_minutes`** (120) is a ruleset value, not a contract term; a
  run that reports no conclusion at all is F2's deadlock with a clock on it.

## §8. References

- `.github/workflows/admission-gate-v2.yml` — the 7-fold aggregate, `anchor-resolve`, `gateway`.
- `.github/workflows/admission-check.yml` — `[venue]`, `[guard]`, `[preflight]` steps, GO lanes.
- `.github/workflows/axiom-operational-slice.yml` — the serial `needs:` chain.
- `.github/workflows/publication-integrity.yml`, `tools/ci/publication_report.nim` — the venue-as-input pattern.
- `.github/workflows/runner-pool-acceptance.yml` — the callee's `executed-jobs` basis rollup.
- `config/policy/merge_admission.json`, `config/policy/trust_surface_manifest.json`.
- `tools/ci/validate_workflow_shell.sh` — R2/R3 predicates.
- [ADR-0027](0027-queue-delegation.md), [ADR-0032](0032-admission-venue-split.md),
  [ADR-0043](0043-publication-venue-split.md), [ADR-0041](0041-free-authority-migration.md).
- GitHub: control-jobs-with-conditions, skip-workflow-runs, about-protected-branches,
  merge_group event reference (URLs inline at F1–F4).