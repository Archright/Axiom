# WP3-c Result — Historical Trust-Artifact Integrity Debt

> EXPERIMENT-ONLY / not canonical execution path / not production API.
> This work package classifies, inventories, and quarantines-by-designed the historical trust
> journal. It does NOT perform operational reader exclusion and does NOT batch re-verify any
> record. Those are deferred to a later Debt WP (see Next-Experiment).

## Question

The pre-WP3-b trust journal holds 6,806 `tcVerifiedProof` records whose creation-time evidence
binding is unqualified. Register this as trust debt, produce an immutable deterministic
inventory, and define a revalidation protocol — without mutating any historical record and
without touching the protected Act-1 invariants.

## Context

- EXPERIMENT_ID: `act2-wp3c-historical-trust-debt`
- AXIOM_REVISION: working tree at `Axiom@f7dd583ca (v1.0.0)` head + uncommitted WP3-b/WP3-c changes. **No commit made.**
- PROJECT_UNDER_TEST: `nim-stew@c75502c` (untouched this WP).
- Scope: `data/trusted/journal/` (6,806 JSON records), WP3-b writers (`src/core/trusted/trust_commit.nim`,
  `src/verification/proof_universe_commit.nim`), `src/verification/certificate_verifier.nim`,
  `src/cli/verify_cli.nim`, `src/verification/proof_state_builder.nim`, `src/cli/axiom_engine.nim`.
- Toolchain: Nim `2.2.10`; `legacy_trust_audit.nim` compiled outside the product build (bare `nim`
  inside `Axiom/` triggers the product config.nims gate, so the source was copied to `/tmp` and
  compiled there). EXPERIMENT-ONLY tool, not the canonical execution path.

## Scope

Included:
- Immutable deterministic inventory (`output/manifest*.json`) of all 6,806 historical records.
- DEBT#445 registration, ADR-0017 (Trust Claim Authority), `docs/spec/trust_revalidation_protocol.md`.
- Determinism check (RunA/RunB) and SHA-256 correctness cross-validation.
- Journal directory integrity re-hash (content + basename sorted).

Excluded (and why):
- No operational reader exclusion (deferred: requires reader-enforcement WP).
- No batch re-verification (deferred: external proof pipeline not yet complete).
- No mutation of `verification_scope.lock` / journal schema / VKD / certificate schema / baseline / CI.
- No `nim-stew` modification. No `git commit`.
- No budget-ledger or architecture-hash reconciliation (pre-existing drift; minimal intervention).

## Procedure

1. Captured pre-WP git status (WP3-b changes preserved; journal 6,806 records, untracked).
2. Wrote EXPERIMENT-ONLY generator `legacy_trust_audit.nim` (stdlib only; inline SHA-256 — the
   installed Nim `std/sha256` is absent and `std/sha1` only exposes SHA-1). Compiled in `/tmp`
   to avoid the product config.nims gate.
3. Ran generator twice over the same journal → `manifest_runA.json`, `manifest_runB.json`;
   confirmed byte-identical; emitted `manifest.json` (RunA copy) and `manifestDigest`.
4. Cross-validated SHA-256: 50/50 random `originalSha256` vs Python `hashlib.sha256`; digest
   independently recomputed over the body-before-digest byte range.
5. Registered DEBT#445 in `data/debt_registry.json` (manually, `entry open → close` style), then
   `./bin/debt_engine --codegen` (NOT `--prune`) → regenerated `src/generated/debt_constants.nim`
   and `docs/DEBT_REGISTRY.md`. `make check-debt` state documented honestly.
6. Wrote ADR-0017 and `docs/spec/trust_revalidation_protocol.md`, verifying every cited line against
   the current source.
7. Final verification: journal directory re-hash vs captured baseline; nim-stew `git status`;
   Axiom `git status` (uncommitted, no commit).

## Result

- recordCount = **6,806**; kind = `tcVerifiedProof` × 6,806.
- solverInvocation: vault-manifest **6,668** · proof-universe-lock:v33 **84** · batch-uap-loop **36** · cert-promotion **18**.
- claimFormat: entries[] **6,668** · graphSnapshot **84** · certificate/other **54**.
- revalidationStatus = `legacy-unverified` × 6,806 (provenance-unqualified — not adjudicated false, simply unverifiable from file alone).
- `manifestDigest` = `a42bf17d0eaf8ef718f3514ba1d3756d9abf47239547c53c1b0089b511e99663`.
- RunA / RunB byte-identical (determinism). 50/50 SHA-256 sample: 0 mismatches. Digest independently reproduced.

## Evidence

- Generator & inventory:
  - `experiments/act2-wp3c-historical-trust-debt/legacy_trust_audit.nim`
  - `experiments/act2-wp3c-historical-trust-debt/output/manifest_runA.json` (2390008 bytes)
  - `experiments/act2-wp3c-historical-trust-debt/output/manifest_runB.json` (RunA-identical)
  - `experiments/act2-wp3c-historical-trust-debt/output/manifest.json` (RunA copy)
