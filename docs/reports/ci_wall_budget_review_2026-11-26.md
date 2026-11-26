# CI wall-clock budget review record - rebuttal of the proposed "Evidence-First Incremental CI" and the scope adopted

> **Purpose**: answer the question "can CI be held under 10 minutes while verification capability keeps
> growing?" by rebutting the submitted design (diff-scoped execution -> L0/L1/L2 tiers -> input_closure_digest-based
> Evidence CAS -> license scan reuse as the first slice) against repository measurements and external
> official documentation, and keeping only the scope that can be adopted.
> **Date**: 2026-11-26
> **Method**: cross-check against the repository's normative documents and measured data, **retrieval of the
> original GitHub Actions / Bazel official documentation through Context7 MCP** (quoted in §2), and 4 independent
> audits (CI topology / verification that the existing mechanisms already exist / license scan
> feasibility / constitutional critique).
> **Deliverable**: this record **creates no authority of any kind**. The normative rules are
> owned by `docs/spec/ci_admission_budget_contract.md`; this document is the audit record that preserves
> the grounds on which those rules stand.

---

## 1. Verdict summary

| proposed claim | verdict | basis |
|---|---|---|
| Evidence reuse (Proof Unit + `input_closure_digest` CAS) is a new architecture | **Rejected - it already exists, and building it anew is forbidden** | `src/verification/evidence_cas.nim` (SL-15), `src/verification/judgment_cas.nim` (4 GO-critical subjects), `src/gate/orchestrator/hook/memo.nim` (gate memo). `docs/spec/verification_dag_contract.md:19` lists "building a zero-base planner/CAS anew" as a **non-goal**, and `:130` enumerates it among the forbidden items |
| Skip unrelated changes by diff/impact scope | **Rejected - under GitHub semantics this deadlocks or passes silently** | Skipping a required workflow through `paths:` -> the check stays Pending -> the merge is blocked. Skipping the job through `if:` -> it **reports "Success"** (it passes even when required). The repository has already codified the same trap |
| The accumulation of CI (number of gates) is what drives the wall-clock rise | **Rejected - fixed provisioning dominates** | The composite is **84%** of `runnerSeconds` (run `44521587339`: 1080/1286), and `install_extract` is 899.5/1076.6s. The maximum gain from lane rebalancing is 2-4s -> **VS-CI-01 REJECTED** |
| `Operational slice 341s = production 132s + verdict 209s` | **Rejected - forbidden summation** | `docs/spec/ci_critical_path_metric.md` §2.1: `wallSeconds` values from different workflows are never added or max-folded. `T_exec` is `T_verify + T_publication` and is not a fifth phase |
| The 10-minute ceiling can be "designed" | **Conditional - it is already breached, and a second-granularity budget cannot be a verdict input** | `T_admission` p50 **639s**, p90 694.8s, max 718s (n=5). And `docs/spec/productization_contract.md:177`: a hardware-dependent wall-clock cannot flip PASS/FAIL/UNKNOWN |
| License scan reuse is "the safest first slice" | **Rejected - wall contribution 0 and the highest landing cost** | publication-integrity is not the last finisher in any observed cycle. On top of that it is a trust-surface path, and the scanner pin is only a version string (DEBT#567), so the key is not hermetic |
| Use the cache as an evidence store | **Rejected** | `src/verification/evidence_ledger.nim` "cache is acceleration, never evidence". The GitHub cache is 10GB per repository, entries untouched for 7 days are evicted, PR caches are scoped to the merge ref, and restored content is untrusted |
| A matching input digest alone allows the result to be reused | **Precondition unmet** | Most gates depend on git history and host paths, so a sound closure digest for every gate cannot be computed today. Bazel documentation: an undeclared input yields an *incorrect incremental build*, and a bad entry in a shared cache poisons the whole team |

## 2. Facts confirmed against external official documentation

1. **A path filter deadlocks a required check.** GitHub Actions documentation (Manage workflow runs ->
   Skipping workflow runs): when a workflow is skipped by a path/branch filter, "checks associated with that
   workflow will remain in a **Pending** state. A pull request that requires those checks to be
   successful will be **blocked from merging**."
2. **A skipped job is reported as a success.** The same documentation family (Control jobs with
   conditions): "A job that is skipped will report its status as **'Success'**. It will not prevent a
   pull request from merging, even if it is a **required check**."
   -> Together the two facts make diff-scoped tiering **broken at both ends**: a deadlock at the
   workflow level, a silent pass at the job level.
3. **A cache cannot be an evidence store.** Dependency caching documentation: 10GB per repository by
   default, removal of entries not accessed for 7 days, a cache created by a PR is created on the merge
   ref (`refs/pull/.../merge`) so that **only a re-run of that PR** can restore it while the base branch
   and other PRs viewing the same base cannot, and restored files are treated as untrusted input. (Mind
   the direction: a PR run restoring a *default branch* cache is permitted - that is why the toolchain
   cache works, and at the same time why evidence reuse cannot ride the cache. The trust direction is
   the opposite one.)
4. **The soundness condition for incremental reuse.** Bazel sandboxing documentation: with an
   undeclared input, Bazel wrongly judges the target up to date and produces an *incorrect incremental
   build*. A bad entry in a shared cache affects every developer ("a bad cache entry in a shared cache
   affects every developer on the project").

These 4 items were confirmed on 2026-11-26 to match the original text retrieved through Context7 MCP
(`/websites/github_en_actions`, `/bazelbuild/bazel`). These 4 are the whole set of external claims that
repository measurements do not rebut, and the remaining verdicts (§1) rest on the repository's normative
documents.

## 3. Repository measurements (normative)

| quantity | value | source |
|---|---|---|
| `T_admission` (n=5) | p50 **639s**, p90 694.8s, min 588, max 718 | `docs/evidence/ci_admission_measurement_2026-11-24.md` |
| phase breakdown | queue 3% / **verify 94%** / publication 0% / merge 2% | same |
| last finisher | `readiness-verdict` **4/5**, `publication-integrity` 0/5 | same |
| publication slack | 139s (#415) / 208s (#416) -> removal effect **0 against T_admission** | same |
| `wall` / floor / ceiling (n=10) | 513s / 435s(85%) / 78s, **0 in 2/10** | `data/ci_optimization/admission_latency_2026-11-24/slack_reconciliation.md` |
| serial chain (#415) | 533s = slice job 304s + readiness 227s, provisioning **114s(21.4%)** | same, §"Where the time actually goes" |
| `Prove, replay the same certificate` | 205s (#415), 277s (#416) = 38-48% of the chain | same |
| provisioning share | composite 84% of runnerSeconds (run 44521587339, 1080/1286); `install_extract` 899.5/1076.6s; `libpcre3` installation 1542.1s over 40 runs (79% fetch) | `data/ci_optimization/ci_provisioning_decomposition_2026-11-20/summary.json` |
| provisioning cohort share | provisioning family 2574s / step-seconds 4669s = **55.1%** (n=5) | `data/ci_optimization/ci_critical_path_baseline_2026-11-20/summary.json:145-147` |
| A-layer exact HIT cost | **~28.3s** - raising the hit rate further cannot push below this floor | `docs/evidence/ci_admission_measurement_2026-11-24.md` |
| lane rebalancing | max gain 2-4s, ~110s fixed per lane -> **REJECTED** | `data/ci_optimization/vs_ci_01_lane_rebalance_decision_2026-11-22.json` |
| SLO of record | **480s P95**, a policy and not a constitutional invariant, already breached at p50 | `docs/evidence/ci_wall_clock_optimization_acceptance_2026-10-07.md` |

## 4. Adopted / rejected

**Adopted**

- The principle that cost should be proportional to **the amount of invalidated evidence** rather than to the
  total number of verifiers - with the caveat that this is the `runnerSeconds` law and not the
  `T_admission` law.
- Missing and uncertain are `UNKNOWN`, not `PASS` (`docs/spec/merge_admission_controller.md:57`
  "missing ≠ valid empty").
- The 3-tier idea - it has already landed as `venue split` (ADR-0043: `pull_request`=preflight `{secret-scan}`,
  `merge_group|schedule|dispatch`=full landing). The criterion for choosing a tier is **irreversibility,
  not cost**.

**Rejected**

- diff-scoped skip set (deadlock/silent pass; `Makefile:1515` already forbids automatic selection).
- Turning a second-granularity budget into a verdict input (`productization_contract.md:177`, 1.4-1.5x spread
  between VMs).
- Describing "600 seconds" as the completion of the 10-minute ceiling - 600 seconds is a **ceiling**, not an
  SLO, and it does not replace the SLO of record (480s P95). Making 600 seconds the target quietly lowers the
  existing promise.
- Making license scan reuse the first slice (effect 0, maximum landing cost, a non-hermetic key).
- Building a new Evidence CAS / planner (`verification_dag_contract.md:19`, `:125`, `:130`).

**Lineage - this repository already attempted this design, and the contract was retired**

The proposer's L0/L1/L2 tiers and incremental reuse are not a new invention. ADR-0017 (incremental
verification engine) and ADR-0019 (verification tier scheduling) already defined the Work Unit W1-W11 model,
`inputClosure`, the "skip only when provably false" rule, and the L0/L1/L2 safety ladder, and
`tools/ci/impact_closure_selector.nim` survives as an implementation of that selector in **shadow mode**
(producing a report without executing a gate).

The important fact is that its normative contract `docs/spec/incremental_ci_contract.md` was **deleted by the
CI=0 cutover (2026-09-20)**, and that `data/selector_soundness/mutation_catalog.json:170` records it as
"reassigned to the surviving normative contract `docs/spec/productization_contract.md`". In other words this
axis survives as **a tool without a contract**. This work therefore did not revive the deleted contract; it put
into the new normative document **only the minimum pieces needed (placement rules over the required context)**.

Incidental finding (not fixed, out of scope): `tools/ci/IMPACT_CLOSURE.md:5` is still a dangling reference that
cites that deleted contract as normative, and it is not registered in `data/debt_registry.json` (DEBT#468,
which points at the same file, registers only the `canonical_execution_semantics.md` side).

## 5. What this record does not claim

- **It does not claim a distribution.** n=5 and n=10 are the first operational window, and p90 is an arithmetic
  value. An SLO claim requires `n≥20` from metric §1.2.
- **It does not claim an improvement.** This work only measured and codified the rules; it applied no
  optimization of any kind.
- **The 205-277s of the `Prove` step is still unattributed.** It is 38-48% of the chain, yet there is no
  step-level decomposition of the cause. That measurement must come first, before any budget claim is made on
  top of this contract.
- **The wait a user experiences is longer than `T_admission`.** The end-to-end tail is dominated by events and
  human waits, and no CI ceiling bounds that value.

## 6. Change in authority

None. This record adds no verdict, gate, check, or required context, and it changes neither the 7 required
contexts in `config/policy/merge_admission.json` nor its trustSurface.
Phase 2 (removing duplicate provisioning) touches trust-surface files, so it needs a separate architect/rotation
path.

## 7. Follow-up landing record - Phase 3 (mechanical enforcement of R2/R3)

Phase 3 of contract §9.2 landed in the same work. No new gate, check, required context, or Makefile target was
created; predicates were added to `tools/ci/validate_workflow_shell.sh` (the BASE copy), which already runs
inside the already-required `bsec-integrity` - contract §4 form (a) for R1, so the marginal wall-clock cost is
0.

- **Enforced**: `paths` / `paths-ignore` / `branches-ignore` on a required workflow (R2), and the `if:`
  whitelist of a required **job** - absent / `always()` / `!cancelled()` / their `&&` combinations (R3).
- **Not enforced (stated as the locus in the document)**: allow-list **coverage** (whether the trunk is included)
  and the headroom condition of R1. The trunk's normative list is absent from policy, and creating a second
  configuration is exactly the act R2 forbids. The failure mode of this residue is not a silent pass but a
  **visible Pending deadlock**.
- **Verification evidence**: the self-test verdict matrix 8/8 (a forbidden filter -> FAIL, a disjunctive `if:` ->
  FAIL, `always() && !cancelled()` / `always()` / `!cancelled()` / absent -> PASS, the same filter in a
  non-required file -> PASS), 2 kinds of external mutation of the real `bsec-integrity.yml` (each FAIL with
  attribution to `<required-context-rules>`), and 0 cases in the unmutated control.
- **Remaining precondition**: this script is not yet in `trustSurface`. Because the BASE copy judges the candidate,
  a weakening inside a candidate PR is inert for that PR, but **a landed weakening becomes the BASE of the next
  PR**. Registering it is an amendment of `config/policy/merge_admission.json` (itself trust-surface), so it
  belongs to the architect/rotation lane, and it was not bundled into this change.
