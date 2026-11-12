# ADR-0017: Trust Claim Authority — Legacy tcVerifiedProof Records are Provenance-Unqualified and MUST NOT Assert Current Verified

## Status

**Proposed (ratified decision points).** This ADR ratifies the *Trust Claim Authority* invariant for Axiom's trust journal, and classifies the historical
`tcVerifiedProof` population as provenance-unqualified (`legacy-unverified`) rather than current verified-truth. It authorizes the WP3-c inventory as the
immutable evidence base. It does **not** authorize operational reader exclusion or batch re-verification of historical records — those are deferred to a
dedicated Debt Work Package (see Consequences → Open Issues).

## Context

The pre-WP3-b trust journal (`data/trusted/journal/`) contained 6,806 `tcVerifiedProof` records at experiment time. The writer that produced them was
`commitVerification(currentDir, tc)` (WP3-b baseline) which did **not** guarantee kernel-proof-evidence binding at creation time. Consequently, the mere
*existence* of a historical `tcVerifiedProof` record is not sufficient evidence that a kernel proof was actually produced when it was written.

Observed population (immutable inventory, `experiments/act2-wp3c-historical-trust-debt/output/manifest.json`, `manifestDigest` =
`a42bf17d0eaf8ef718f3514ba1d3756d9abf47239547c53c1b0089b511e99663`):

| Field | Value |
|---|---|
| recordCount | 6,806 |
| historicalKind | tcVerifiedProof × 6,806 |
| solverInvocation | vault-manifest 6,668 / proof-universe-lock:v33 84 / batch-uap-loop 36 / cert-promotion 18 |
| claimFormat | entries[] 6,668 / graphSnapshot 84 / certificate ("other") 54 |

Re-verification limits:

- `irHash` is a one-way digest (SHA-256 over canonical IR); the `.axiom/vault/` CAS is empty; ~98% of claims carry no fingerprint-family fields; neither
  `verification_scope.lock` nor `baseline.json` pins an exact subject revision. Track-1 *Historical Reconstruction* is therefore low-certainty; Track-2
  *Current Re-verification* is a separate question and is possible.

Actual trust consumers today (all read the legacy journal):

- `src/verification/certificate_verifier.nim:274` (R4 trust closure),
- `src/cli/verify_cli.nim:55` (`ax verify`),
- `src/verification/proof_state_builder.nim:193` (`ax report/status`).

`replayJournal` = `src/core/trusted/trust_commit.nim:399` is all-or-nothing.

External standards basis (independent re-verification): SLSA Threat F (verification cannot substitute for provenance); in-toto §4.3.2 (re-verification is a
new attestation, never a mutation of an existing one); RFC 6962 §3 / §7.3 (append-only immutable ledger); SLSA distributing-provenance (attestation
immutability). In all of these, a historical claim is made immutable and any re-assertion is a *fresh* attestation, never an edit.

---

## 1. Decision — Trust Claim Authority invariant (ratified, non-negotiable)

**A trust artifact may never assert a stronger claim than the strongest evidence actually produced by the current verification run.**

Consequences for writers:

- `tcVerifiedProof` is **Verified-only** — it may be committed only when the current run produced kernel-acceptance-grade proof evidence (WP3-b gate).
- `Vacuous`, `Unknown`, `Unsupported`, `NoObligation`, and failure results MUST NOT be materialized as `tcVerifiedProof` trust-records.
- A trust artifact owns its truth status; the runtime context (`cwd`, `repoRootForPath()`) MUST NOT be the authority that decides artifact ownership or the
  strength of a claim.

Rationale (from WP3-b evidence): a `solverMethod=smNone` record was previously written as `tcVerifiedProof` (TrustCommit's semantic validation was too
weak). The WP3-b three-stage gate closes the *creation* path. This ADR closes the *interpretation* path — it makes the historical population's weak
provenance a first-class fact instead of an implicit truth.

## 2. Decision — Historical population classification (ratified)

The 6,806 legacy records are classified as **`legacy-unverified`**:

- They are **provenance-unqualified**: their creation-time evidence binding is not established.
- This is **not** a verdict that all 6,806 are false. Some may have been genuinely kernel-proved. The classification is *insufficient provenance to treat as
  current verified-truth*.
- They are preserved **immutably**; none are deleted, edited, or rewritten. The immutable inventory pins each record's original sha256 and revalidation
  status.

This classification is recorded in:

1. `data/debt_registry.json` → **DEBT#445** (`Trust / Evidence`, severity high, open).
2. `experiments/act2-wp3c-historical-trust-debt/output/manifest.json` — the execution-derived inventory (one entry per journal file, with
   `journalPath`, `originalSha256`, `historicalKind`, `historicalSolverInvocation`, `historicalClaimFormat`, `revalidationStatus="legacy-unverified"`).
3. `docs/spec/trust_revalidation_protocol.md` — the two-track re-verification protocol.

## 3. Decision — Re-verification protocol shape (ratified, execution deferred)

The three-phase model is **quarantine → revalidation → promotion**:

```
Historical Journal → Quarantine → Deterministic Revalidation → { Verified → promote } | { Not verified → retain as historical }
```

- **Quarantine** (this WP3-c): classify + pin immutably. No reader change.
- **Revalidation** (future Debt WP): present each historical claim to the **current canonical verification pipeline** (never a legacy verifier), produce a
  linkage digest binding the historical record to the current result, and classify as `Revalidated` / `FailedRevalidation` /
  `NotReconstructable` / `SemanticallyChanged`.
- **Promotion**: only `Revalidated` records may be re-issued as *new* current trust records. Historical records are never mutated.

Two independent tracks:
- **Track-1 Historical Reconstruction** — reconstructing the original canonical input from the artifact. Low certainty (see Context).
- **Track-2 Current Re-verification** — re-running the current pipeline against a reconstructible subject revision. Separate and possible.

## 4. Consequences

- **New records** are guarded by the WP3-b gate; the creation path is closed.
- **Historical records** remain readable by current consumers (`ax verify/report/status`, R4 trust closure) — see Open Issues for the deferred reader
  exclusion.
- `check-debt` is red at this commit for **pre-existing** reasons (HEAD baseline already showed `debt_registry_open` drift and `nimtry_violations` drift
  before DEBT#445; the WP3-b working-tree edits also leave `architecture_debt.json` canonical syntax hashes stale). DEBT#445 correctly moves
  `debt_registry_open` projection from 17 → 18. This ADR/DEBT does not fabricate a green state by silently updating the budget ledger or regenerating
  architecture hashes; that reconciliation is tracked as open work.
- No `verification_scope.lock`, journal schema, VKD, certificate schema, or Act-1 gate is changed by this ADR.

### Open Issues

1. **Operational reader exclusion** — `certificate_verifier.nim:274`, `verify_cli.nim:55`, `proof_state_builder.nim:193` may still consume legacy records
   until a reader-enforcement WP marks `legacy-unverified` records as non-authoritative. This WP3-c is classification + inventory only.
2. **Retention policy is unresolved** — the historical population is *integrity-pinned*, but its retention (permanent archive vs lifecycle endpoint) is not
   decided.
3. **Budget-ledger reconciliation** — updating `data/debt_ledger.json` BUDGET#005 `current` (16 → 18) and the `nimtry_violations`/`architecture_debt`
   drift is deferred and must not be done opportunistically.

## References

- `src/core/trusted/trust_commit.nim` (pre-WP3-b writer; WP3-b gate).
- `src/verification/certificate_verifier.nim:274`, `src/cli/verify_cli.nim:55`, `src/verification/proof_state_builder.nim:193`.
- `data/debt_registry.json` DEBT#445; `data/debt_ledger.json` BUDGET#005.
- `experiments/act2-wp3c-historical-trust-debt/` (tool, manifest, analysis, result).
- `docs/spec/trust_revalidation_protocol.md`.
- External: SLSA Threat F; in-toto §4.3.2; RFC 6962 §3/§7.3; SLSA distributing-provenance.
