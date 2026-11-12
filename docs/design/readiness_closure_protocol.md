# Readiness Closure Protocol — Per-Blocker Deterministic Closure Lifecycle (Normative Spec)

> **Status**: ADOPTED — NORMATIVE SPEC (protocol verified and adopted with corrections; this spec is the normative contract it fixes). Documentation only — no product code, no test, no readiness-artifact change is made by this file.
> **SSOT anchors**: frozen vocabulary — `docs/design/phasec_boundaries.md` §2 (Axis B1) and §3.2 (Axis B2 identity formulas); point-in-time verdicts — `data/readiness/decision.independent.*.json`; policy — `data/readiness/independent_policy.json`; evidence — `data/readiness/evidence_manifest.json` + `data/readiness/readiness_history.json`; post-GO governance — `docs/spec/continual_revalidation.md` §4/§6(e).
> **Enforcement**: the per-state required-evidence and transition contracts defined in §2 are enforced by the machine schema `data/readiness/closure_state.schema.json` and the checker `tools/readiness_closure_check.nim` (planned implementations of this spec; neither exists at the time of writing — see §9.2).
> **Related**: `docs/adr/0015-phase0-decision-gate-evidence-boundary.md`, `docs/adr/0016-r4-promotion-eligibility.md`, `docs/design/phasec_r7_termination_architecture.md`, `docs/design/r7_exit_authority_gap.md`, `docs/design/r7_cli_outcome_contract.md`, `docs/design/r8_research_charter.md`, `docs/design/r4_promotion_eligibility_aggregate.md`.

---

## 1. Purpose and Domain

### 1.1 Problem

The independent readiness evaluation produces **whole-readiness verdicts** (`finalVerdict` = GO / NO-GO in `decision.independent.<UTC>.json`, `data/readiness/`) but no per-blocker lifecycle. A blocker (`R4`, `R7`, `R8` today) is a CRITICAL invariant in FAIL or UNPROVEN state per `data/readiness/independent_policy.json` blockingPolicy. Once a blocker is recorded, the repository has no single mechanism that answers, for *that blocker*: what has been decided, what is still open, what may be implemented, and what evidence closes it. Each blocker has so far been handled by bespoke documents (ADRs, charters, audit trails) with different vocabularies and no shared machine-readable state.

This protocol defines **one deterministic closure lifecycle** — 10 states, one taxonomy, one record shape — so that every current blocker **and every future blocker (R9, R10, …) is processed by the same machinery**. A future blocker is not a new process: it enters the same lifecycle at OBSERVED.

### 1.2 The master invariant: 코드가 결정을 선행할 수 없다

```
INVARIANT-RCP-0 (ratify-before-implement): 코드가 결정을 선행할 수 없다 —
   code must NEVER precede decision. No implementation of any blocker-scoped change
   may enter the product tree before the record has reached CONTRACT_REVISION_RATIFIED
   for that change. The chain OBSERVED → … → CONTRACT_REVISION_RATIFIED states a
   ratified decision; IMPLEMENTED is unreachable without it. Any product-code or
   product-visible-behavior change in a blocker's domain without its ratified
   revision is a protocol violation (theater under AGENTS.md §0.9: it claims
   closure progress without the ratifying substance).
```

Two concrete consequences already load-bearing today:

- `ax prove --no-such-flag` exits **2** as an **UNRATIFIED implementation routing label** and MUST NOT be changed to 3 until the semantic partition is ratified (`docs/design/r7_exit_authority_gap.md:172-174`). Changing it early would be code preceding decision — it would pre-empt the partition ratification by hard-wiring one answer.
- The `data/readiness/evaluate.py:81-82` R4 re-scope MUST NOT be applied as a code fix; it is a **ratified evaluator-semantic revision** (§6). An applied-but-unratified evaluator edit is exactly "code preceding decision".

### 1.3 Enforcement machinery (schema + checker)

The per-state required-evidence and transition contracts in §2 are the normative contract for:

- `data/readiness/closure_state.schema.json` — the JSON Schema defining `ReadinessClosureRecord` (§4) plus the 10-state machine and the blockerClass pinning rules;
- `data/readiness/closure_state.json` — the machine-readable ledger: `{ "schemaVersion": 1, "protocol": "readiness-closure", "records": [ <ReadinessClosureRecord>... ] }`, one record per blocker (`invariant` = R4/R7/R8/...);
- `tools/readiness_closure_check.nim` — a deterministic checker that validates `closure_state.json` against the schema AND the state-machine / pinning / identity / cross-check rules (§9.2; `exit 0 == valid`).

---

## 2. The State Machine (exactly 10 states)

### 2.1 Overview

```
Forward stages (7):                                      Blocked states (3):
 OBSERVED → CLASSIFIED → SEMANTICALLY_RATIFIED
            → CONTRACT_REVISION_RATIFIED → IMPLEMENTED
            → INDEPENDENTLY_REEVALUATED → CLOSED

pinned side-states (entered per §3, resumed per §2.2):
 BLOCKED_BY_DECISION        — waiting on a ratified decision
 BLOCKED_BY_RESEARCH        — waiting on an isolated research workstream
 BLOCKED_BY_IMPLEMENTATION  — waiting on engineering execution
```

