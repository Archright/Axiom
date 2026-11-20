# ADR-0041 — Free Authority Migration: Repository Ruleset + Independent Verifier App

- **Status**: Accepted (activation performed 2026-11-17; post-landing acceptance recorded in `docs/evidence/free_authority_migration_phase0_proof.md` §8–§9)
- **Date**: 2026-11-17
- **Supersedes (limited)**: ADR-0027's org-required-workflow subordination, ADR-0035's "org-injected producer" clause, and ADR-0036's L2 hardcoded `integration_id == 15368` — **only to the extent** those texts require an Organization ruleset or the GitHub Actions app as the producer of the `admission-check` context. All other clauses remain in force.

## 1. Context

The `Archright` organization plan is `free`. Organization rulesets `25218071` and `23943917` are unavailable (`GET /orgs/Archright/rulesets` → `403 Upgrade to GitHub Team`) and are no longer part of the enforcement chain. This does **not** remove the security purpose that the org ruleset served. The purpose is unchanged:

> A PR cannot verify itself, an independently trusted verifier judges the exact commit, and GitHub refuses the merge without that judgment.

The repository ruleset `27097366` (`main`, active, `bypass_actors: []`, 7 required contexts, merge queue `MERGE/ALLGREEN`, `max_entries_to_build: 2`) remains the merge authority. The `admission-check` context is now published by the independent GitHub App `axiom-admission-verifier` (id `5795152`), which verifies:

1. the workflow run is `.github/workflows/admission-gate-v2.yml`, event matches the venue, `head_sha` is the judged commit, and `conclusion == success`;
2. every path in `config/policy/trust_surface_manifest.json` has `blob(G) == blob(B_mg)` (manifest read from `B_mg`);
3. the subject-continuity ledger gained exactly one entry bound to `(base, PR head)` in the merge-group venue.

The technical cutover was executed at 2026-11-17T06:29Z. It exposed a hardcoded consumer: `generation-acceptance.yml` L2 required `all(integration_id == 15368)`, so its ruleset name resolution turned `RULESET_UNAVAILABLE` and failed closed (measured on PR #135, run `44032936628`). The verifier gate itself worked (PR #131 merged through the queue at `06:39:09Z`, G=`c955dfce`), but generation-surface PRs could no longer pass GPA. This ADR records the policy correction that closes that gap.

## 2. Decision

1. **GitHub remains the merge authority.** Axiom does not reimplement merge admission. Repository ruleset `27097366` is the enforcement surface; `bypass_actors` stays `[]` outside audited break-glass windows.
2. **The expected producer is policy data, not a constant.** `config/policy/merge_admission.json` gains `requiredCheckSources`:
   - `default: 15368` (GitHub Actions app) for every context not listed;
   - `byContext.admission-check: 5795152` (the independent verifier App).
   An absent map keeps the legacy meaning (all contexts from the Actions app), so a pre-v1.24.0 policy is judged on its own shape rather than silently reinterpreted.
3. **Every judgment consumer derives the source from the policy.** GPA L2/L4 (`generation-acceptance.yml`), `tools/merge_ruleset_drift_monitor.nim` (leg 2 and leg 3), and `tools/ci/landing_observe.sh` read `requiredCheckSources`. No hardcoded app id remains in a judgment path.
4. **The orchestrator identity is repository-native.** `requiredWorkflowDetection.repositoryId` moves `1182157951` → `1454952493`; the workflow path stays `.github/workflows/admission-gate-v2.yml` with `verdictJob: admission-check`. `verdictCheckSource` records the App identity.
5. **The verifier contract is unchanged.** This ADR does not alter the App's four merge-group conditions, the PR-venue preflight, the ledger binding, or the certificate-mint caller-path guard. It only realigns the policy and its consumers with the authority that is already enforcing.
6. **Trust-surface PRs do not ride the auto-merge queue.** This amendment touches `.github/workflows/generation-acceptance.yml` and `config/policy/merge_admission.json`; both are trust-surface paths, so the amendment lands through the audited break-glass lane (MUST-T2a: bypass activation → native merge → bypass restoration, all timestamps and readback recorded).

## 3. Consequences

- A PR that defines its own job named `admission-check` cannot satisfy the required context: the ruleset accepts only check runs produced by App `5795152`. The Actions app may still publish a same-named check; it is ignored.
- Generation-surface PRs pass GPA L2 again after the amendment: the expected-source map now matches the live ruleset.
- The verifier App is an availability dependency. If it does not publish a conclusion within the queue's `check_response_timeout_minutes: 120`, the entry fails closed; it never defaults to success.
- **Residual (documented, not erased)**: the within-Actions same-name residual remains for the six Actions-owned contexts. Their recorded `requiredValidations` workflow-identity bindings are judgment-reference records, not merge-time re-verification (P12 delegation retained).
- **Follow-ups** (outside this ADR's scope, recorded for the debt lane):
  - `config/app_landing_binding.json` still carries the stale Landing App id `4879411`.
  - Ruleset `27097369` (`refs/heads/cas-probe/*`) still lists the uninstalled App `4879411` as a bypass actor. **Readback correction (2026-11-19)**: live `GET /repos/Archright/Axiom/rulesets/27097369` returns `bypass_actors: []`, `current_user_can_bypass: "never"`, `updated_at: "2026-11-17T17:13:56.898+09:00"` (name `cas-probe-scratch`, enforcement `active`). The bypass actor is no longer present; the sentence above is retained as the observation that motivated the follow-up. This follow-up item is satisfied by the readback; the other follow-ups in this list are unchanged.
  - The narrative comment block in `src/cli/merge_cli.nim` still describes the org-injected producer; it is non-normative and will be re-anchored with its canonical hash in a follow-up.

## 4. Acceptance

The migration is accepted only when all of the following are observed and recorded:

| Condition | Evidence |
|---|---|
| Repository ruleset active with 7 contexts, `bypass_actors: []` | ruleset readback |
| `admission-check` expected source = App `5795152`; other 6 = `15368` | ruleset readback + policy |
| GPA L2 name resolution passes against the live ruleset | GPA `L2.result = OK` on a generation-surface probe |
| App publishes `admission-check` on a merge-group commit and GitHub merges natively | ≥2 merge-queue landings, G ↔ App summary ↔ merge commit |
| Trust-surface tamper PR is refused by the queue | negative-control PR with Actions-produced fake success remains unmergeable |
| Ledger entry bound to `(base, PR head)` | App summary `ledger=PASS` |
| Policy/live drift window closed | policy v1.24.0 landed + ruleset readback after landing |