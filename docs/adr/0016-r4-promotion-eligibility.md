# ADR-0016: R4 Promotion Eligibility — Proof-less Verification Results ARE Promotable (Q1=YES) under an Explicit ProofStatus Model (Q2)

## Status

**Proposed (ratified decision points).** This ADR decides the R4 semantics — *is a verification result without a real proof object promotable to the canonical vault/certificate?* — with exactly two pre-decided answers (Q1 = YES, subject to the Q2 guard). No implementation is authorized by this ADR alone: Policy v2, the ProofStatus tagging implementation, and the C0 B4 artifact-commit decision are separate follow-on ratified revisions (see Consequences).

## Context

An independent readiness evaluation of Axiom (HEAD `2e31b2587`, Nim 2.2.10 / Lean 4.29.0 / Z3 4.13.3) runs R4 as a CRITICAL invariant and FAILs it:

- `data/readiness/evaluate.py` — `r4()`, lines 68-87 — the independent evaluator's R4 rule hard-fails when the observed certificate proof digest is null:
  - line 71: `proof = getval(o, "certProofDigest")`
  - lines 81-82: `if any(pv is None for pv in proof): fail.append("proofDigest absent/null on cert (proof-artifact pipeline unimplemented)")`
- The evidence manifest observes the null digest directly: `data/readiness/evidence_manifest.json:340-341` (obsId `C4-01j` — `"key": "certProofDigest", "value": null`, scope `artifact`).
- The resulting decision artifact is **NO-GO** with **R4 in `blockingInvariants`**: `data/readiness/decision.independent.20260819T122137Z.json:44-49,92-98` (R4 FAIL: "proofDigest absent/null on cert (proof-artifact pipeline unimplemented)"; blockingInvariants = [R4, R7, R8]; finalVerdict = NO-GO).

The FAIL is a *mechanical* observation, but the underlying question is **semantic**: the v1 product contract declares `proofDigest` **optional** (the proof-artifact pipeline is unimplemented), so a verification result whose certificate carries no real proof object is — by contract — a *complete* v1 artifact. This ADR ratifies that semantic question (Q1) and the state model for certificate-level proof status (Q2).

---

## 1. Decision — Q1: Is a proof-less verification result promotable to the canonical vault?

### Answer: **Q1 = YES** (ratified)

A verification result whose certificate carries no real proof object **MAY be promoted** to the canonical vault/certificate, **because the v1 product contract declares `proofDigest` optional**, subject to the Q2 guard: proof-less promotion must NOT weaken `certGreen`/proof-backed semantics.

### Evidence FOR YES

1. **v1 product contract, §R4 — `proofDigest` is optional by contract.** `docs/spec/productization_contract.md:80`:

   > requiredFields는 policy(`r4.requiredFields`)에서: `claim, attestation, inputHash, provenance, toolchainIdentity, solverInvocation, solverInputDigest, solverResultDigest`. `proofDigest`는 현재 증명 artifact 파이프라인이 미구현되어 null 유지 — optional.

   The 8 required fields are `claim, attestation, inputHash, provenance, toolchainIdentity, solverInvocation, solverInputDigest, solverResultDigest` — **`proofDigest` is NOT among them**.

2. **Contract §1 — the promise is a reproducible verification result, not proof-bearing.** Core promise: "동일한 **canonical input** + 동일한 **execution contract**(toolchain·solver·config·cache policy)에 대해 **재현 가능한(canonical semantic 동일) verification result**를 제공한다" — a *result*; no proof requirement. §1 non-goals (`docs/spec/productization_contract.md:21`): "certificate는 출력 artifact로 존재하되 promise는 **'local replay-bound verification artifact'**로 제한됨"; "provenance-bearing 같은 표현은 v1에서 local replay-bound 로 재명한다".

3. **Policy SSOT — same 8 fields, no proofDigest.** `config/readiness_policy.json:201-211` (`r4.requiredFields`): exactly the 8 contract fields listed above. `proofDigest` is absent from the required set.

4. **Provenance v3 contract — a canonical v3 cert with null proofDigest is valid by contract.** `docs/spec/provenance_contract_v3.md:21` shows the v3 schema with `"proofDigest": null`; `:41` — `proofDigest` is optional ("O"), meaning "증명 artifact 파이프라인이 존재하지 않음 — null 유지", schema check "Y (null 포함)"; `:68` — "`proofDigest = null` — solver result는 proof가 아니다. 증명 artifact 파이프라인은 현재 존재하지 않는다". Note `:47` — "필수 필드는 null/빈 값이 될 수 없다" — that rule applies to **required** fields only; proofDigest is optional, so null stays conformant.

