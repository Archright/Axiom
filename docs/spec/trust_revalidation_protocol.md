# Trust Revalidation Protocol — Historical `tcVerifiedProof` Records

> **Status:** Ratified by ADR-0017 (Trust Claim Authority). This document defines the **protocol** for handling
> historical trust-journal records whose provenance is unqualified. It does **not** authorize operational reader
> exclusion or batch re-verification today; those are deferred to a dedicated Debt Work Package (open issues below).
>
> Scope: this WP3-c artifact is **classification + immutable inventory**. Where this document speaks of
> "quarantine" / "revalidation" / "promotion", it describes the *design* and the *future execution contract*, not
> an already-executed operational state.

## 1. Problem

The pre-WP3-b trust journal (`data/trusted/journal/`) holds 6,806 `tcVerifiedProof` records. The creating writer
(`commitVerification(currentDir, tc)`) did not guarantee kernel-proof-evidence binding at write time. Therefore, the
**existence** of a historical `tcVerifiedProof` record is not sufficient evidence that a kernel proof was produced when
it was written.

This is not a claim that all 6,806 are false — some may be genuinely kernel-proved. The correct classification is
**insufficient provenance to treat as current verified-truth**: the population is `legacy-unverified`.

## 2. Core invariant (ADR-0017)

> **A trust artifact may never assert a stronger claim than the strongest evidence actually produced by the current
> verification run.**

Any downstream artifact (`tcVerifiedProof`, certificate), and any trust consumer that reads it, must not out-claim the
verification result that produced it. Concretely: `Vacuous`, `Unknown`, `Unsupported`, `NoObligation`, and failure
results MUST NOT be committed as `tcVerifiedProof`. `tcVerifiedProof` is **Verified-only**.

## 3. Three-phase model

```
Historical Journal → Quarantine → Deterministic Revalidation → { Verified → Re-issue (new record) }
                                                             { Not verified → Retain as historical }
```

### Phase 1 — Quarantine (executed in WP3-c, this document's subject)

Objective: make the historical population's untrusted status explicit and its bytes immutable, **without modifying any
journal record**.

- A `legacy-trust-audit` manifest enumerates each journal file deterministically.
- Each manifest entry binds `journalPath → originalSha256` plus a `revalidationStatus = "legacy-unverified"`.
- Historical records are **never deleted, edited, or rewritten**.
- Scope boundary: WP3-c performs **classification + inventory only**. Operational reader exclusion (making
  `legacy-unverified` records non-authoritative to `ax verify/report/status` and the R4 trust closure) is a separate,
  later Debt WP.

### Phase 2 — Revalidation (future Debt WP)

Each historical claim is presented to the **current canonical verification pipeline** (never a legacy verifier). The
claim is classified by the pipeline's actual outcome:

| Revalidation status | Meaning |
|---|---|
| `Revalidated` | Current canonical path produced a real kernel proof for the reconstructible claim. |
| `FailedRevalidation` | Current pipeline produced a proof failure. |
| `NotReconstructable` | Original input / environment cannot be reconstructed (provenance insufficient). |
| `SemanticallyChanged` | Current semantics differ from historical semantics; the claim is not reproducible as-is. |

### Phase 3 — Promotion (future Debt WP)

Only `Revalidated` records may be **re-issued as new** current trust records. Historical records are never mutated; a
revalidation that succeeds produces a *new* record in the current trust journal, linked to the historical one.

## 4. Determinism of revalidation

Each revalidation MUST bind a linkage digest committing the full input/evidence chain:

```
revalidationDigest =
    sha256(
        historicalRecordDigest
      + sourceFingerprint
      + dependencyFingerprint
      + toolchainFingerprint
      + executionContractDigest
      + currentVerificationResult
      + currentEvidenceDigest
    )
```

Equal historical input + equal verification contract ⇒ equal revalidation result, so the revalidation outcome is
reproducible.

## 5. Two independent tracks

