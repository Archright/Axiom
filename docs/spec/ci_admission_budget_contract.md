# CI admission budget contract — bounding the marginal cost of adding verification

> **Status**: Normative (v1, 2026-11-26). Answers one question: *can verification capability keep growing without the merge wall growing with it?* This contract defines **placement and admission rules for new verification**. It introduces no new verdict, gate tool, check, required context, or measurement; R2/R3 are enforced as predicates inside the already-required `validate_workflow_shell.sh` (§9.2), which is form (a) — a step in an already-provisioned job.
> **Bounded quantity**: `T_admission` (merge-queue entry → merged) over `merge_group` candidates, as defined by the frozen metric contract.
> **Measurement authority**: [ci_critical_path_metric.md](ci_critical_path_metric.md) (frozen v2, 2026-11-24). This document redefines **none** of its quantities; every term in §2 is inherited verbatim.
> **Required-context authority**: `config/policy/merge_admission.json` (v1.25.0 — seven required contexts: six `requiredValidations` jobs plus the `admission-check` verdict published through `requiredWorkflowDetection.verdictJob`). This contract does not amend it.
> **Creates no new verdict** — same discipline as [evidence_capsule_contract.md](evidence_capsule_contract.md) §1.2. Rules here constrain *where* a verification may run; they never decide *whether* a change is admissible.
> **Protection grade**: this document belongs to neither the trust surface manifest, `trustSurface`, nor the checker closure — a revision requires no trust rotation. R2 (banned trigger filters) and R3 (required-job `if:`) are machine-enforced by `tools/ci/validate_workflow_shell.sh` since §9.2; R1 and R2's allow-list coverage are review-enforced and labelled as such at their rule.

---

## §1. The defect this contract bounds

Verification capability in this repository has grown every week and is expected to keep
growing. The merge wall must not grow with it. Those two statements are only compatible if
the marginal wall-clock cost of a new verification is **bounded by something other than the
total number of verifiers**.

They are compatible, because the merge wall is not a sum over verifiers. It is a **maximum
over required contexts**, and the six required workflows that carry those contexts already
have unequal completion times. A new verification that runs inside a workflow which finishes
before the slowest one costs the wall **nothing**; a new verification that runs on the
slowest one costs its full duration. The repository has measured both cases:

- `publication-integrity` grew to six landing dimensions while remaining the last finisher in
  **zero** observed cycles; its slack was 139 s (#415) and 208 s (#416).
  Authority: `docs/evidence/ci_admission_measurement_2026-11-24.md` §"The correction does not
  rescue #421".
- `axiom-operational-slice` → `readiness-verdict` is a two-job serial chain in one workflow,
  and it was the last finisher in **4 of 5** observed cycles.
  Authority: same document, §"Post-landing re-measurement on canonical main (n=5)".

The contract therefore does not budget *compute*. It budgets **placement**.

This is not a new invention here. ADR-0017 and ADR-0019 already define an incremental
verification engine over work units W1–W11 with a provable-skip rule, and an impact-closure
selector implementing it survives — but it runs in **shadow mode**, writing a report and
executing no gate (`tools/ci/IMPACT_CLOSURE.md`). This contract constrains the part that
selector does not touch: **where new verification may be placed on the required path**. It
forbids (§4 R2/R3) exactly the two workflow-level constructs that would turn a sound selector
into a deadlock or a silent pass, and it requires any reuse to stay inside an always-running
adjudicator emitting an explicit per-unit basis.

## §2. Inherited quantities (no redefinition)

All terms below are used exactly as their owner defines them. A statement that mixes two of
them is invalid by construction.

| term | definition | owner |
|---|---|---|
| `T_admission` | queue entry → merged, per candidate | `docs/evidence/ci_admission_measurement_2026-11-24.md` §"What was measured" |
| `T_queue`, `T_verify`, `T_publication`, `T_merge` | the four non-overlapping phases of `T_admission`; `T_exec = T_verify + T_publication` is **not** a fifth phase | same |
| `wallSeconds` | per-workflow span over a terminal attempt | [ci_critical_path_metric.md](ci_critical_path_metric.md) §2.1 |
| `wall` / `floor` / `ceiling` / `headroom` / `recoverable` | 8-run cohort max, slowest other required workflow, `wall − floor`, gap between 1st and 2nd required finisher, `wall − max(agCF after change, floor)` | `data/ci_optimization/admission_latency_2026-11-24/slack_reconciliation.md` §1 |
| `provisioningFamilySeconds` | sum of `setup-axiom-toolchain` spans in a run | `data/ci_optimization/ci_provisioning_decomposition_2026-11-20/summary.json` |

**Hard rule (inherited, not restated as new)**: `wallSeconds` values from different workflows
are never added or max-folded into an admission wall (metric §2.1). A per-job step span is not
an edge cost (metric §6).

## §3. Two laws

**L-W (maximum, not sum).** `T_admission` is bounded below by the slowest required context.
Work on a context that is not the slowest recovers `min(internal saving, headroom)`, which is
**0** whenever `headroom = 0`. Measured: admission-gate-scoped work had a ceiling of 0 s in
**2 of 10** runs (`slack_reconciliation.md` §2).

**L-M (fixed provisioning dominates the marginal cost).** The cost of adding a verification is
not its verification work; it is the fixed per-job provisioning needed to run it.
Measured: the provisioning composite accounted for **84 %** of `runnerSeconds` on run
`44521587339` (1080 s / 1286 s), and `install_extract` was **899.5 s of 1076.6 s** of that
composite. Cohort-level, the provisioning family was **2574 s of 4669 step-seconds (55.1 %)**
over 5 runs (`data/ci_optimization/ci_critical_path_baseline_2026-11-20/summary.json:145-147`). An A-layer restore costs **~28 s even on an exact key hit**.

Consequence, and the whole point of this contract: **"new verification = new job" is the path
by which CI time accumulates**, not "new verification = new checks". Adding a step to an
already-provisioned job costs approximately its work; adding a job costs provisioning + work.

## §4. Placement rules (normative)

**R1 — Venue admission.** A new verification may be added only in one of these forms:

| form | condition |
|---|---|
| (a) step inside an already-provisioned job | preferred; cost ≈ work |
| (b) job in a required workflow | the workflow's **measured** headroom must be ≥ the job's measured p50 |
| (c) off-chain venue (`schedule`, `push@main`, `workflow_dispatch`) | always admissible; cost is not on `T_admission` |
| (d) coverage plane (`tests/gateway_coverage/`, not consumed by CI gates) | always admissible; see `ci/checker.mk` LANDING_POLICY / coverage split |

A form-(b) admission requires a recorded measurement of the added job's p50 and of the target
workflow's headroom, per metric §1.2 (`n≥5` to decide). Without both numbers the admission is
**not made** — absence of measurement is not evidence of headroom.

**R2 — A required workflow must not be filterable away from a merge candidate.** For every
workflow that publishes a required context:

| trigger key | verdict | enforced by | why |
|---|---|---|---|
| `paths`, `paths-ignore` (either venue) | **FAIL** | `validate_workflow_shell.sh` (R2) | no admissible use on a required context |
| `branches-ignore` (either venue) | **FAIL** | `validate_workflow_shell.sh` (R2) | a deny-list can exclude the trunk |
| `pull_request.branches` allow-list | **admissible iff it covers the trunk** | **review only** (locus, below) | measured present use: `bsec-integrity.yml` declares `branches: [main]`. A literal "no `branches` key" rule would red the tree today and is therefore wrong |
| `merge_group.branches` | **admissible iff it equals the trunk** | **review only** (locus, below) | the queue only carries trunk candidates |

The failure mode is a deadlock, not a silent pass: GitHub leaves the associated checks in
**"Pending"** when a filter skips the run, and a pull request requiring those checks is
**blocked from merging**
(https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs). A
diff-scoped required workflow costs queue time; it saves none. The trunk set must be read from
the required-context policy, not from a second configuration.

**R2 locus — what the gate does not decide.** The policy records no trunk branch, and
introducing one (or a second configuration) is exactly what this rule forbids, so allow-list
*coverage* is **review-enforced, not machine-decided**. That is stated rather than faked
because the residual failure mode is the same visible **Pending** deadlock as the two banned
keys — never a silent pass. The two banned keys have no legitimate use on a required workflow
at all, which is why they can be banned unconditionally without a trunk.

**R3 — No skip-as-success on a required check.** A **required job** — the job id the policy
names, not every job in the workflow — MUST NOT be conditionally skippable. The admissible
`jobs.<id>.if` values are exactly: **absent**, `always()`, `!cancelled()`, or a `&&`-conjunction
of those. Anything else, including `always() && inputs.stage == 'attest'`, is **FAIL**, because
a job skipped by `jobs.<id>.if` reports its status as **"Success"** and does not block merging
even when it is a required check
(https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions).
Venue selection is decided **inside** the job from `github.event_name`, never by skipping it.
Enforced by `validate_workflow_shell.sh` (R3), keyed by the **(workflowPath, job) pair** — never
by job name, which would false-fail the non-required callee job of the same name in
`admission-check.yml`, and never by workflow, because sub-jobs (`go-critical-rollup`, the attest
lanes) are legitimately conditional.

Reuse and scoping are still permitted, but only inside an always-running adjudicator that
emits an **explicit per-unit basis** (`EXECUTED | REUSED`), and a skipped lane MUST fail the
rollup. This is already the repository's pattern, not a new invention:
`admission-check.yml` emits `EXECUTED n/N, REUSED(skip) m` and asserts every GO-critical
judgment carries one of the two, and `go-critical-rollup` fails closed on a skipped or
cancelled lane. The same prohibition is stated for the publication venue as the
"skipped-job = success" platform trap.

**R4 — Cache is acceleration, never evidence.** Verification-result reuse requires the
existing evidence ledger, not a build cache. `src/verification/evidence_ledger.nim` states the
rule ("cache is acceleration, never evidence"), and `admission-check.yml` records it at the
B cache carrier. The GitHub Actions cache is additionally unsuitable as an evidence store on
its own terms: 10 GB per repository default, entries evicted after 7 days without access, a
pull-request cache is created for the merge ref and is restorable **only by re-runs of that same
pull request** — never by the base branch or by another pull request targeting it — and restored
content must be treated as **untrusted input**. (A PR run *can* restore a default-branch cache;
that is what makes the toolchain cache work, and it is also why evidence reuse must not ride it:
the direction of trust is wrong.)
(https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)

**R5 — No second authority.** This contract adds no verdict producer, no check, and no
required context. The required set stays exactly the 7 contexts declared in
`config/policy/merge_admission.json` — six `requiredValidations` entries plus the
`admission-check` verdict job. Per-output authority is unchanged: GitHub owns merge
admission, and a missing or unverifiable fact is `UNKNOWN`/`FAIL`, never `PASS`
(`docs/spec/merge_admission_controller.md` §2 "missing ≠ valid empty").

## §5. Budget

**§5.1 SLO of record — unchanged.** The merge wall SLO of record is **480 s (8 min) P95**, and
it is **policy, not a constitutional invariant**
(`docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` §"The 8-minute P95 is a
policy SLO"). This contract does not replace it, loosen it, or attach a new optimization claim
to it. It was already breached **on its own cohort** — registered baseline p50 923 s and live
p50 1000 s (n=101) against a 480 s *p95* ceiling
(`docs/evidence/p95_attribution_2026-10-16.md:14`). That cohort is a different quantity from
the `T_admission` samples in §5.2 and the two must not be compared as one series.

**§5.2 Admission ceiling — 600 s, and it is not an SLO.** An operator-declared ceiling of
**600 s** on `T_admission` p50 governs **whether new verification may be admitted to the merge
path**. It is deliberately above the SLO of record: breaching the ceiling blocks *growth*;
breaching the SLO is a policy matter with an owner. The ceiling is stated as a count of
seconds for human communication only — see §5.3 for why it can never be a verdict input.

**§5.3 The ceiling is never a verdict input.** Hardware-dependent wall clock must not flip
`PASS`/`FAIL`/`UNKNOWN`: `docs/spec/productization_contract.md:177` states this for the
readiness axis, and the same reasoning applies here — the repository has measured a
**1.4–1.5×** spread between runner VMs on identical work. A seconds-based budget may therefore
produce an **observation** (`OVER_BUDGET`) and a **growth block**, but never a merge verdict.
This is the reason this contract adds no gate: a wall-clock gate would be a hardware-dependent
verdict authority.

**§5.4 The admission test is relative, not absolute.** A candidate verifier is admissible only
if a paired pre/post measurement shows **no increase** in `T_admission` p50 beyond the
measurement noise floor, on the cohort defined by metric §1.2 (`n≥20` for a claim). Comparing
against an absolute number is forbidden, because the three quantities in circulation
(`wallSeconds`, `wall`, `T_admission`) are different objects with different cohorts.

## §6. Overrun semantics

| observation | meaning | what it does | what it does not do |
|---|---|---|---|
| `T_admission` p50 > 600 s | the ceiling is breached | blocks **form-(b)** admission of new verification until a measured reduction lands | does not fail a merge; does not demote a verification to nightly |
| a required workflow is the last finisher | this workflow defines the wall | moves the wall only by shortening it | does not authorize skipping its checks |
| a verifier has no recorded measurement | unknown, not zero | blocks form-(b) admission | is not read as "fits in slack" |

At the time of writing the measured p50 is **639 s** (n=5) and **718 s** max, so the ceiling is
**already breached**. Under this contract, no new form-(b) verifier is admissible until the
Phase 2 reduction lands. Forms (a), (c), and (d) remain open — which is the whole point: the
capability can keep growing off the critical chain immediately.

## §7. Forbidden

- Diff-scoped skip sets for a required context (R2, R3). The repository already refuses
  automatic affected-test selection as nondeterministic (`Makefile:1515`).
- Any new hash scheme, evidence CAS, or planner. `docs/spec/verification_dag_contract.md:19`
  lists "제로베이스 planner/CAS 신규 구축" as a **non-goal**, and `:125` forbids starting
  frontier reuse before Phase 4 closure. Existing reuse surfaces (`evidence_cas`,
  `judgment_cas`, gate memo) are consumed, not re-derived.
- `ciGeneration` (the CI cutover generation number) as an identity input. Existing identity
  wires purge it by contract.
- Treating a cache hit, a workflow conclusion, or a timing metric as evidence.

## §8. Evidence basis

| claim | source |
|---|---|
| `T_admission` p50 639 s / p90 694.8 s / max 718 s; `T_verify` = 94 % | `docs/evidence/ci_admission_measurement_2026-11-24.md` |
| `readiness-verdict` last finisher 4/5; `publication-integrity` never last | same |
| `wall` mean 513 s, floor 85 % of wall, ceiling 0 s in 2/10 | `data/ci_optimization/admission_latency_2026-11-24/slack_reconciliation.md` |
| provisioning = 84 % of `runnerSeconds`; `install_extract` 899.5/1076.6 s | `data/ci_optimization/ci_provisioning_decomposition_2026-11-20/summary.json` |
| lane rebalance rejected; ~110 s fixed per lane; 2–4 s max gain | `data/ci_optimization/vs_ci_01_lane_rebalance_decision_2026-11-22.json` |
| 480 s P95 is policy, not invariant | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` |
| skipped job reports Success; path filter leaves Pending | GitHub Actions documentation (URLs in R2/R3) |
| undeclared inputs make incremental builds incorrect; a bad shared-cache entry poisons everyone | Bazel `docs/sandboxing` |

## §9. Follow-ups (not part of this contract)

1. **Phase 2 — the serial slice chain.** Of the measured **114 s / 21.4 %** of the #415 chain,
   **54.1 s** is two `libpcre3` install steps that a six-tier supply ladder already in the tree
   is expected to remove, and **no run of that ladder has ever been observed**. The first action
   is therefore an **acceptance measurement**, not new provisioning code — the falsifiable
   predictions and the epoch-cutover step list are already recorded in
   `data/ci_optimization/admission_latency_2026-11-24/toolchain_ledger.md`. Remaining residuals
   after that: `provision-scope: nim` on the second job (~18–23 s, but a **two-generation**
   change because a scope switch invalidates the B key and needs a seeded lane), and
   parallelizing the 85 s readiness test suite (the largest single lever; a DAG change that
   needs an explicit fail-closed assertion on the sibling job).
   **Forbidden here**: merging the two jobs — it deletes the `readiness-verdict` context and
   trips the 7-tuple producer closure, i.e. it removes a verification; and a container image —
   the runner is a hosted VM resolved through `vars.CI_RUNNER_MAP`, so there is no image to bake.
   Both files are trust-surface entries; this is an architect/rotation change.
2. **Phase 3 — mechanical enforcement of R2/R3: LANDED in this tree.** Host:
   `tools/ci/validate_workflow_shell.sh`, already invoked from `bsec-integrity.yml` as the
   **BASE copy against the candidate tree**, inside a job that is itself a required context, so
   the marginal wall cost is zero (form (a)) — no new gate, check, context, or Makefile target.
   The predicates read the required set from `config/policy/merge_admission.json` in **BASE**;
   the candidate is never asked what is required. The self-test carries an 8-case decision
   matrix (banned filter → FAIL, disjunctive `if:` → FAIL, `always() && !cancelled()` / bare
   `always()` / `!cancelled()` / absent → PASS, non-required filename with the same filter →
   PASS), and an external mutation of the real `bsec-integrity.yml` (adding `paths:`, or
   conditioning the required job on `github.event_name`) fails with the
   `<required-context-rules>` attribution.
   **Amended scope, stated rather than overstated**: R2's allow-list *coverage* rows and R1's
   headroom condition are **not** machine-decided (see the R2 locus paragraph) — R1 needs a
   trust-surface headroom record and R2 coverage needs a trunk authority, neither of which
   exists; both stay review-enforced.
   **Remaining prerequisite (not a rule, a protection grade)**: the script is **not** in
   `trustSurface`. It is self-protecting only in the weak sense that the BASE copy judges the
   candidate — a landed weakening would govern the *next* PR. Registering it is a policy
   amendment (`config/policy/merge_admission.json` is itself a trust-surface entry) that lands
   through the architect/rotation lane, and is deliberately not bundled here.
3. **Phase 4** — grow capability through forms (a), (c), (d), each judged by a paired
   `T_admission` measurement. Recovery is `min(saving, headroom)` and is **0** in any cycle
   where another required context finishes last, so a chain that shrinks does not by itself
   prove that admission improved.