5. **ADR-0015 F2 — never fabricate, never exclude.** `docs/adr/0015-phase0-decision-gate-evidence-boundary.md:39-62` — F2: "No genuine proof object exists today"; using `proofDigest` for a digest of `solverStatus+result` would be a misnomer; the name is only legitimate once a real proof object is wired into the certificate pipeline. F2's rule is **never fabricate `proofDigest`**, and F2 **never excludes proof-less certs from the vault** — it mandates honest digests with the name *reserved* for a future real proof object. F3 (`:64-81`) designs a single aggregate promotion gate in which `verifyProofArtifact` is a structural F2-domain placeholder, not a required conjunct for v1 promotion.

6. **Repo (Nim) evaluator — ruleR4 passes without proofDigest.** `tools/readiness_evaluator.nim:484-507` — `ruleR4` reads `policy["r4"]["requiredFields"]` (`:488-494`) and requires exactly those fields; with the current policy (8 fields, no proofDigest) a cert with null proofDigest does **not** fail ruleR4. (`:495-497` — a hard-coded fallback default field list is used only when the policy `r4` block is missing; superseded by the policy.) The repo evaluator therefore agrees: proof-less is not an R4 integrity violation under the ratified policy.

7. **Runtime promotion gate — `verifyProofArtifact` is NOT a required verifier.** `src/verification/cert_promotion.nim:228-231` — "No promotion may bypass this eligibility check". `:246-261` — `promoRequiredVerifiers` by status: `certGreen` -> `[verifySemanticEvidence, verifyAcceptance, verifyIdentityBinding, verifyCertificateCompleteness]`; `certZ3Verified / certLeanVerified / certNoObligation` and default -> `[verifySemanticEvidence, verifyIdentityBinding, verifyCertificateCompleteness]` — `verifyProofArtifact` is in **neither** set, and the aggregate executes exactly the required set. Supporting: `src/verification/certificate_eligibility.nim:49-61` — `verifyProofArtifact` returns `passed=false` with "NOT_APPLICABLE: no real proof artifact in v1 (F2); proofDigest not fabricated" — a structural placeholder that never gates promotion (design corroboration: `docs/design/r4_promotion_eligibility_aggregate.md:40,70` — proofDigest optional/absent "is not a completeness failure in v1").

### Evidence FOR NO (recorded honestly, for the record)

- `data/readiness/independent_policy.json:33` — independent R4 `observationKeys` **include** `certProofDigest`, so the independent harness observes this key (and the raw observation is the null seen in the manifest).
- `data/readiness/evaluate.py:81-82` — the independent engine hard-FAILs null directly (mechanical, no semantic read).
- `docs/audit/productization_readiness_2026-08-17.md:35,117` — the 2026-08-17 audit's **6-field list included proofDigest**: `:35` — R4 FAIL: "certificate에 claim/attestation/inputHash/provenance/toolchainIdentity/proofDigest 필드 없음"; `:117` — "R4 evidence: certificate-persisted scope 6개 필드 전부 `certFieldPresent=false`…". This 6-field audit list is **superseded** by the contract's 8-field list (`docs/spec/productization_contract.md:80`): the supersession drops `proofDigest` from "required" and adds `solverInvocation` / `solverInputDigest` / `solverResultDigest` — the projection is 6 → 8, with `proofDigest` moved to optional.

**Reconciliation.** The NO-leaning evidence is policy-of-record history under a pre-contract field set, not a contract-level requirement; the ratified contract (§R4) is the newer authoritative list. Q1 = YES stands.

---

## 2. Decision — Q2: ProofStatus of a promoted proof-less certificate

### 2.1 Guard (ratified, non-negotiable)

**Proof-less promotion must NOT weaken `certGreen`/proof-backed semantics.** Promotion of a proof-less certificate may lift the artifact into the vault, but must never lift its claim tier.

### 2.2 Ratified ProofStatus semantic-state model (certificate-level)

