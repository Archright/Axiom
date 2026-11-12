# WP3-c Analysis — Historical Trust-Artifact Integrity

> EXPERIMENT-ONLY / not canonical execution path / not production API.
> Classification + immutable inventory of the historical trust journal. No operational
> quarantine (reader exclusion) and no batch re-verification are performed here.

## Question

The pre-WP3-b trust journal holds 6,806 `tcVerifiedProof` records whose creation-time evidence binding is unqualified.
What is the exact population, what is its integrity evidence, and how should it be recorded honestly (DEBT + ADR +
inventory + protocol) without mutating any historical record?

## Context

- EXPERIMENT_ID: `act2-wp3c-historical-trust-debt`
- Scope: `data/trusted/journal/` (6,806 JSON records at experiment time), WP3-b writers and WP3-b-gate.
- Artifacts: `legacy_trust_audit.nim` (generator), `output/manifest.json` (inventory), DEBT#445, ADR-0017,
  `docs/spec/trust_revalidation_protocol.md`.

## Localization — why the population is provenance-unqualified

1. **Writer did not gate.** Pre-WP3-b `commitVerification(currentDir, tc)` wrote `tcVerifiedProof` without a
   hard kernel-evidence gate (`src/core/trusted/trust_commit.nim`, pre-WP3-b reducer in
   `src/verification/proof_universe_commit.nim`). A record's existence did not imply a kernel proof was produced.
2. **Weak semantic validation.** A `solverMethod=smNone` record was previously written as `tcVerifiedProof` —
   TrustCommit's semantic validation was too weak to reject a claim stronger than the evidence (ADR-0017 §1 rationale).
3. **WP3-b closed the creation path.** The WP3-b three-stage gate (`test_wp3b_verifiedproof_gate.nim`, 7/7) now
   requires hard kernel evidence before `tcVerifiedProof`. This fixes the *future*; the 6,806 existing records are the
   historical residual.
4. **Re-verification limits.** `irHash` is one-way (SHA-256 over canonical IR); `.axiom/vault/` CAS is empty; ~98% of
   claims carry no fingerprint-family fields; neither `verification_scope.lock` nor `baseline.json` pins an exact
   subject revision. Track-1 (Historical Reconstruction) is low certainty; Track-2 (Current Re-verification) is
   separate and possible.

## Trust consumers (authoritative read points)

| Consumer | Location | Uses journal via |
|---|---|---|
| R4 trust closure | `src/verification/certificate_verifier.nim:274` | `readCommit` |
| `ax verify` | `src/cli/verify_cli.nim:55` | `replayJournal` |
| `ax report/status` | `src/verification/proof_state_builder.nim:193` | `replayJournal` |

`replayJournal` = `src/core/trusted/trust_commit.nim:399` (all-or-nothing, fail-closed).

## Inventory (execution-derived, deterministic)

Generator `legacy_trust_audit.nim` — stdlib-only (json/sha256-inline/algorithm/strutils), **no product imports**,
EXPERIMENT-ONLY header. Deterministic: byte-order sorted journal paths, fixed key order, no timestamps, no fs metadata.
Per-record `journalPath / originalSha256 / historicalKind / historicalSolverInvocation / historicalClaimFormat /
revalidationStatus`. `manifestDigest` = sha256(canonical manifest JSON bytes).

Observed:

- recordCount = 6,806; kind = tcVerifiedProof × 6,806.
- solverInvocation = vault-manifest 6,668 · proof-universe-lock:v33 84 · batch-uap-loop 36 · cert-promotion 18.
- claimFormat = entries[] 6,668 · graphSnapshot 84 · certificate/other 54.
- `manifestDigest` = `a42bf17d0eaf8ef718f3514ba1d3756d9abf47239547c53c1b0089b511e99663`.

Cross-validation:
- 50/50 random sampled `originalSha256` values matched Python `hashlib.sha256` (inline SHA-256 correctness).
- manifestDigest independently reproduced by Python over the body-before-digest byte range.
- RunA / RunB byte-identical (determinism).

## Journal integrity (unchanged)

- Baseline directory hash (sha256sum of all 6,806 journal files + basenames) captured before; the audit tool performed
  only reads. Journal files were not modified, created, or deleted by this WP.

## Registration

- DEBT#445 (`Trust / Evidence`, severity high, open) — records the population and pins `manifestDigest`.
- ADR-0017 — Trust Claim Authority invariant + classification + deferred protocol.
- `docs/spec/trust_revalidation_protocol.md` — two-track re-verification protocol.

## check-debt baseline note

`check-debt` is red. Baseline (HEAD debt files, before DEBT#445): 66/66 entry checks passed but Validation FAILED due to
pre-existing 2 DRIFT metrics (`debt_registry_open` 17 vs ledger 16; `nimtry_violations` 13 vs ledger 0). After DEBT#445:

- DEBT#445 correctly moves `debt_registry_open` projection 17 → 18 (delta 1 → 2 vs the stale ledger `current` 16).
- The `architecture_debt.json` canonical-syntax-hash substantive-change failures are a pre-existing artifact of the
  uncommitted WP3-b source edits (many `src/` files changed), not introduced by WP3-c.

No budget-ledger or architecture-hash reconciliation is performed here (minimal intervention; deferred — see ADR-0017
Open Issues). A green `check-debt` is not fabricated.