Forward transitions are step-wise (+1); blocked transitions are side-states; resume and regress are deterministic (§2.2). CLOSED is terminal.

### 2.2 Transition grammar

```
FWD:    S(i) → S(i+1)         requires the ENTRY evidence of S(i+1) (per-state, §2.3)
BLOCK:  S(i) → B_pinned        allowed when blockerClass pins B (§3) AND the missing
                               input that blocks the next forward step is of kind B
RESUME: B → S(j)               where S(j) = the earliest forward stage whose ENTRY
                               evidence is made present by the unblocking input
REGRESS:S(j) → S(i)  (i<j)     only when an evaluation or ratification refutes the
                               evidence held at S(i)..S(j); the record falls back to
                               the EARLIEST stage whose entry evidence no longer holds
CLOSE:  INDEPENDENTLY_REEVALUATED → CLOSED
                               requires a decision artifact with the invariant no
                               longer blocking (PASS) or pre-ratified NOT_APPLICABLE
```

Determinism rule (INVARIANT-RCP-1): from any state, the set of legal next states is a function of the record metadata (currentState + evidence fields); the checker rejects any move whose target's entry evidence is absent.

### 2.3 Per-state definition (each: a) meaning · b) required evidence to ENTER · c) transition contract to MOVE OUT)

#### S1 OBSERVED

(a) **Meaning**: the blocker exists as an observation — an invariant result FAIL/UNPROVEN in a readiness decision. Also the entry for future blockers (R9, R10, …) once an evaluation observes them.
(b) **Required evidence to ENTER**: an evaluation artifact carrying the invariant's FAIL/UNPROVEN result (point-in-time `decision.*.json`), and `observedEvidenceDigest` set from that evaluation's evidence manifest/snapshot. For a PLANNED blocker not yet observed, `observedEvidenceDigest` is ABSENT and carries a `toBeComputedAt` marker — never a fabricated digest (§4.3, INVARIANT-RCP-3).
(c) **Transition contract to MOVE OUT** (→ CLASSIFIED): the record gains a taxonomy classification with the root-cause location and the `blockerClass` decision — no more, no less.

#### S2 CLASSIFIED

(a) **Meaning**: the blocker has a `blockerClass` per §3 — the class that decides everything downstream: which blocked state it may rest in and which ratification kind it needs.
(b) **Required evidence to ENTER**: `blockerClass` ∈ {SEMANTIC_DECISION, CONTRACT_ARCHITECTURE_DECISION, BOUNDARY_NON_GOAL, RESEARCH, IMPLEMENTATION}, with the observed evidence cited (doc/file anchor).
(c) **Transition contract to MOVE OUT**:
- class ∈ {SEMANTIC_DECISION, CONTRACT_ARCHITECTURE_DECISION, BOUNDARY_NON_GOAL} and the semantic question not yet ratified → **BLOCKED_BY_DECISION** (pinning rule §3); otherwise → **SEMANTICALLY_RATIFIED**;
- class = RESEARCH → **BLOCKED_BY_RESEARCH** (the research workstream starts);
- class = IMPLEMENTATION → **BLOCKED_BY_IMPLEMENTATION** (a ratified decision exists; engineering pending).

#### S3 SEMANTICALLY_RATIFIED