- Registration:
  - `data/debt_registry.json` → DEBT#445 (`Trust / Evidence`, high, open)
  - `src/generated/debt_constants.nim` (DebtEntryCount=166, DebtOpenCount=18)
  - `docs/DEBT_REGISTRY.md` (regenerated)
  - `docs/adr/0017-trust-claim-authority.md`
  - `docs/spec/trust_revalidation_protocol.md`
- Analysis: `experiments/act2-wp3c-historical-trust-debt/wp3c-analysis.md`

### Journal integrity (R8)

Journal directory hash (content + basename, sorted) re-run at close:
`4a9a63f45f222510901bdc54f36af6aba4c9a4cfb76035eadaf7ccebba1bc7de` — **identical to baseline**.
No historical record created, modified, or deleted by this WP.

### Subject immutability (R8 subject)

`git -C nim-stew status --porcelain` shows `?? data/` — an **untracked residual** from a prior WP:
`data/trusted/journal/3ab50cc2...json` (kind `tcVerifiedProof`, solverInvocation `proof-universe-lock:v33`,
mtime < WP3-c session). This is historical contamination of the subject from an earlier ExternalSubject
journal-routing defect (the class that WP3-b's `commitVerification(run, result)` + `ArtifactResolver(stateRoot)`
fix addresses). This WP did **not** touch nim-stew: no files created, modified, or deleted here. Per
WP1 §8, the run that wrote this residual is excluded from M1 candidacy; the subject's integrity within
this WP is preserved.

## Classification

- **DEBT (`Trust / Evidence`, Historical Trust-Artifact Integrity)** — 6,806 provenance-unqualified
  `tcVerifiedProof` records. Registered, not adjudicated.
- **Unsupported / Incomplete** for re-verification at this stage: Track-1 reconstruction is low
  certainty; Track-2 (current re-verification) is possible but deferred.
- **InfrastructureFinding** (architectural, via ADR-0017): a trust artifact must not assert a
  stronger claim than the strongest evidence actually produced by the current run.

## R1–R9 Acceptance Table

| # | Predicate | Result | Evidence |
|---|---|---|---|
| R1 | Historical population measured | **PASS** — 6,806 | manifest, recordCount |
| R2 | Untrusted status recorded | **PASS** — `legacy-unverified` × 6,806 | manifest |
| R3 | No historical record mutated | **PASS** — journal hash invariant | baseline `4a9a63f4…bcde` re-derived identical |
| R4 | No fabrication of green | **PASS** — `check-debt` red, honestly documented (pre-existing drift + DEBT#445 open 17→18) | analysis §check-debt |
| R5 | Inventory deterministic | **PASS** — RunA ≡ RunB byte-identical | manifest_runA/B |
| R6 | manifestDigest pinned | **PASS** — in DEBT#445 + ADR-0017 | `data/debt_registry.json`, ADR |
| R7 | No mutation of lock/journal-schema/VKD/cert/subject | **PASS** — none touched | git status, journal hash |
| R8 | Journal files unchanged | **PASS** — hash matches baseline | re-hash output |
| R9 | Deferred framing (not "quarantine complete") | **PASS** — operational reader exclusion deferred | this doc §Non-Conclusions |

## Interpretation

What the evidence establishes:
- The 6,806 records are **provenance-unqualified**, not proven false; several carry
  `solverInvocation` families that do not themselves establish kernel proof.
- The future creation path is closed (WP3-b gate); only the historical residual remains.
- The population is now deterministically inventoried with a pinned digest, so its integrity is
  auditable without touching the records.

What it does NOT establish:
- It does not prove any individual record is correct or incorrect.
- It does not quarantine operationally: `ax report/status/verify` may still consume these legacy
  records until the reader-enforcement WP is completed (R9).

## Non-Conclusions

- "6,806 records were false" — NOT claimed; they are adjudged *unverified-by-file*.
- "Quarantine is complete" — NOT claimed; only classification + inventory + protocol design.
- "Retention is resolved" — NOT claimed; picture pinned, retention policy unresolved → Open Issues.
- "Track-1 will recover ~100%" — NOT claimed; two-track protocol, Track-1 low certainty.

## Next-Experiment (deferred Debt WP)

1. **Reader-enforcement WP** — make journal consumers (`readCommit`, `replayJournal`) treat
   `legacy-unverified` records as non-trusted except where revalidated, achieving operational
   quarantine. Smallest useful next experiment.
2. **Track-2 current re-verification** of a small revalidatable subset to validate the promotion path.
3. Later: budget-ledger / architecture-hash drift reconciliation (separate from evidence integrity).

---

## Registration summary (fixed values)

- manifestDigest = `a42bf17d0eaf8ef718f3514ba1d3756d9abf47239547c53c1b0089b511e99663`
- recordCount = 6,806
- journal baseline hash = `4a9a63f45f222510901bdc54f36af6aba4c9a4cfb76035eadaf7ccebba1bc7de`
- DEBT#445 = `Trust / Evidence`, severity high, status open
- ADR-0017 = Trust Claim Authority invariant
- check-debt = red at HEAD baseline (pre-existing drift); DEBT#445 adds one honest open delta; no fabrication.
