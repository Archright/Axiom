# Axiom v1 Productization Entry Contract — Launch Requirement Layer (Normative Spec)

> **Status**: PROPOSED — NORMATIVE SPEC (submitted 2026-08-20 for ratification). This document defines the **launch requirement layer** for Axiom v1: the product capabilities a v1 launch depends on, the evidence each requires, and the pure function that derives the **binary GO/NO-GO launch verdict** from readiness evidence. It is deliberately **not** the closure lifecycle and **not** an evaluator (§1, §7). Documentation only — no product code, no test, no readiness-artifact change is made by this file.
> **SSOT anchors**: per-invariant evidence results — `data/readiness/decision.independent.<UTC>.json` (latest: `data/readiness/decision.independent.20260819T122137Z.json` — `finalVerdict` = NO-GO, `blockingInvariants` = [R4, R7, R8], R1/R2/R3/R5/R6 = PASS, R4/R7/R8 = FAIL, lines 24-98); policy — `data/readiness/independent_policy.json`; evidence — `data/readiness/evidence_manifest.json`; closure lifecycle — `docs/design/readiness_closure_protocol.md` + ledger `data/readiness/closure_state.json`; v1 product profile & exit contract — `docs/spec/productization_contract.md` §1, §R4, §6b, §7 and the v1 CLI Exit-State Contract (:246-285); frozen certificate model — `docs/design/phasec_boundaries.md:55-96`.
> **Related**: `docs/adr/0016-r4-promotion-eligibility.md`, `docs/adr/0015-phase0-decision-gate-evidence-boundary.md`, `docs/design/phasec_r7_termination_architecture.md`, `docs/design/r7_exit_authority_gap.md`, `docs/design/r8_research_charter.md`.
> **Authority**: this file is the ONLY place the v1 launch requirement set is defined. Changing a launch requirement = ratifying a revision of THIS file (§2, §7). It never lands through evaluator or policy edits.

---

## 1. Purpose and Domain

### 1.1 Three questions, three layers

| Layer | Answers | Authority |
|---|---|---|
| Readiness evaluation | *How do R1–R8 measure against the contract right now, per invariant?* (PASS/FAIL/UNKNOWN per R, point-in-time) | `data/readiness/evaluate.py` — sole per-invariant arbiter (ADR-0015 locked decision 3) |
| Closure protocol | *For each blocking invariant, where is its lifecycle and what closes it?* (10-state machine, per-blocker) | `docs/design/readiness_closure_protocol.md` + `data/readiness/closure_state.json` |
| **Entry Contract (this file)** | *What must a v1 launch require, and is it satisfied?* (capability-indexed, derived verdict) | this file — requirement layer only |

The readiness evaluation produces point-in-time verdicts; the closure protocol tracks blocker lifecycles and is deliberately NOT a verdict/projection engine (INVARIANT-RCP-6). Neither defines what a v1 **launch** must require. This contract fills exactly that gap: launch requirements are indexed by **product capability**, and R1–R8 form the **evidence/measurement layer** — each R is EVIDENCE FOR a capability, never the requirement itself.

### 1.2 The master invariant — Closure requirement ≠ Launch requirement

```
INVARIANT-EC-1 (closure ≠ launch): a closed blocker is a lifecycle fact; a
   satisfied launch requirement is an evidence fact. Neither implies the other:
   - all requiredEvidence R of a capability may be PASS while the corresponding
     closure records are still open (forward or BLOCKED_* stages) — the launch
     requirement is satisfied; the lifecycle is simply behind;
   - closure records can NEVER satisfy a launch requirement — no OPEN/CLOSED
     record, no ratification chain, is evidence. Evidence is the PRIMARY
     satisfier (§3).
```

### 1.3 No parallel names — frozen semantics reused verbatim

This layer reuses the frozen vocabulary of `docs/design/phasec_boundaries.md:55-96` — PromotionState (`PROMOTED`/`PROMOTABLE`/`INELIGIBLE`), ProofStatus (`REQUIRED_AND_PRESENT`/`REQUIRED_BUT_ABSENT`/`NOT_REQUIRED_BY_CERTIFICATE_TYPE`/`NOT_EVALUATED`), CertificateClaim (`Evidence-only`/`Proof-backed`), INVARIANT-B1-1/2/3 — and ADR-0016 (Q1 = YES: proof-less verification results ARE a complete v1 artifact because `proofDigest` is optional by contract; Q2 = certificate-level ProofStatus model; `docs/adr/0016-r4-promotion-eligibility.md:21-25,87-94`). v1 certificates ride the ratified branch: `NOT_REQUIRED_BY_CERTIFICATE_TYPE`, promotion allowed, claims evidence-only (:94). This contract adds no parallel name for any frozen state.