| ProofStatus | Meaning |
|---|---|
| `REQUIRED_AND_PRESENT` | The certificate type REQUIRES a proof object **and** a real proof artifact is bound (non-null, verifiable digest). |
| `REQUIRED_BUT_ABSENT` | The certificate type REQUIRES a proof object **but** none is bound (null/missing). |
| `NOT_REQUIRED_BY_CERTIFICATE_TYPE` | The certificate type does NOT require a proof object (v1 §R4 — 8-field set without `proofDigest`). |
| `NOT_EVALUATED` | Proof presence was NOT evaluated for this certificate. |

### 2.3 Tagging rule — an explicit ProofStatus tag, NOT a blanket NOT_APPLICABLE

`proofDigest = null` **must** be tagged with an explicit `ProofStatus` — **NOT** a blanket `NOT_APPLICABLE` — so "no proof pipeline" (`NOT_REQUIRED_BY_CERTIFICATE_TYPE`) is **never conflated** with "intentionally evidence-only" (a deliberate, lower-tier claim choice):

- "No proof pipeline" = the certificate *type* (v1) has no proof-object requirement; absence is a contract-level state.
- "Intentionally evidence-only" = a conscious claim decision that a promoted certificate carries only an evidence-only, lower-tier claim.

A blanket NOT_APPLICABLE label collapses both into one ambiguity; this model keeps them distinguishable, so every promoted artifact carries an explicit, honest proof-status semantic.

> Layering note: the *verifier-level* `NOT_APPLICABLE` result inside the promotion aggregate (`src/verification/certificate_eligibility.nim:54-57`, per `docs/design/r4_promotion_eligibility_aggregate.md:40`) stays structurally unchanged — it is the mechanical F2 placeholder. The *certificate-level* `ProofStatus` tag is the semantic state. The two layers coexist; neither overrides the other.

### 2.4 Promotion-allowed mapping + CertificateClaim (per C0 B1)

The Phase-C boundaries freeze (C0, item **B1 — CertificateClaim taxonomy**) governs what each promoted state may claim. Anti-theater law (AGENTS.md §0.9) and claim/evidence honesty require that a promoted certificate never impersonate a stronger claim than its evidence supports:

| ProofStatus | Promotion? | CertificateClaim (C0 B1) it may carry |
|---|---|---|
| `REQUIRED_AND_PRESENT` | **Allowed** | Proof-backed claim — the **only** state that may carry a `certGreen`-class (proof-backed) claim, and only when all certGreen conjuncts pass (dual acceptance, deep verify, no vacuity, identity binding). |
| `NOT_REQUIRED_BY_CERTIFICATE_TYPE` | **Allowed** (v1 default) | Evidence-only claim — **never `certGreen`/proof-backed** (no certGreen impersonation). Honest lower-tier status such as the `certZ3Verified`-style tier (`statusConsistentWithEvidence` lower-bound; `src/verification/proof_state_projection.nim:226-228` downgrades overstated statuses). |
| `REQUIRED_BUT_ABSENT` | **Refused** (fail-closed) | No claim issued — promotion gate blocks. |
| `NOT_EVALUATED` | **Refused** (fail-closed) | No claim issued — nothing unevaluated is promoted (theater guard). |

Under this model the current v1 runtime sits exactly on the ratified branch: v1 certificates are `NOT_REQUIRED_BY_CERTIFICATE_TYPE` (contract §1), promotion is allowed, and their claims are evidence-only lower tiers — **never** named certGreen. If a future certificate type makes proof required, absence becomes `REQUIRED_BUT_ABSENT` and promotion is refused — that is the Q2 guarantee: proof-less promotion never weakens proof-backed semantics.

### 2.5 Both branches keep NO-GO unchanged

Resolving R4 does **NOT** change the current NO-GO. **R7** (CLI product contract: internal-error exit contract open — no top-level signal handler, SIGSEGV out-of-contract, target exit 2 unimplemented) and **R8** (productization blocking surface: 0 v3 certs in the canonical vault — persist step not closed; VKD 0/23, obligation pipelines emit IR FAIL — F4=B research blocker) **remain blocking** in the same independent policy (`data/readiness/decision.independent.20260819T122137Z.json:62-76,92-98`). Even with Q1=YES plus a ratified Policy v2, the final verdict stays NO-GO until R7/R8 close. The independent evaluator remains the sole GO/NO-GO arbiter (ADR-0015, locked decision 3).

