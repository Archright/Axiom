# ADR-0037: The Operational Slice as a Required Check

- **Status**: Accepted (2026-10-22)
- **Authority**: merge admission — GitHub ruleset 20303214 (P12 delegation: GitHub enforces, Axiom records identity)
- **Policy SSOT**: `config/policy/merge_admission.json` v1.17.0
- **Predecessors**: ADR-0025 (gateway landing authority), ADR-0035 (admission SSOT), ADR-0036 (GPA v1)

## Context

Before this decision, no required check ran the product's own verification path.
The four live contexts (admission-check, bsec-integrity, debt-registry-gate,
generation-acceptance) enforced admission, ledger, and policy coherence — none
executed `ax prove`, and `ax cert verify --kernel` was dead code in CI: the G7
target's certificate leg read `nodeReports[].vaultPath`, which is empty for
UAP-verified nodes, so `bin/ax cert verify` never ran. The product's verification
result therefore had no merge authority: a PR could land while the proof path it
carried was never observed by the authority that admits it.

Separately, `ax report --json` exits 0 whenever `failedCount == 0 ∧ timeoutCount
== 0`, regardless of `runOutcome.verdict`/`gateVerdict` — a fail-open seam
(documented at `docs/spec/execution_accounting_contract.md` §6a) that CI could
not distinguish from success.

## Decision

1. **One required check runs the real proof path.** `axiom-operational-slice`
   (workflow id 392498537, path `.github/workflows/axiom-operational-slice.yml`)
   is registered as the fifth required context on ruleset 20303214
   (integration_id 15368). The job runs `make verify-contract-release-e2e-full`:
   `ax prove --target normalizeMaxWorkers` → certificate resolution from the
   vault manifest → `ax cert verify --kernel` on the SAME certificate →
   run↔cert execution-identity join → FRESH-SATISFIED unit assert → direct
   assertion of `runOutcome.verdict/gateVerdict`.
2. **The verdict assertion closes the CI fail-open.** The check fails whenever
   the report verdict is not PASS — the product-level exit projection
   (pinned trusted-checker files) is a separate rotation follow-up; the check
   does not wait for it.
3. **Operator-PUT-first ordering.** The workflow landed through the merge queue
   (PR #1040) BEFORE the ruleset PUT, so the GPA L2 promotion-pending exception
   (`generation-acceptance` only) was never exercised and stays hardcoded.
4. **The negative control is part of the activation contract.** A deliberately
   falsified postcondition (`normalizeMaxWorkers` `return 1` → `return 0`, PR
   #1041) MUST fail the check and block the merge. Measured: check FAILURE,
   `isRequired=true`, `mergeStateStatus=BLOCKED`, closed without merge.
5. **Evidence is a first-class artifact.** The check emits
   `axiom.run-manifest.v1` (`tools/ci/run_manifest.jq`,
   `docs/spec/run_manifest_contract.md`) joining state + certificate + report +
   exit codes, uploaded with its SHA-256 digest. Digest equality is a
   reproducibility claim, not a correctness claim (correctness = Lean kernel
   re-execution + Z3 + negative control).
6. **The mirror is double-bound in the same commit.** `requiredValidations`
   gains the entry (workflowPath + workflowId 392498537 + job + success), and
   `src/cli/merge_cli.nim` `RequiredChecks`/`RequiredWorkflowIds` gains the same
   identity — one-sided updates turn the drift monitor leg 1 RED. The
   architecture-debt canonical hash and the trustedCheckerTreeClosure blob sha
   are re-anchored as rotation companions. This PR lands through the rotation
   path (trustSurface hit: `TRUST_SURFACE_MODIFIED`, manual merge lane).

## Consequences

- A PR that breaks a declared postcondition of a verified kernel symbol is now
  blocked by the merge authority itself, in addition to the local gates and the
  vault-certificate identity checks.
- The check costs ~9 minutes per PR and merge-group entry (a real Lean kernel
  re-execution). The check is on `pull_request` + `merge_group` + `push: main`
  with no conditional skip — a skipped required check reports success.
- The cold-cache precondition (`lake build ircheck` in `proofs/`) is explicit in
  the workflow; a missing reference extractor demotes the node to
  NOT_VERIFIABLE and fails the check (first-run observation, fixed).
- Follow-ups (separate rotations): the product-level report exit projection
  (read the verdict axis, `verified==0` fail-closed); extending the slice beyond
  one symbol.

## References

- PR #1039 (surface policy v85 — the workflow path CONTROLLED registration)
- PR #1040 (the operational slice: G7 binding + workflow + manifest contract)
- PR #1041 (negative control — closed without merge)
- `data/promotions/axiom-operational-slice-activation/manifest.json`
- `docs/spec/run_manifest_contract.md`, `tools/ci/run_manifest.jq`