---

## 2. Capability-Indexed Launch Requirements (v1)

Each launch requirement is one row: `{ capability, product promise, requiredEvidence (R-set), predicate (§4), closure (§3), status }`.

| Capability | v1 product promise captured | requiredEvidence (R-set) — evidence FOR this capability | status |
|---|---|---|---|
| `CANONICAL_EXECUTION` | The documented v1 surface (`ax prove`, `ax report --json`) really exists, really executes verification, and results are rule-derived: `verified` is produced only by fixed rules, vacuous proofs never counted, Z3-only paths distinguishable from dual-assurance paths | R1 (documented promises exist on the real CLI surface — `commandExists`/`promiseOutputExists`), R2 (result semantics rule-derived; Z3-only/dual distinguishable; vacuous excluded), R3 (canonical result projection deterministic) | REQUIRED |
| `REPRODUCIBLE_RESULT` | Same canonical input + same execution contract (toolchain·solver·config·cache policy) → identical canonical result (canonical projection hash equal), and the per-command product contract is stable: exit codes, JSON schema `axiom.report.v1`, stdout/stderr split | R5 (deterministic salted cache + pinned seeds → byte-identical A/B; per-command exit-code/JSON-schema surface — `productization_contract.md:82-90,232-244`) | REQUIRED |
| `EVIDENCE_BACKED_CERTIFICATE` | Every verdict is evidence-bounded; certificates exist as per-function, local replay-bound artifacts; proof-less is honest and storable under the frozen ProofStatus model (`NOT_REQUIRED_BY_CERTIFICATE_TYPE`, Evidence-only claim); proof-backed claims require `REQUIRED_AND_PRESENT` (INVARIANT-B1-3); the golden slice's persist step (execute→verify→canonicalize→attest→persist→reproduce) is closed | R4 (cert fields present; proof-less honest; chain reconstructible — `productization_contract.md:73-80`) + **R8-P** (persist/artifact leg, §6.2) | REQUIRED |
| `PROVENANCE` | Every artifact reconstructs the claim→evidence→toolchain→solver→input chain from the local repo (local replay-bound); identity terms are content hashes only, never provenance values (INVARIANT-B2-1/2/3); failure never converts to success; the documented promise matches the actual surface | R4 (`provenanceReconstructible`) + R1 (the documented promise is a real, matching surface) + R6 (no failure→success conversion, no swallowed exception, observation hygiene) | REQUIRED |
| `CLI_CONTRACT` | A deterministic process-exit contract: 4-state model `0/1/2/3` + out-of-contract signal rule, per command; `SIGSEGV(139)` is OUT_OF_CONTRACT — never shimmed to 2 (`productization_contract.md:259,261,280`); deterministic exit via the `quit(errorcode)` primitive (POSIX signal death = 128+signum is not a contract state); termination classification is a documented external product contract (Part B D1/D2, Part C L1–L3, `docs/design/phasec_r7_termination_architecture.md`; §7.3 of `docs/design/r7_exit_authority_gap.md`) | R7 (CLI Product Contract; independent policy, CRITICAL) | REQUIRED |
| `PERSISTABLE_CERTIFICATE` | The canonical vault holds ≥1 **promoted** v3 certificate that survives re-runs and stays callable — a customer-facing persistence artifact | R8-P (persist step, §6.2) | **OPEN** — ratification pending: whether ≥1 promoted canonical certificate is a v1 launch requirement is an open contract decision (§6.2); NOT a documented customer promise today |
| `RUNTIME_BOUNDARY` | Product execution MUST NOT mutate tracked repository state **except** for the canonical product artifacts explicitly destined here as sanctioned execution outputs (`src/verification/certificates/<irHash>.json` + `src/verification/certificates/manifest.json`). Every sanctioned tracked mutation is deterministic, identity-bound, atomic, idempotent, and independent of unrelated source/config/input state. R6 = **NoUncontrolledTrackedMutation** (a §7-ratified refinement of the former unqualified `noTrackedMutation` — see §6.3): `TrackedDelta(execution) ⊆ SanctionedProductWrites` and `TrackedDelta ∩ Source/Config/Input = ∅` | R6 (see §6.3 for the exact predicate) | REQUIRED |