(a) **Meaning**: the semantic question behind the blocker is decided by a ratified decision record — Q1/Q2 of ADR-0016 (R4's promotion semantics, whose closure leaves NO-GO unchanged) or, for R7, the Part B ratified decision order in `phasec_r7_termination_architecture.md`. The *semantics* are decided; the *evaluator-visible contract/policy revision* is not yet.
(b) **Required evidence to ENTER**: `ratification[]` non-empty; each entry is a ratified decision reference (path + relevant lines + the ratified answer) that pins down what the evaluator's invariant should mean after closure.
(c) **Transition contract to MOVE OUT** (→ CONTRACT_REVISION_RATIFIED): a single ratified revision exists that carries the policy/contract/evaluator-scope change **as one revision** (§6.2). Without it, the record stays put or rests in BLOCKED_BY_DECISION.

#### S4 CONTRACT_REVISION_RATIFIED

(a) **Meaning**: the contract/policy revision that changes the evaluator's obligations themselves is ratified — the exact set of artifact changes (policy manifest, evaluator-scope predicate, contract doc lines) is fixed, with a ratification identity.
(b) **Required evidence to ENTER**: `contractRevision` set — { revisionId, ratification reference, ratified artifact paths (e.g. `data/readiness/independent_policy.json`, `data/readiness/evaluate.py:81-82` re-scope) }. The revision MUST bundle policy + evaluator-scope as ONE revision whenever the evaluator predicate decides the invariant (§6.2).
(c) **Transition contract to MOVE OUT** (→ IMPLEMENTED): the revision is applied; the implementation identity is recorded.

#### S5 IMPLEMENTED

(a) **Meaning**: the ratified revision is implemented — product code, policy manifest update, evaluator-scope re-scope — whatever the revision says; nothing more (§6.2).
(b) **Required evidence to ENTER**: `implementationRevision` — commit/artifact identity + the changed artifact paths. The ratified predecessor (§2.2 FWD / INVARIANT-RCP-0) is a precondition: a checker sees IMPLEMENTED without a CONTRACT_REVISION_RATIFIED stage as a ratify-before-implement violation.

(c) **Transition contract to MOVE OUT** (→ INDEPENDENTLY_REEVALUATED): a NEW evidence snapshot is collected at the implemented tree, `readiness_history.json` lineage is appended, and the independent evaluator re-runs unchanged per ADR-0015:132-135 on the new snapshot.

#### S6 INDEPENDENTLY_REEVALUATED

(a) **Meaning**: the blocker's invariant is recomputed by the independent evaluator on the post-implementation snapshot. `status` reflects the new outcome (PASS/FAIL/UNPROVEN/NOT_APPLICABLE; §4.2); `evaluationIdentity` is computed per the frozen formulas (§4.3) for this evaluation.
(b) **Required evidence to ENTER**: the re-evaluation result (decision artifact section for the invariant) + the evaluation identity terms being computable, or explicitly planned.
(c) **Transition contract to MOVE OUT**:
- outcome ∈ {PASS, NOT_APPLICABLE (pre-ratified)} → **CLOSED**;
- outcome = FAIL/UNPROVEN → **REGRESS** to the earliest forward stage whose entry evidence is refuted. The re-evaluation is the honest judge — an unchanged FAIL is a refutation of the revision, not a forgiven step.

#### S7 CLOSED

(a) **Meaning**: the blocker no longer blocks readiness — it is absent from `blockingInvariants` (PASS) or pre-ratified NOT_APPLICABLE in the latest decision; the record is the durable trace. CLOSED is terminal — later re-openings are NEW records (a new OBSERVED) whose `predecessor` is this record.
(b) **Required evidence to ENTER**: a fresh decision artifact where the invariant ∈ {PASS, NOT_APPLICABLE} (absent from `blockingInvariants`), its DecisionIdentity recorded; `status` ∈ {PASS, NOT_APPLICABLE}.
(c) **Transition contract to MOVE OUT**: none — terminal.

#### B1 BLOCKED_BY_DECISION

(a) **Meaning**: the lifecycle rests because a required decision is unratified: a semantic question, a contract/architecture change, or a boundary non-goal statement.
(b) **Required evidence to ENTER**: pinning (§3) + the record showing exactly the missing piece — an empty/unsatisfied `ratification` or `contractRevision` while the resume target (earliest unsatisfied forward stage) is recorded.
(c) **Transition contract to MOVE OUT**: the pending decision is ratified — new `ratification[]` / `contractRevision` entries with their decision identity — and the RESUME rule applies (§2.2). Example: R4, once the evaluator-semantic revision is ratified, resumes at CONTRACT_REVISION_RATIFIED (§9.1).

#### B2 BLOCKED_BY_RESEARCH

(a) **Meaning**: the blocker depends on an isolated research workstream (R8; ADR-0015 F4=B). The lifecycle waits on research, which does NOT consume the readiness evidence (sealed).
(b) **Required evidence to ENTER**: class RESEARCH + the research charter reference (`docs/design/r8_research_charter.md`) + the blocking research question (the obligation-generation dead-end tracked as DEBT#416).
(c) **Transition contract to MOVE OUT**: a research result has been **deliberately adopted** (an architect decision on the proposal, per `r8_research_charter.md` §2.2) — NOT merely produced. Adoption → SEMANTICALLY_RATIFIED (findings ratified as semantics), then the normal chain; the first re-evaluation runs on a NEW evidence snapshot (charter §2.2), never on the current evidence.

#### B3 BLOCKED_BY_IMPLEMENTATION

(a) **Meaning**: decisions exist; the ratified, contracted revision awaits engineering execution (queue, dependency, capacity).
(b) **Required evidence to ENTER**: a ratified revision (`contractRevision`) whose implementation is unsatisfied, with the reason (queue/dependency).
(c) **Transition contract to MOVE OUT** (→ IMPLEMENTED): the implementation appears with `implementationRevision` — resume at IMPLEMENTED.

---

## 3. blockerClass taxonomy and pinning

Exactly five classes. The class pins WHICH blocked state the record may rest in. Any off-pin residency is an invalid record (INVARIANT-RCP-2, checked by schema + checker):

| blockerClass | Pinned blocked state | Meaning of the blocker per class |
|---|---|---|
| `SEMANTIC_DECISION` | BLOCKED_BY_DECISION | a semantic question must be decided before any revision (R4's promotion semantics; R7's semantic partition) |
| `CONTRACT_ARCHITECTURE_DECISION` | BLOCKED_BY_DECISION | a contract/architecture question decides the boundary/design (the R7 layered exit architecture vs the contract table) |
| `BOUNDARY_NON_GOAL` | BLOCKED_BY_DECISION | the invariant's subject is a documented v1 non-goal; closure = contract revision ratifying the boundary + policy pre-ratified NOT_APPLICABLE per ADR-0016's pattern — never a manufactured PASS |
| `RESEARCH` | `BLOCKED_BY_RESEARCH` | no admissible semantic exists yet; research is the only path (VKD 0/23 via DEBT#416) |
| `IMPLEMENTATION` | `BLOCKED_BY_IMPLEMENTATION` | semantics + contract ratified; engineering work is the whole remainder |

**Pinning rule (INVARIANT-RCP-2)**: a record in a blocked state MUST be in the state pinned by its `blockerClass` — the schema enumerates {class → state} exactly as this table; the checker enforces that mapping, so any off-pin record is invalid.

---

## 4. ReadinessClosureRecord — machine schema

### 4.1 Field contract (normative; `data/readiness/closure_state.schema.json` implements exactly these names)

| Field | Meaning | Present from… | Law |
|---|---|---|---|
| `invariant` | the readiness invariant this record tracks (R4, R7, R8, R9, …) | OBSERVED | one record per invariant; key of the file |
| `currentState` | one of the exactly-10 states §2.1 | OBSERVED | schema enum — no other string is valid |
| `status` | latest invariant outcome observed by an evaluation: `FAIL` / `UNPROVEN` / `PASS` / `NOT_APPLICABLE` (vocabulary of `independent_policy.json` stateSemantics) or `PLANNED` (unobserved; only with `toBeComputedAt`) | OBSERVED | CLOSED requires `PASS` or `NOT_APPLICABLE` |
| `blockerClass` | taxonomy class §3 — pins the blocked state | CLASSIFIED | INVARIANT-RCP-2 |
| `observedEvidenceDigest` | content digest of the evidence manifest/snapshot that first observed the blocker | OBSERVED | never fabricated; `toBeComputedAt` only while unobserved |
| `ratification` | ordered list of ratified decisions — each entry: ref (ADR/doc) + lines + the ratified claim | SEMANTICALLY_RATIFIED | each entry is one ratified decision with its identity |
| `contractRevision` | the ONE ratified revision {id, ratification ref, artifact paths} | CONTRACT_REVISION_RATIFIED | bundles policy + evaluator-scope when the evaluator decides the invariant (§6.2) |
| `implementationRevision` | identity of the implemented revision (commit/artifact digest) + changed paths | IMPLEMENTED | impossible before its ratified revision (INVARIANT-RCP-0) |
| `evaluationIdentity` | canonical identity pair per frozen formulas §4.3 | INDEPENDENTLY_REEVALUATED (or planned) | INVARIANT-RCP-3 |
| `priorEvaluations[]` | historical evaluation references (§4.4) | OBSERVED | INVARIANT-RCP-4 |
| `predecessor` | id of the prior record in this blocker's chain (null on the first) | OBSERVED | chain integrity |
| `created` / `updated` | point-in-time timestamps | OBSERVED | provenance only — B2-2/B2-3: never into any digest |

### 4.2 A canonical record, worked example (the R4 record today)

```jsonc
{
  "schemaVersion": 1,
  "recordId": "closure/R4.20260819.1",
  "invariant": "R4",
  "currentState": "SEMANTICALLY_RATIFIED",
  "status": "FAIL",
  "blockerClass": "SEMANTIC_DECISION",
  "observedEvidenceDigest": "b1c21216e7554681811953e6783a3e6f99639b3777fffdaedda7d96b0812be05",
  "ratification": [
    { "ref": "docs/adr/0016-r4-promotion-eligibility.md", "ratifies": "Q1 = YES (proof-less verification results ARE promotable); Q2 = ProofStatus model (certificate-level)", "lines": "21-98" }
  ],
  "contractRevision": { "id": null, "toBeComputedAt": "Policy v2 + evaluate.py:81-82 re-scope ratified as ONE revision (§6)", "artifactPaths": ["data/readiness/independent_policy.json", "data/readiness/evaluate.py"] },
  "implementationRevision": { "id": null, "toBeComputedAt": null },
  "evaluationIdentity": {
    "EvaluationInputIdentity": {
      "formula": "H(EvidenceDigest ‖ PolicyDigest ‖ EvaluatorArtifactDigest ‖ SchemaDigest ‖ ExecutionContractDigest)",
      "terms": {
        "EvidenceDigest": { "computed": "b1c21216…" },
        "PolicyDigest":        { "computed": "617f6e7e…" },
        "EvaluatorArtifactDigest": { "computed": "a8ad5b82…" },
        "SchemaDigest":        { "toBeComputedAt": "B4: SchemaArtifact separately versioned" },
        "ExecutionContractDigest": { "toBeComputedAt": "B4: execution contract an explicit identity input" }
      }
    },
    "DecisionIdentity": {
      "formula": "H(EvaluationInputIdentity ‖ Verdict ‖ Outcome)",
      "value": { "toBeComputedAt": "canonical identity after the B2/B3 identity corrections (FROZEN-B3-2b/c)" },
      "Verdict": "NO-GO",
      "Outcome": "FAIL"
    }
  },
  "priorEvaluations": [
    { "ref": "data/readiness/decision.independent.20260819T093022Z.json", "note": "historical reference only; timestamp decisionId violates B2-3 — NOT a canonical evaluationIdentity" },
    { "ref": "data/readiness/decision.independent.20260819T122137Z.json", "note": "current NO-GO; invariantResult FAIL; blockingInvariants = [R4, R7, R8]" }
  ],
  "predecessor": null,
  "created": "2026-08-19T21:21:00Z",
  "updated": "2026-08-19T21:21:00Z"
}
```

(For readability the example keeps digest prefixes; a real record holds full 64-hex values. Where a field is absent at its stage, the schema requires the `toBeComputedAt` marker object rather than the field being silently dropped — an absent-yet-undeclared identity term is a schema violation.)

### 4.3 `evaluationIdentity` — frozen formulas and the planned-term rule (INVARIANT-RCP-3)

The canonical identities MUST follow the frozen composite formulas, reproduced verbatim from `docs/design/phasec_boundaries.md:139-144` (Axis B2):

```
EvaluationInputIdentity = H(EvidenceDigest ‖ PolicyDigest ‖ EvaluatorArtifactDigest
                             ‖ SchemaDigest ‖ ExecutionContractDigest)
     — identifies "what inputs + execution contract were evaluated" (NO verdict).

DecisionIdentity = H(EvaluationInputIdentity ‖ Verdict ‖ Outcome)
     — identifies "what the evaluation result was".
```

These are the ONLY identity formulas accepted in a record. Where a term is not yet computable — `SchemaDigest` (the schema is not yet a separately-versioned artifact, B4 open item), `ExecutionContractDigest` (not yet an identity input of either evaluator), or the canonical input serialization — the term is **planned/absent with a `toBeComputedAt` marker**, NEVER a fabricated digest. Fabricated identity terms violate the F2 no-fabrication law (ADR-0015) and B2 determinism; the checker treats any digest-valued term whose computation is not checkable as invalid.

### 4.4 `priorEvaluations[]` — the historical registry (INVARIANT-RCP-4)

`priorEvaluations` preserves HISTORICAL evaluation references — e.g. the two existing decision artifacts `data/readiness/decision.independent.20260819T093022Z.json` and `data/readiness/decision.independent.20260819T122137Z.json` (the latter is the current NO-GO: `blockingInvariants = [R4, R7, R8]`, `finalVerdict = NO-GO`). These are explicitly **NOT the canonical `evaluationIdentity`**: their `decisionId` embeds a timestamp (`data/readiness/evaluate.py:179`), which violates B2-3 / FROZEN-B3-2b — a timestamp inside an identity digest is not an identity. The canonical identity is computed per §4.3 for each evaluation the record chooses to carry; archived artifacts stay as historical references, never pressed into the identity slot.

### 4.5 Chain integrity

`predecessor` links record revisions; `created`/`updated` are provenance timestamps whose only legal use is audit. A CLOSED record is terminal; a re-occurrence is a NEW record in the chain, never a mutation of the closed record.

---

## 5. Alignment with the frozen vocabulary — no parallel names

The certificate-semantics three-axis model is frozen at `docs/design/phasec_boundaries.md:55-96` (Axis B1). This protocol MUST NOT introduce parallel names; every reference uses the frozen name only:

- **PromotionState** = `PROMOTED` / `PROMOTABLE` / `INELIGIBLE` — a persistence/promotion decision.
- **ProofStatus** = `REQUIRED_AND_PRESENT` / `REQUIRED_BUT_ABSENT` / `NOT_REQUIRED_BY_CERTIFICATE_TYPE` / `NOT_EVALUATED` — the proof-obligation semantic state.
- **CertificateClaim** = `Evidence-only` vs `Proof-backed` — what the stored certificate may claim.
- INVARIANT-B1-1: promotion ≠ proof — `PROMOTED` says where it is written, never "it is proven".
- INVARIANT-B1-2: `REQUIRED_BUT_ABSENT` is a truthful, storable state — not an error (the model the R4 closure rides).
- INVARIANT-B1-3: a Proof-backed claim requires `ProofStatus == REQUIRED_AND_PRESENT`; nothing else may carry it.

```
INVARIANT-RCP-5 (no parallel names): the closure vocabulary never introduces a
   parallel name — a local string that denotes one of the frozen states (a renamed
   PromotionState, a new ProofStatus value, a renamed claim tier) is a protocol
   violation. Any state the closure protocol needs ALREADY LIVES in the B1 model;
   a record adding a new axis is a contract change, requiring the decision-binding
   waiver path (§0.10, config/decision_binding.waiver.toml).
```

**R4's closure semantics build on this model (§6):** the evaluator re-scope states exactly the frozen ProofStatus reading for proof-less v1 certificates — `NOT_REQUIRED_BY_CERTIFICATE_TYPE` (ADR-0016 Q2) with an `Evidence-only` claim — never a blanket `NOT_APPLICABLE` label and never a claim-tier boost; closing R4 therefore cannot weaken `certGreen`/Proof-backed semantics (Q2 guard) and never fabricates a proof digest (F2).

---

## 6. The R4 closure caveat (mandatory)

### 6.1 Closing R4 is NOT "Policy v2 pending"

The blocker closes only through a **RATIFIED EVALUATOR-SEMANTIC-REVISION step**: the policy AND the re-scope of `data/readiness/evaluate.py:81-82` — the rule that FAILs R4 when `any(pv is None for pv in proof)` ("proofDigest absent/null on cert (proof-artifact pipeline unimplemented)") — ratify and land **as ONE revision**:

- **policy**: the independent policy gains the pre-ratified-eligible statement — "`certProofDigest` absence (null) while the proof-artifact pipeline is unimplemented = honest NOT-scored per contract §R4; proof-less v1 certificates are not scored on proof presence" (ADR-0016 consequence 1); and
- **evaluator re-scope**: null `certProofDigest` is re-scoped into the frozen ProofStatus model — `NOT_REQUIRED_BY_CERTIFICATE_TYPE` (certificate type imposes no proof obligation) — never to a blanket `NOT_APPLICABLE` *claim role* and never to a bare PASS; the theater guard stays: `noEmptyFieldPromotion` stays, the honest `NOT_APPLICABLE` reason text stays, and `proofDigest` is never fabricated (F2) — per ADR-0016:108-111.

Per ADR-0016 (`docs/adr/0016-r4-promotion-eligibility.md:107,112-114`): "Re-score `evaluate.py:81-82` so null `certProofDigest` is not an R4 FAIL" and "Policy v2 is ratified as its own decision … the independent evaluator then re-runs unchanged against it … **any evaluator change IS a policy change that itself requires ratification**". Hence S4 requires exactly this shape: policy + evaluator-scope as one ratified revision.

### 6.2 Tension with ADR-0015's "rerun unchanged" (locked decision 3)

ADR-0015 (`docs/adr/0015-phase0-decision-gate-evidence-boundary.md:132-135`) locks: the independent evaluator is the sole GO/NO-GO arbiter (R1–R8) **and must rerun unchanged**. The R4 revision must NOT be framed as "we fixed the evaluator to match the product" NOR as "the policy was quietly aligned" — both framings are ratification theater. Under this protocol the sequence is: **RATIFY the evaluator+policy revision as one decision object — then the evaluator re-runs unchanged AGAINST THE RATIFIED REVISION**. "Unchanged" binds the observer to the ratified artifact, not to the pre-ratification byte-for-byte state. The checker verifies the revision identity on the record rather than trusting a silent edit.

(Separately, the Python-evaluator identity divergence vs the Nim repository evaluator — timestamp-based `decisionId` (`evaluate.py:179`) and CWD-fragile fingerprint (`evaluate.py:173-175`) — remains open-to-ratify under B3/FROZEN-B3-2b/2c; that B3 ratification is NOT a precondition for the R4 re-scope §6 prescribes, and it does NOT license any identity fabrication.)

### 6.3 Even after R4 closes, the verdict stays NO-GO

Closing R4 changes nothing in the verdict alone: R7 and R8 remain FAIL/blocking under the same independent policy (`data/readiness/decision.independent.20260819T122137Z.json` — `blockingInvariants = [R4, R7, R8]`). After R4 = CLOSED, R7 + R8 still block → **finalVerdict remains NO-GO** (ADR-0016 §2.5: "Both branches keep NO-GO unchanged").

```
INVARIANT-RCP-6 (blocker closure ≠ verdict): closing one blocker never shifts the
   whole-readiness verdict. The verdict is a function of the evaluator's next
   decision artifact, not of any record's currentState.
```

---

## 7. Current honest state of the blockers (record anchors)

Evidence base: `data/readiness/decision.independent.20260819T122137Z.json` (R4 FAIL, R7 FAIL, R8 FAIL; `blockingInvariants = [R4, R7, R8]`; `finalVerdict = NO-GO`).

### 7.1 R4 — SEMANTICALLY_RATIFIED (decision-bound; may rest in BLOCKED_BY_DECISION while the ratification is pending)

The semantics are ratified: ADR-0016 — Q1 = **YES** (a proof-less verification result MAY be promoted, because the v1 contract declares `proofDigest` optional) and Q2 = the certificate-level ProofStatus model, with the Q2 guard (proof-less promotion never weakens `certGreen`/Proof-backed semantics; `NOT_REQUIRED_BY_CERTIFICATE_TYPE` is the v1 branch). No `contractRevision` or `implementationRevision` exists yet — the honest per-state record. `status` = FAIL (latest evaluation). When the evaluator-semantic revision is ratified per §6, the chain moves per §9.1.

### 7.2 R7 — BLOCKED_BY_DECISION, blockerClass CONTRACT_ARCHITECTURE_DECISION

- The layered model — command-domain outcome → classification policy → single process boundary: `DomainOutcome → ClassificationPolicy → TerminationInstruction` — is ALREADY the target design in `docs/design/phasec_r7_termination_architecture.md` (Part B decision order D1/D2; Part C L1/L2/L3):
  - D1 per-command domain outcome enums; L1 pure per-domain classifiers next to each command module;
  - D2 per-domain policy rows; L2 = the per-site mapping workbook (every P1 `quit(` site — the table is the source of truth for the conversion diff); any outcome with no {0,1,2,3} bucket stays a `CH_RATIFY` row — never a silent remap;
  - L3: single process boundary `exitWith(CliOutcome)`, and the `quit(0)` fall-through at `action_interpreter_cli.nim:204` is deleted.
- **The semantic-partition ratification is pending** (§C.4): the InvalidInput / VerificationFailure / InternalError / EnvironmentError → exit-code attribution (incl. `release roNoBump/roDirtyWorktree`, `cert coJournalRequired`, topology `toApplyRollbackFailed`, `verify` no-claims vs bad-dir), and the exit-table options (3 candidates). The exit-table part would revise `docs/spec/productization_contract.md:263-281` — outside any record's authority until ratified.
- Honest boundary facts for the record: `ax prove --no-such-flag` → 2 is an **UNRATIFIED implementation routing label** (`docs/design/r7_exit_authority_gap.md:172-174`), not a product classification, and MUST NOT be changed to 3 before the partition is ratified (INVARIANT-RCP-0). `SIGSEGV (139)` stays **OUT_OF_CONTRACT** — never shimmed to 2 (`docs/spec/productization_contract.md:259,261,280`; `docs/design/r7_cli_outcome_contract.md` INV-5: no signal→exit-code shim; a SIGSEGV-to-2 handler would be theater (§0.9)).
- **Count correction (repeat for the record notes)**: "83 termination sites" = 83 total direct `quit(` sites (corrected count per `phasec_r7_termination_architecture.md` A.1); only the **38 P1 sites** are the mappable set for the layered conversion (the L2 workbook maps every P1 `quit()` site). Records must keep the 38/83 distinction — 83 is the raw total, 38 is the mappable product-boundary set.

### 7.3 R8 — BLOCKED_BY_RESEARCH, blockerClass RESEARCH

- R8 is an **isolated research workstream** per `docs/design/r8_research_charter.md` (sealed list §2.1; MAY/MUST-NOT table §6): nothing an R8 researcher produces may touch `data/readiness/**` or perturb the R4/R7 evidence base.
- **ADR-0015 F4 = B**: no admissible golden target exists without new verification semantics → R8 MUST NOT be executed as persistence engineering; the obligation-generation (CHC) semantics must first produce real obligations.
- Root cause **DEBT#416** (`data/debt_registry.json:2438` — UNRESOLVED): CHC/Spacer declines all kernel obligations; VKD = **0/23** (`data/baseline.json` — unchanged until the evaluator re-runs).
- Re-entry gate: a research result enters the product path only after **deliberate adoption** (architect decision), then a NEW evidence snapshot → NEW evaluator run (charter §2.2). An R8 result is a readiness milestone, not a license to skip the gates.

---

## 8. Relation to existing machinery (what this adds)

| Existing machinery | Provides (whole-readiness / point-in-time) | NOT provided — the gap this protocol fills |
|---|---|---|
| `data/readiness/decision.*.json` | point-in-time: PASS/FAIL/UNPROVEN per invariant, GO/NO-GO verdict, `blockingReasons` | per-blocker lifecycle — what closes it, what's missing, where it resumes |
| `data/readiness/readiness_history.json` | snapshot lineage: evidence-manifest digests, BEFORE/AFTER snapshots, run ids (audit trail) | any lifecycle semantics — a lineage ledger, not a closure ledger |
| `docs/spec/continual_revalidation.md` | post-GO governance loop: ObservedState/DecisionOutcome tables (PASS→CONTINUE, FAIL→BLOCK/UNRESOLVED), reopen criteria | per-blocker tracking: it revalidates the whole readiness; a single invariant's closure is not tracked |
| **Readiness Closure Protocol** (this spec) | per-blocker lifecycle §2–§4: state machine, blockerClass pinning, ratification chain, identity honesty | exactly the per-blocker lifecycle tracking none of the above provides |

The closure records are **not an additional projection engine and not a duplicate decision maker**: they consume the existing decision artifacts, reuse the frozen vocabulary, and add only the lifecycle layer. The evaluator remains the sole authority (ADR-0015 locked decision 3); the protocol never changes a verdict — it records the path to one.

---

## 9. Usage — advancing a record

### 9.1 How a future engineer/agent advances a record

A record advances by supplying the missing target-state evidence — the move is valid iff the target's entry evidence is present (§2.3; the checker verifies this):

1. **OBSERVED → create / re-establish**: build the record from the latest decision artifact (invariant, FAIL/UNPROVEN status, evidence digest).
2. **CLASSIFIED**: add the taxonomy class with its citation; rest in the pinned blocked state per §3.
3. **SEMANTICALLY_RATIFIED**: record the ratified decision in `ratification[]`.
4. **CONTRACT_REVISION_RATIFIED**: record the ONE-revision decision (policy + evaluator-scope bundled) in `contractRevision`.
5. **IMPLEMENTED**: apply the ratified revision, record `implementationRevision`, then a NEW snapshot.
6. **INDEPENDENTLY_REEVALUATED**: independent evaluator rerun against the new snapshot; update `status`, `evaluationIdentity`, `priorEvaluations`.
7. **CLOSED**: when the invariant leaves `blockingInvariants` (PASS) or is pre-ratified NOT_APPLICABLE; record the DecisionIdentity.

Worked example (the R4 path, once the revision is ratified):

```
R4: SEMANTICALLY_RATIFIED
      --(ratified evaluator-semantic revision: Policy v2 + evaluate.py:81-82 as ONE)-->
    CONTRACT_REVISION_RATIFIED
      --(apply)--> IMPLEMENTED
      --(new snapshot; evaluator rerun) --> INDEPENDENTLY_REEVALUATED
      --(decision: R4 out of blockingInvariants)--> CLOSED
      then: R7, R8 still FAIL  =>  finalVerdict stays NO-GO
```

R7: after the semantic partition is ratified (§C.4), the record resumes at CONTRACT_REVISION_RATIFIED → the layered conversion (L2 workbook) as IMPLEMENTED → re-evaluated → CLOSED (exit codes in contract; SIGSEGV stays out-of-contract).
R8: after a research result is deliberately adopted (the ONLY gate; the research never evaluates the current evidence) — SEMANTICALLY_RATIFIED (findings) → CONTRACT → IMPLEMENTED (obligation-semantics fix) → NEW snapshot → re-run (VKD > 0, R8 closure) → CLOSED.

### 9.2 Deterministic validation (`tools/readiness_closure_check.nim`)

After any move, the checker validates the record (normative):

- **schema conformance**: field `toBeComputedAt` handling, enums (`currentState` ∈ the 10 states, `blockerClass` ∈ the 5 classes, `status` ∈ {FAIL, UNPROVEN, PASS, NOT_APPLICABLE, PLANNED}), types.
- **state machine**: the current state is reachable from the record's own evidence (entry evidence of the current state present); forward moves are +1 steps only; CLOSED is terminal.
- **pinning**: blocked state == pin(blockerClass) (INVARIANT-RCP-2).
- **identity honesty**: absent identity terms carry `toBeComputedAt`, not a fabricated value (INVARIANT-RCP-3); `priorEvaluations` never masquerade as the canonical identity (INVARIANT-RCP-4); `IMPLEMENTED` without a ratified predecessor = failure (INVARIANT-RCP-0).
- **exit code**: `exit 0` = valid record; non-zero = the list of violated clauses. The checker is deterministic and pure — reproducibility is part of the contract.

The checker does NOT decide whether a blocker is closed: the independent evaluation decides. The checker declares the record honest against the lifecycle.

---

## 10. Status / scope

- **Status**: ADOPTED — NORMATIVE SPEC. This file changes no product code, test, or readiness artifact.
- **Immediate open items** (tracked in §6.2 / B4, NOT blockers of the spec): canonical `SchemaDigest` + `ExecutionContractDigest` inputs (B4), B3 class ratification for the Python evaluator identity (FROZEN-B3-2b/2c), and the artifact-commit decision for the untracked readiness set — each is a per-blocker item once the records exist.
- **Deliverables of this spec** (created in follow-up steps, not by this file): `data/readiness/closure_state.schema.json`, `data/readiness/closure_state.json` (the `records[]` ledger — R4/R7/R8), and the deterministic checker `tools/readiness_closure_check.nim`.

---

## Appendix A — Verified anchors (2026-08-19)

| Claim | Source | Lines |
|---|---|---|
| Current NO-GO verdict with blockers R4/R7/R8 | `data/readiness/decision.independent.20260819T122137Z.json` | 44-49, 62-76, 92-98 |
| R4 hard-rule re-scope point | `data/readiness/evaluate.py` | 81-82 |
| R4 policy change / reruns unchanged — "any evaluator change IS a policy change" | `docs/adr/0016-r4-promotion-eligibility.md` | 107, 112-114 |
| F4 = B research blocker + locked decision 3 (rerun unchanged) | `docs/adr/0015-phase0-decision-gate-evidence-boundary.md` | 83-102, 132-135 |
| Frozen identity formulas (B2) | `docs/design/phasec_boundaries.md` | 139-144 |
| Frozen three-axis model (B1) | `docs/design/phasec_boundaries.md` | 55-96 |
| R7 layered target design D1/D2/L1-L3 | `docs/design/phasec_r7_termination_architecture.md` | Part B (D1-D2), Part C (L1-L3, C.4), A.1 (83/38) |
| R7 `ax prove --no-such-flag → 2` unratified label | `docs/design/r7_exit_authority_gap.md` | 172-174 |
| SIGSEGV out-of-contract + no signal→exit shim | `docs/spec/productization_contract.md`; `docs/design/r7_cli_outcome_contract.md` | 259, 261, 280 ; INV-5 |
| R8 research charter: isolation, adoption gate | `docs/design/r8_research_charter.md` | §2.1-2.2, §5, §6 |
| R8 root cause + VKD | `data/debt_registry.json`; `data/baseline.json` | 2438 ; 29-33 |
| Readiness history = snapshot lineage only | `data/readiness/readiness_history.json` | whole file |
| Post-GO governance: ObservedState/DecisionOutcome | `docs/spec/continual_revalidation.md` | §4, §6(e) |

## Appendix B — Terms

| Term | Definition |
|---|---|
| blocker | a CRITICAL invariant (R4, R7, R8, R9, …) in FAIL/UNPROVEN per `independent_policy.json` |
| ReadinessClosureRecord | the per-blocker machine record (§4) |
| closure stage | one of the 10 states §2.1 |
| evaluationIdentity | the frozen B2 identity pair (§4.3) |
| toBeComputedAt | the marker for an absent-but-planned term — never fabricated (§4.3) |
| priorEvaluations | historical reference list — never canonical identity (§4.4) |
| ratify-before-implement | INVARIANT-RCP-0: 코드가 결정을 선행할 수 없다 |