- **Track-1 — Historical Reconstruction:** reconstructing the original canonical input from the historical artifact
  alone. **Low certainty** because `irHash` is one-way, the `.axiom/vault/` CAS is empty, ~98% of claims carry no
  fingerprint-family fields, and neither `verification_scope.lock` nor `baseline.json` pins an exact subject revision.
- **Track-2 — Current Re-verification:** re-running the current pipeline against a reconstructible subject revision.
  **Separate and possible.** Re-verification is a *new* attestation (in-toto §4.3.2), never an edit to an existing one.

## 6. Inventory artifact (WP3-c)

Generator: `experiments/act2-wp3c-historical-trust-debt/legacy_trust_audit.nim`
(EXPERIMENT-ONLY — not canonical execution path — not production API; stdlib-only, no product imports).

Output: `experiments/act2-wp3c-historical-trust-debt/output/manifest.json`

- Deterministic: records processed in byte-order by canonical journal path; fixed key order; no timestamps; no
  filesystem metadata.
- Per-record fields: `journalPath`, `originalSha256`, `historicalKind`, `historicalSolverInvocation`,
  `historicalClaimFormat`, `revalidationStatus`.
- `manifestDigest` = sha256 of the canonical manifest JSON bytes.
- Observed `manifestDigest` = `a42bf17d0eaf8ef718f3514ba1d3756d9abf47239547c53c1b0089b511e99663`,
  `recordCount` = 6,806.

## 7. Observed population

| Field | Value |
|---|---|
| recordCount | 6,806 |
| historicalKind | `tcVerifiedProof` × 6,806 |
| solverInvocation | vault-manifest 6,668 · proof-universe-lock:v33 84 · batch-uap-loop 36 · cert-promotion 18 |
| claimFormat | entries[] 6,668 · graphSnapshot 84 · certificate/other 54 |
| revalidationStatus (initial) | `legacy-unverified` × 6,806 |

## 8. Current trust consumers (read the legacy journal today)

- `src/verification/certificate_verifier.nim:274` — R4 trust closure via `readCommit`.
- `src/cli/verify_cli.nim:55` — `ax verify` via `replayJournal`.
- `src/verification/proof_state_builder.nim:193` — `ax report/status` via `replayJournal`.

`replayJournal` (`src/core/trusted/trust_commit.nim:399`) is all-or-nothing: any corrupt commit fails the whole replay
closed.

These consumers may still consume legacy records until the reader-enforcement Debt WP (open issue, below).

## 9. What is NOT changed by this protocol

- `verification_scope.lock` content and semantics.
- Trust journal schema / record format.
- VKD definition.
- Certificate schema.
- `nim-stew` subject.
- The Act-1 protected invariants.
- `check-debt` is red at this commit for **pre-existing** reasons (HEAD baseline already carried `debt_registry_open` and
  `nimtry_violations` drift, and the WP3-b working-tree edits stale `architecture_debt.json` canonical syntax hashes).
  DEBT#445 correctly moves the `debt_registry_open` projection from 17 → 18. This protocol does **not** fabricate a
  green state by silently editing the budget ledger or regenerating architecture hashes.

## 10. Open issues (deferred)

1. **Operational reader exclusion** — make `legacy-unverified` records non-authoritative to the three consumers above.
   This is the next Debt WP, not WP3-c.
2. **Retention policy** — the historical population is *integrity-pinned* but its retention (permanent archive vs
   lifecycle endpoint) is unresolved.
3. **Budget-ledger reconciliation** — updating `data/debt_ledger.json` BUDGET#005 `current` (16 → 18) and reconciling
   `nimtry_violations` / `architecture_debt` drift, deferred; must not be done opportunistically.

## 11. References

- ADR-0017 Trust Claim Authority.
- DEBT#445 (data/debt_registry.json).
- `experiments/act2-wp3c-historical-trust-debt/` (tool, manifest, analysis, result).
- External standards: SLSA Threat F; in-toto §4.3.2; RFC 6962 §3/§7.3; SLSA distributing-provenance.