Notes:

- Evidence sets may overlap across capabilities (R4 serves `EVIDENCE_BACKED_CERTIFICATE` AND `PROVENANCE`; R1 serves `CANONICAL_EXECUTION` and `PROVENANCE`). Evidence is a shared, re-usable input — never a duplicated measurement — and each requirement is evaluated independently (§5).
- `PERSISTABLE_CERTIFICATE` is the ONLY row whose membership in the launch requirement set is unresolved. OPEN means it participates in NO launch predicate until ratified (§6.2).
- `RUNTIME_BOUNDARY` is REQUIRED and evaluates R6 under the **NoUncontrolledTrackedMutation** refinement (§6.3), including the declared `SanctionedProductWrites` set. It does NOT require an unqualified clean tree — it requires that every tracked delta from a run be confined to the sanctioned canonical cert artifacts (deterministic, identity-bound, atomic, idempotent, no unrelated mutation).
- **R8-R is explicitly NOT in the v1 requirement set** (§6.1). If a future v2 imposes a real-proof obligation, it promotes a new capability row here — e.g. `PROOF_OBLIGATION_COVERAGE ← R8-R` — by revising §2 of THIS contract only, never the evaluator or the policy criticality.

---

## 3. Evidence-Primary / Closure-Secondary (INVARIANT-EC-2)

```
INVARIANT-EC-2 (evidence-primary / closure-secondary): a capability is satisfied
   PRIMARILY by its requiredEvidence per-R states being PASS, or pre-ratified
   NOT_APPLICABLE in the evaluator's own vocabulary — never minted by the closure
   layer. Closure state is an OPTIONAL, secondary constraint only:
   - evidence FAIL/UNKNOWN ⇒ capability UNSATISFIED, no matter what the closure
     records say;
   - the closure constraint (when a requirement's `closure` column is set to
     CLOSURE_RECORDS_CLOSED, §4) can only ADD an extra condition on top of
     evidence: every requiredEvidence R must then also have its closure record in
     terminal CLOSED state; a missing record is a violation;
   - default `closure` = CLOSURE_NONE — closure records are not consulted.
```

Because the closure protocol reaches CLOSED only via a NEW decision artifact where the invariant ∈ {PASS, pre-ratified NOT_APPLICABLE} (readiness_closure_protocol.md §2.3 S7), evidence-primary and closure-secondary cannot contradict in a healthy run; if they ever diverge, evidence wins. An absent/invalid decision artifact ⇒ no launch derivation (fail-closed, same law as evidence UNKNOWN).

---

## 4. Fixed Predicate Vocabulary (INVARIANT-EC-3)

```
INVARIANT-EC-3 (closed predicate vocabulary): every launch requirement's
   predicate is drawn from a FIXED, machine-evaluable enum below — never
   arbitrary expressions, never natural-language clauses, never ad hoc
   formulas. Predicates evaluate the LATEST decision artifact only.
```

| Predicate | Satisfied iff (over `decision.latest`) |
|---|---|
| `EVIDENCE_ALL_SATISFIED` | every R in requiredEvidence has `result ∈ {PASS, pre-ratified NOT_APPLICABLE}` in `invariantResults`; any FAIL/UNKNOWN/missing → unsatisfied (fail-closed) |
| `EVIDENCE_ANY_SATISFIED` | ≥1 R in requiredEvidence has `result ∈ {PASS, pre-ratified NOT_APPLICABLE}` — for alternative-evidence capabilities only |
| `NO_BLOCKER_IN_REQUIRED_SET` | (requiredEvidence ∩ `blockingInvariants`) = ∅ — computed from the same single artifact |

Closure-side enum (secondary, §3; column `closure`): `CLOSURE_NONE` (default) | `CLOSURE_RECORDS_CLOSED` (every required R has a terminal CLOSED record; missing record = violation).