---

## 3. Consequences — next step: Policy v2 is a FOLLOW-ON, not part of this ratifying step

Because Q1=YES, the **independent policy** will later need a **ratified Policy v2 revision** — a SEPARATE ratified revision, never a silent evaluator edit:

1. Add one item to `preRatifiedNotApplicable` in `data/readiness/independent_policy.json`: *"`certProofDigest` absence (null) while the proof-artifact pipeline is unimplemented = honest NOT-scored per contract §R4 optional; proof-less v1 certificates are not scored on proof presence"*.
2. Re-score `evaluate.py:81-82` so null `certProofDigest` is **not** an R4 FAIL.
3. **KEEP the theater guard (non-negotiable):**
   - `noEmptyFieldPromotion` stays — promotion still validates v3 field completeness + acceptance (no acceptance-free promotion);
   - the honest `NOT_APPLICABLE` reason text stays (never a manufactured PASS);
   - `proofDigest` is **never fabricated** (ADR-0015 F2 stays law).
4. Policy v2 is ratified as its own decision (separate ADR/step), and the independent evaluator then **re-runs unchanged** against it — per ADR-0015 locked decision 3: the evaluator is the sole arbiter and must rerun unchanged; any evaluator change IS a policy change that itself requires ratification.

This ADR authorizes *only* the semantic answers (Q1, Q2); the Policy v2 manifest revision, the ProofStatus tagging implementation, and any evaluator edit are outside its authority.

Additionally, the **artifact-commit decision** (normative artifact set per C0 B4) **must accompany** this ratification: the entire Phase-0 apparatus is currently **untracked** — `data/readiness/independent_policy.json`, `data/readiness/evidence_manifest.json`, the `data/readiness/decision.independent.2026*.json` files, `readiness_history.json`, `snapshots/`, the design docs (`docs/design/r4_promotion_eligibility_aggregate.md`, and others), `docs/adr/0015`, and `src/verification/certificate_eligibility.nim` all show as untracked in `git status` — so a normative-artifact commitment decision (per B4) must be made before this apparatus can serve as the ratifiable basis of future GO/NO-GO claims.

---

## 4. Decision (final)

| ID | Ratified answer | Branch |
|---|---|---|
| **Q1** | **YES** — a verification result whose certificate carries no real proof object MAY be promoted to the canonical vault/certificate; v1 contract declares `proofDigest` optional | Promotion allowed for `NOT_REQUIRED_BY_CERTIFICATE_TYPE` (v1 default); Policy v2 follow-on |
| **Q2** | **ProofStatus model ratified**: `REQUIRED_AND_PRESENT` -> allowed (proof-backed claim only); `NOT_REQUIRED_BY_CERTIFICATE_TYPE` -> allowed (evidence-only claim, never certGreen impersonation); `REQUIRED_BUT_ABSENT` -> refused; `NOT_EVALUATED` -> refused; `proofDigest = null` must carry an explicit tag — never blanket NOT_APPLICABLE | Q2 guard: proof-less promotion cannot weaken certGreen/proof-backed semantics |
| **Gate** | R7/R8 remain FAIL/blocking (independent) — final verdict stays **NO-GO** | Re-evaluation only after R7/R8 closure + ratified Policy v2 |

## Evidence map

- Observation ground truth: `data/readiness/evaluate.py:68-87` (`:71`, `:81-82`); `data/readiness/evidence_manifest.json:340-341`; `data/readiness/decision.independent.20260819T122137Z.json:44-49,62-76,92-98`
- Contract/policy: `docs/spec/productization_contract.md:19,21,80`; `config/readiness_policy.json:201-211`; `docs/spec/provenance_contract_v3.md:21,41,47,68`
- Prior ADR + design: `docs/adr/0015-phase0-decision-gate-evidence-boundary.md:39-62`; `docs/design/r4_promotion_eligibility_aggregate.md:16,40,70`
- Evaluator + runtime: `tools/readiness_evaluator.nim:484-507`; `src/verification/cert_promotion.nim:228-231,246-261`; `src/verification/certificate_eligibility.nim:49-61`; `src/verification/proof_state_projection.nim:226-228`
- NO-leaning policy history: `data/readiness/independent_policy.json:33`; `docs/audit/productization_readiness_2026-08-17.md:35,117`