Free-form expressions, conditional satisfiability, "unless…" carve-outs: none are representable. Extending the vocabulary (a new predicate or closure value) is a ratified revision of THIS contract, with the same discipline as a requirement change (§7).

---

## 5. Binary GO/NO-GO (INVARIANT-EC-4)

```
INVARIANT-EC-4 (binary launch verdict): the v1 launch verdict is exactly:
   GO    ⟺ every requirement with status REQUIRED (§2) is satisfied by its
           predicate on the latest decision artifact;
   NO-GO ⟺ otherwise (any REQUIRED requirement unsatisfied, OR any required
           evidence in FAIL/UNKNOWN, OR evidence absent).
   CONDITIONAL is explicitly out of scope — there is no third value, no
   conditional launch, and no generated conditions list.
```

- The derivation is a **pure, deterministic projection**: input = most recent `data/readiness/decision.independent.<UTC>.json` (lexicographic order is the tie-break), rules = §2/§3/§4, output = one of two values. No human judgment, no free-form input.
- The launch verdict may deliberately differ from the readiness `finalVerdict`: the readiness verdict judges the full R1–R8 contract under the independent policy; the launch verdict judges only the v1 capability set. That difference is where R8-R is derived away (§6.1). Each per-invariant result remains the sole authority over its own R (ADR-0015 locked decision 3); this contract only re-maps results to capabilities.
- Worked example at the latest decision (`data/readiness/decision.independent.20260819T122137Z.json`):

| Requirement | Evidence state at latest decision | Verdict contribution |
|---|---|---|
| `CANONICAL_EXECUTION` | R1/R2/R3 = PASS | satisfied |
| `REPRODUCIBLE_RESULT` | R5 = PASS | satisfied |
| `EVIDENCE_BACKED_CERTIFICATE` | R4 = FAIL (R8-P not satisfied) | unsatisfied |
| `PROVENANCE` | R4 = FAIL | unsatisfied |
| `CLI_CONTRACT` | R7 = FAIL | unsatisfied |
| `PERSISTABLE_CERTIFICATE` | OPEN — participates in no predicate | — |

→ **NO-GO**, consistent with the readiness verdict; the launch-blocking capabilities are `EVIDENCE_BACKED_CERTIFICATE` (R4), `PROVENANCE` (R4), `CLI_CONTRACT` (R7). R8-R does not participate.

---

## 6. The R8-R / R8-P Decomposition

### 6.1 R8-R — RESEARCH component: derived away from v1 launch

The latest decision FAILs R8 on three observed legs (`data/readiness/decision.independent.20260819T122137Z.json:69-76,86-90`): persist-step not closed (0 v3 certs in canonical vault), golden slice not fully closed, and the verification-coverage gap ("VKD 0/23, obligation pipelines emit IR FAIL — ObliSemanticNoApplicable"). The third — obligation/CHC/real-proof research (DEBT#416, `data/debt_registry.json:2438`, UNRESOLVED; VKD = 0/23 as measured truth, `productization_contract.md:224-228`) — is **derived away from the v1 launch requirement set by this contract**: ADR-0015 F4 = B means no admissible real-proof target exists, and the v1 product promise is evidence-only; therefore the research leg cannot be a launch dependence. It remains a blocker of the WHOLE-readiness verdict (unchanged, independent policy) and a `BLOCKED_BY_RESEARCH` closure track (readiness_closure_protocol.md B2; `docs/design/r8_research_charter.md` §2.1-2.2 — isolated workstream, adoption gate). It does NOT block the v1 launch verdict. Any future v2 promotion revises §2 of THIS file only.

### 6.2 R8-P — PERSIST component: a separate launch question, OPEN

The persist/artifact leg — canonical-vault persistence, the golden-slice last step (canonicalize→attest→persist→reproduce) — is a **launch-gate criterion** (it sits in `EVIDENCE_BACKED_CERTIFICATE`'s evidence set, §2) but is **NOT a documented customer promise** today. Whether "≥1 **promoted** canonical v3 certificate" is a v1 launch requirement is an open contract decision, machine-addressed as the `PERSISTABLE_CERTIFICATE` row: ratification of either answer takes effect by revising this contract's row — never through an evaluator or policy edit (the ADR-0016 consequences — Policy v2, `evaluate.py:81-82` re-scope — concern R4's proof-digest rule and are unrelated to this question).

### 6.3 R6 — Controlled Tracked State Transition (RATIFIED refinement)

**Background.** R6 was first collected as the unqualified `noTrackedMutation` (no tracked mutation at all during product execution). That predicate is **too coarse** for a product that is *required* to persist canonical artifacts into a tracked vault: v1 mandate (R8-P) deliberately writes the canonical certificate vault `src/verification/certificates/<irHash>.json` and its `manifest.json` — both intentionally tracked data per `.gitignore:44,108-111` ("Git tracked data files: .json (domain_layout, certificates)"). Demanding zero tracked delta therefore conflicts with a mandatory persistence transition.

**Refinement (ratified under §7).** R6 is redefined from *no tracked mutation* to **NoUncontrolledTrackedMutation**:

```
R6 — Controlled Tracked State Transition

A product execution MUST NOT mutate tracked repository state EXCEPT for the
canonical product artifacts explicitly designated by THIS contract as
sanctioned execution outputs:

    SanctionedProductWrites =
        { src/verification/certificates/<irHash>.json (canonical cert files),
          src/verification/certificates/manifest.json (canonical cert manifest) }

R6(R) ⟺  TrackedDelta(execution) ⊆ SanctionedProductWrites(execution)
     AND  TrackedDelta(execution) ∩ Source/Config/Input/OtherData = ∅

Every sanctioned tracked mutation MUST additionally be:
  1. Write-set limited  — only declared canonical product artifacts change;
  2. Identity-deterministic — same execution ⇒ same certificate identity;
  3. Atomic             — via the existing tmp+rename + TrustCommit journal +
                          rollback promotion transaction;
  4. Idempotent         — same identity + same bytes ⇒ no-op; same identity +
                          different bytes ⇒ hard fail;
  5. No unrelated mutation — source/config/unrelated tracked data unchanged.

Any tracked delta outside SanctionedProductWrites, or violating 1–5, is an R6
FAIL.  This is a meaningful contract amendment (not a silent evaluator carve-
out): the golden-slice readiness check and the R6 evaluator inspect the actual
tracked delta against the sanctioned write-set rather than requiring a clean
tree.  R6 and R8-P are thereby mutually reinforcing: promotion is mandatory
persistence (R8-P) of a sanctioned artifact (R6).

---

## 7. Status & Non-Goals

- **Status**: PROPOSED — NORMATIVE SPEC, submitted for ratification. No product code, no test, no readiness-artifact change is made by this file. Deliverables that instantiate the derivation (a check-only projection tool, a schema for requirement rows) are follow-up artifacts under THIS contract, not made here.

| NOT | Because |
|---|---|
| a competing evaluator | per-invariant PASS/FAIL/UNKNOWN remains the sole arbiter of each R (ADR-0015 locked decision 3). This file authorizes **no** edit to `data/readiness/evaluate.py` and no new evidence collection |
| a policy-criticality edit | `data/readiness/independent_policy.json` is untouched; R7 stays CRITICAL, R4 stays CRITICAL |
| a closure-protocol patch | the closure lifecycle vocabulary, states, and ledger are unchanged; this layer only *consults* records under `CLOSURE_RECORDS_CLOSED` |
| a promise-widening machine | every capability row must trace to the documented v1 product profile (`productization_contract.md` §1); it introduces no third verdict, no conditional, no free-form predicate |
| a measurements register | no telemetry/metrics definitions; VKD stays "a measured truth, not a goal" (`productization_contract.md:226-228`) |
| Verification DAG (build-once → verify-many) | deferred — future identity chain (Source → ActionInputDigest → Canonical Materialization → ArtifactOutputDigest → fan-out) does not exist in src/; v1 uses `(sourceHash, irHash)` per proof directly |
| runner_cell.sh (per-job ephemeral runner wrapper) | deferred (P-D) — current static 2-host pool uses `jit_supervisor.sh` + `flock` per host |
| Pool Controller / elastic provisioning (ARC-like) | **terminated** — CI=0 cutover, 2026-09-20: self-hosted 러너 인프라 제거로 elastic provisioning 자체가 소멸. 원 defer 조건("Controller retention trigger", `self_hosted_ci_migration.md` §135-152)과 governing decision(`docs/ci/scale_set_authority_decision_2026-09-20.md`)의 두 문서는 모두 CI=0으로 삭제됨 |

**Amendments**: any change to the requirement table (§2), the predicate/closure vocabulary (§3-§4), or the verdict rule (§5) is a ratified revision of this contract, with a decision-binding waiver where conflicts exist (§0.10), following the ratification→implementation→re-evaluation discipline of readiness_closure_protocol.md §6.2.

**Ratified Amendment Log**:

| Amendment | Section | Ratified | Summary |
|---|---|---|---|
| R6 → **NoUncontrolledTrackedMutation** | §6.3 + `RUNTIME_BOUNDARY` row (§2) | 2026-08-20 (architect) | Replaces the unqualified `noTrackedMutation` R6 predicate with the controlled-transition predicate: `TrackedDelta(execution) ⊆ SanctionedProductWrites = { src/verification/certificates/<irHash>.json, src/verification/certificates/manifest.json }` and `TrackedDelta ∩ Source/Config/Input = ∅`, with the five sanctioned-write properties (write-set limited, identity-deterministic, atomic, idempotent, no unrelated mutation). Resolves the R6↔R8-P conflict introduced by mandatory canonical-vault persistence. The R4 predicate change (proofDigest optional per contract + DEBT#412) is codified in `data/readiness/evaluate.py` (untracked draft evaluator); ratification is recorded here so the evaluator's predicate matches the ratified contract. |
| §7 Non-Goals → Pool Controller row | §7 Status & Non-Goals | 2026-09-20 — **ratification: pending (architect)** | Superseded by scale-set authority decision (`docs/ci/scale_set_authority_decision_2026-09-20.md`; 문서는 CI=0 cutover, 2026-09-20로 삭제 — 기록으로 보존); **terminated** by CI=0 (elastic provisioning 소멸); ratification: pending (architect) |

Per §7 discipline, a ratified amendment above is binding only when accompanied by (1) the amended predicate in the evaluator, (2) a fresh independent execution that re-collects evidence (not manual observation edits), and (3) the re-derived launch verdict. The 2026-08-20 fresh audit satisfies these.

---

## Appendix A — Verified anchors (2026-08-19/20)

| Claim | Source | Lines |
|---|---|---|
| Latest decision NO-GO; R1/R2/R3/R5/R6 = PASS, R4/R7/R8 = FAIL; blocking [R4, R7, R8] | `data/readiness/decision.independent.20260819T122137Z.json` | 24-98 |
| Closure records for R4/R7/R8; research charter; DEBT#416 | `data/readiness/closure_state.json`; `docs/design/r8_research_charter.md`; `data/debt_registry.json` | whole-file; §2.1-2.2; 2438 |
| ADR-0016 Q1 = YES, Q2 model; both branches keep NO-GO; sole arbiter | `docs/adr/0016-r4-promotion-eligibility.md` | 21-25, 87-94, 96-98 |
| Frozen B1 model — no parallel names | `docs/design/phasec_boundaries.md` | 55-96 |
| Frozen B2 identity formulas | `docs/design/phasec_boundaries.md` | 139-144 |
| v1 promise: evidence-only; primary output JSON + local replay-bound cert; portable NOT a goal | `docs/spec/productization_contract.md` | 18-21, 224-228 |
| SIGSEGV(139) out-of-contract; no signal→exit shim; 4-state exit model | `docs/spec/productization_contract.md` | 246-285 (261, 280) |
| R7 layered target (D1/D2, L1–L3); unratified label | `docs/design/phasec_r7_termination_architecture.md`; `docs/design/r7_exit_authority_gap.md` | Part B/C; §7.3 (172-174) |

## Appendix B — Terms

| Term | Definition |
|---|---|
| launch requirement | one row of §2 — capability, promise, requiredEvidence, predicate, closure, status |
| requiredEvidence | the R-set that EVIDENCES a capability (evidence layer) — never the requirement itself |
| predicate vocabulary | the closed enum of §4 — the only satisfaction-expression language |
| derived away (derived-out) | exclusion from the v1 launch requirement set by this contract (e.g. R8-R) |
| clause | one capability's satisfaction proposition: predicate(requiredEvidence, [closure]) |
| layers | evaluation (per-invariant, `evaluate.py`) vs closure lifecycle (per-blocker) vs entry contract / requirement layer (this file) |