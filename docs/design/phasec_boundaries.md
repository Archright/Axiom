# Phase C0 — Semantic/Identity Boundary Freeze

> **Status**: FROZEN (Phase C — Semantic/Identity Boundary Freeze, step C0)
> **SSOT anchor**: `docs/spec/continual_revalidation.md` §6(e) (locked decision identity), §4 (Outcome taxonomy)
> **Related**: `docs/design/r4_promotion_eligibility_aggregate.md` (promotion authority), `docs/design/phase3_claim_authority.md` (claim authority), `docs/design/phase5_claimstore_index.md` (ClaimOutcome vs CertificateStatus precedent), `docs/spec/evidence_calculus.md` (status label vs proof obligation), `docs/spec/productization_contract.md` (§0.12 contract-first), AGENTS.md §0.9 (theater prohibition)

This document is a **read-only design freeze**: it defines constraints, not
implementation. It proposes **no product code changes** (§7).

---

## Objective

Freeze, as **four separate, non-collapsible boundary axes**, the semantic and identity
boundaries that Phase C must respect:

| Axis | Subject | Section |
|---|---|---|
| B1 | `PromotionState` ≠ `ProofStatus` ≠ `CertificateClaim` (three-way) | §2 |
| B2 | `EvaluationInputIdentity` ≠ `DecisionIdentity`; Identity ≠ Provenance | §3 |
| B3 | Python/Nim evaluator relationship — decide *before* "alignment" | §4 |
| B4 | Normative Artifact ≠ Execution Contract | §5 |

Each axis is **non-collapsible**: no reduction, projection, or derived mapping may
ever fuse two axes into one (§1.1). The "Decision surface" table (§7) records what is
frozen here versus what remains open-to-ratify.

---

## 1. Axis Contract (applies to all axes)

### 1.1 Separation is structural, not nominal

Two axes are separate if and only if, for every pair of states `(s_a ∈ A, s_b ∈ B)`:

```
INVARIANT-AXIS-0: No state of axis A is a state of axis B.
INVARIANT-AXIS-1: No function derives one axis' value from another axis's value alone.
INVARIANT-AXIS-2: A change in one axis NEVER silently changes another axis —
                  cross-axis consequences must be explicit transitions, never implied.
```

Any violation is **axis collapse**. Collapse is not a bug to be patched: it is a
violation of these frozen boundaries and must be reviewed as a contract change
(§0.12), never silently accepted.

### 1.2 Cross-axis rules are stated as guards

Guards in §6 are non-negotiable and bind all of Phase C plus later phases.

---

## 2. Axis B1: PromotionState ≠ ProofStatus ≠ CertificateClaim (three-way)

### 2.1 The three axes

| Axis | Question it answers | Candidate states | Where it lives |
|---|---|---|---|
| **PromotionState** | *May this result be stored / promoted into the canonical certificate / vault?* — a **persistence/promotion decision** | `PROMOTED` / `PROMOTABLE` / `INELIGIBLE` | promotion/write authority (`r4_promotion_eligibility_aggregate.md`) |
| **ProofStatus** | *Is proof required, and is it present?* — the **proof-obligation semantic state** | `REQUIRED_AND_PRESENT` / `REQUIRED_BUT_ABSENT` / `NOT_REQUIRED_BY_CERTIFICATE_TYPE` / `NOT_EVALUATED` | proof-obligation semantics; verifiable from evidence |
| **CertificateClaim** | *What may the stored certificate assert?* — the **claim the artifact carries** | `Evidence-only` vs `Proof-backed`, realized through the existing `CertificateStatus` tier labels (`certGreen`, `certZ3Verified`, `certLeanVerified`, `certRed`, …) | stored certificate; consumer-facing claim |

### 2.2 Candidate state models (frozen as candidates, not final enums)

The state spaces below are frozen as **the** candidate models. Adding a fourth
axis — or hiding extra state inside these spaces — requires the decision-binding
waiver path (§0.10):

```
PromotionState:
  PROMOTED   — written into the canonical vault
  PROMOTABLE — eligibility confirmed, not yet written
  INELIGIBLE — barred from promotion (static or dynamic)

ProofStatus:
  REQUIRED_AND_PRESENT             — obligation exists; honest proof exists
  REQUIRED_BUT_ABSENT              — obligation exists; proof absent (honest state)
  NOT_REQUIRED_BY_CERTIFICATE_TYPE — certificate type imposes no proof obligation
  NOT_EVALUATED                    — obligation never evaluated (neither present nor absent claimed)

CertificateClaim:
  Evidence-only — bounded to observed evidence; no proof-backed assertion
  Proof-backed  — assertable only when ProofStatus == REQUIRED_AND_PRESENT
```

### 2.3 Frozen separation rules

```
INVARIANT-B1-1: PromotionState is a persistence/promotion decision, and nothing more.
                PROMOTED says "where it is written", never "it is proven".
INVARIANT-B1-2: ProofStatus is an evidence fact, not a promotion verdict.
                REQUIRED_BUT_ABSENT is a truthful, storable state — not an error
                code, not an implicit demotion of another axis.
INVARIANT-B1-3: Proof-backed claim requires ProofStatus == REQUIRED_AND_PRESENT.
                Nothing else may carry a Proof-backed claim.
```

Cross-axis propositions:

- **Q1 (the promotion yes/no question)**: A YES on promotion **must NOT** weaken
  `ProofStatus` and **must NOT** raise `CertificateClaim` beyond what evidence
  supports (B1-3).
- A promoted proof-less certificate keeps an honest `ProofStatus`
  (`REQUIRED_BUT_ABSENT` or `NOT_REQUIRED_BY_CERTIFICATE_TYPE`) that does **not**
  impersonate proof-backed.
- A YES on promotion writes to the promotion axis **only**. It must never weaken
  certGreen / proof-backed semantics (Guard G1, §6.1).

Repo precedent for the claim/status discipline:

- `docs/spec/evidence_calculus.md:12` — *"The `status` field in a certificate (e.g.
  `certGreen`, `certZ3Verified`) is a label, not a proof obligation. Admission is
  determined by `admissibleEvidence`"* — never load-bearing by itself.
- `docs/design/phase5_claimstore_index.md:100` — separates `ClaimOutcome`
  (PROVED/DISPROVED) from `CertificateStatus` (certGreen/certRed); the same
  non-collapse discipline applied to the claim store.

---

## 3. Axis B2: EvaluationInputIdentity ≠ DecisionIdentity (Identity ≠ Provenance)

### 3.1 Identity ≠ Provenance (non-negotiable)

```
INVARIANT-B2-1: Identity = reproducible content hash (pure function of content).
INVARIANT-B2-2: Provenance = recording/observation metadata
                (observedAt / createdAt, run ids, host, invocation details).
INVARIANT-B2-3: Provenance is auditability-only. It NEVER feeds into, or replaces,
                an identity digest.
```

A timestamp is provenance. A timestamp inside an identity digest — e.g. a
`decisionId` embedding `%Y%m%dT%H%M%SZ` — violates B2-3 (current instance: the
Python evaluator, §4.2).

### 3.2 The two identities (frozen formulas)

```
EvaluationInputIdentity = H(EvidenceDigest || PolicyDigest || EvaluatorArtifactDigest
                            || SchemaDigest || ExecutionContractDigest)
    — identifies "what inputs + execution contract were evaluated" (NO verdict).

DecisionIdentity = H(EvaluationInputIdentity || Verdict || Outcome)
    — identifies "what the evaluation result was".
```

These are two distinct digest values, never conflated: neither may be substituted
for the other in any ledger, certificate, or cross-evaluation comparison.

### 3.3 Locked anchor: `continual_revalidation.md` §6(e)

This freeze refines — never replaces — the already-locked decision identity, quoted
verbatim:

> (e) **Content-based deterministic decision identity**: `H(policyDigest + evidenceDigest + executionContractDigest + verdict + outcome)`. Parent = lineage metadata only. Serialized record may be timestamp-varying (provenance) even though canonical identity is deterministic.

Alignment table:

| Locked §6(e) input | B2 input | Notes |
|---|---|---|
| `policyDigest` | `PolicyDigest` | direct |
| `evidenceDigest` | `EvidenceDigest` | direct |
| `executionContractDigest` | `ExecutionContractDigest` | first-class input, §3.4 |
| (implicit evaluator of record) | `EvaluatorArtifactDigest` | made explicit: the evaluator bytes |
| (implicit schemas) | `SchemaDigest` | made explicit: input/decision schemas |
| `verdict`, `outcome` | second-hash inputs (`Verdict`, `Outcome`) | never inside `EvaluationInputIdentity` |

`SchemaDigest` and `EvaluatorArtifactDigest` elaborate the locked formula: they make
explicit what §6(e) leaves implicit. Dropping them from a concrete implementation
weakens the identity — and a weakened identity presented as the same identity is
theater (§0.9).

### 3.4 ExecutionContractDigest is a first-class input

```
INVARIANT-B2-4: ExecutionContractDigest is a distinct digest input and is NOT
                EvaluatorArtifactDigest.
    EvaluatorArtifactDigest  = the evaluator bytes — what the artifact IS.
    ExecutionContractDigest  = how it runs —
        interpreter/runtime version (Python version, Nim toolchain, Z3 invocation),
        invocation contract (entry-point, arguments, CWD assumptions),
        filesystem assumptions (readable/writable paths, relative-path dependencies),
        subprocess contract (allowed spawns and their inputs/env),
        env normalization (which env vars are canonicalized, which are excluded).
```

This is why one normative artifact may run under several execution contracts while
its artifact identity stays fixed (B4, §5).

---

## 4. Axis B3: Python/Nim evaluator relationship — decide before "alignment"

### 4.1 The decision rule (frozen)

There are exactly **two allowed relationship classes**; a "blanket align" class is
prohibited:

```
FORK-B3-1: SAME NORMATIVE EVALUATOR
    If two artifacts claim the SAME normative evaluator,
    their identity schemas MUST agree:
      byte-identical inputs => identical EvaluationInputIdentity AND DecisionIdentity.
    Divergence means one side is wrong, not "a different scheme".

FORK-B3-2: INDEPENDENT EVALUATORS
    If two implementations are independent evaluators, each carries its OWN
    EvaluationInputIdentity / DecisionIdentity, namespaced by its own
    EvaluatorArtifactDigest. Cross-evaluation is COMPARISON ONLY — a recorded
    verdict/outcome comparison — never identity absorption. Never merge digests,
    never present one evaluator's identity as the other's.

FROZEN-B3: NEVER blanket-align. Identity convergence REQUIRES the relationship
    class to be ratified (FORK-B3-1 vs FORK-B3-2) before any alignment work.
    "Alignment" without that step is theater: a claim of agreement without an
    established sameness basis.
```

### 4.2 Current divergence (verified 2026-08-19)

| Attribute | `data/readiness/evaluate.py` (Python) | `tools/readiness_evaluator.nim` (Nim) |
|---|---|---|
| Decision identity | `decisionId = "axiom-independent-readiness-" + utcnow` (`evaluate.py:179`) — **timestamp in identity position** | `decisionDigest = canonicalSha256({verdict, conditions, invariantStates})` (`readiness_evaluator.nim:749,769`) — content-based |
| Evaluator fingerprint | `evaluatorBinaryDigest = sha(evaluator_src)` where `evaluator_src = open(os.path.basename(__file__)).read() ... else __file__` (`evaluate.py:173-175`) — **CWD-fragile**: hashes source bytes only when the script exists under CWD, otherwise hashes the invocation path string | deterministic SHA-256 core (`tools/sha256_native.nim`, pure) |
| Digest fields | `policyDigest`, `evidenceManifestDigest`, `evaluatorBinaryDigest` sit next to a timestamp identity (`evaluate.py:183-185`) | `policyHash`, `bundleDigest` sit next to a content-based `decisionDigest` |
| Execution contract in identity | implicit (Python version, CWD) — not a digest input | implicit — not yet an input of `decisionDigest` |

The two evaluators **currently disagree on identity**. Under §4.1 this is
admissible **only** under FORK-B3-2 (independent evaluators, separate namespaced
identities). The same-normative claim (FORK-B3-1) is not satisfiable while the
divergence stands.

### 4.3 Frozen positions for this divergence

```
FROZEN-B3-2a: Until the class is ratified, neither evaluator's identity may be
    presented as the other's canonical identity.
FROZEN-B3-2b: The timestamp-based decisionId (evaluate.py:179) violates B2-3 and
    MUST be fixed either way — provenance moves out of the identity slot.
FROZEN-B3-2c: The CWD-fragile evaluator fingerprint (evaluate.py:173-175) must be
    replaced by a content-based EvaluatorArtifactDigest in any resolution.
```

The ratification of the Python evaluator's role (independent cross-check vs
same-normative re-platform) is **open-to-ratify** (§7).

---

## 5. Axis B4: Normative Artifact ≠ Execution Contract

### 5.1 Normative artifact set (the authority)

The **normative artifact set** is the set of artifacts the evaluation authority
declares as source of truth. It is decided **before** any persistence choice
(commit / tag / content-digest; §5.3):

| Normative artifact class | Current locus | Tracked today (verified 2026-08-19) |
|---|---|---|
| EvaluatorArtifact | `tools/readiness_evaluator.nim` (Nim — decision-predicate SSOT per `continual_revalidation.md`); `data/readiness/evaluate.py` (Python — independent origin) | Nim: tracked. Python: **gitignored** (`.gitignore:121` matches `*.py`) |
| PolicyArtifact | `config/readiness_policy.json` (policy SSOT); `data/readiness/independent_policy.json` (Python's policy copy) | config: tracked. independent copy: **untracked** |
| SchemaArtifact | decision/output schemas (`"schemaVersion": 1` inside decision JSON) | **not defined as a separately versioned artifact** (open item) |
| DecisionArtifact | `data/readiness/decision.*.json` | 2026-08-1x decision files (incl. `decision.GO.2026-08-17.json`) tracked; `decision.independent.20260819T*.json` **untracked** |
| EvidenceSnapshot | `data/readiness/evidence/R1..R8.json` (tracked) + `evidence_manifest.json` (**untracked**) | partial |

### 5.2 Untracked today => non-reproducible

On 2026-08-19, `git status` shows `evidence_manifest.json`,
`independent_policy.json`, `readiness_history.json`, `snapshots/`, and the
`decision.independent.*.json` outputs as **untracked**, while `evaluate.py` is
fully invisible to git (ignored). The Python evaluation's normative artifacts
cannot be reconstructed from the repository.

### 5.3 Frozen rules

```
FROZEN-B4-1: The normative artifact set is the authority; it is decided BEFORE
    the persistence choice (§5.4). No persistence decision may preempt it.
FROZEN-B4-2: Selection authority ("what is authoritative") ≠ execution authority
    ("how it runs": version, invocation contract, fs assumptions, subprocess
    contract, env normalization).
FROZEN-B4-3: A normative artifact may run under different execution contracts
    without changing its identity — B2 keeps artifact digests and execution-
    contract digests apart by construction.
```

### 5.4 Persistence is downstream (order frozen, choice open)

After the artifact set is ratified, one of the following is chosen per artifact
class — this document **freezes the order, not the choice**:

1. git commit of the artifact set;
2. git tag of each artifact;
3. content-addressed store (repo precedent: `data/proof_certificates/`,
   `logs/proof_vault/`).

---

## 6. C0 Guards (non-negotiable)

Two guards bind every Phase C step (and later phases). They exist because, without
them, the C1 step could trade certGreen for a "yes", and the C2 step could re-merge
identity and provenance:

```
GUARD G1 (binds the C1 step):
  Every "YES" emitted by the C1 step — promotion / GO-style acceptance, including
  any Q1 decision point — MUST NOT weaken certGreen / proof-backed semantics:
    - NO new certificate tier or shortcut that bypasses the full evidentiary
      requirement of certGreen and of the "Proof-backed" claim;
    - NO broadening that turns absent proof into "inherent" proof;
    - a YES may touch only the axes it is authorized to touch
      (e.g. PromotionState); it must never weaken ProofStatus or
      CertificateClaim semantics (B1).

GUARD G2 (binds the C2 step and all later steps):
  Deterministic identity and provenance must NEVER be re-merged:
    - provenance fields (observedAt, run ids, host, invocation) are
      auditability items only — NEVER inputs to EvaluationInputIdentity or
      DecisionIdentity;
    - a record may be timestamp-varying in its serialized form (allowed by
      §6(e)) only while its canonical identity stays deterministic;
    - fixing the Python evaluator's timestamp-based identity (evaluate.py:179)
      is REQUIRED for compliance — re-merging here is a defect, not an option.
```

Only a contract change (§0.12 plus the architect review path) can relax a guard.
A phase step "passing" while violating a guard is theater (§0.9): claim without
the substance the claim asserts.

---

## Appendix A: verified line references (2026-08-19)

| Claim | Source | Lines |
|---|---|---|
| Locked decision identity | `docs/spec/continual_revalidation.md` §6(e) | 89 |
| Outcome taxonomy (ObservedState vs DecisionOutcome) | `docs/spec/continual_revalidation.md` §4 | 40-61 |
| Decision-predicate SSOT | `docs/spec/continual_revalidation.md` §4 | 61 |
| Python decisionId = timestamp | `data/readiness/evaluate.py` | 179 |
| Python evaluator digest, CWD-fragile | `data/readiness/evaluate.py` | 173-175 |
| Python policy/manifest digests | `data/readiness/evaluate.py` | 150-151, 183-185 |
| Nim decisionDigest, content-based | `tools/readiness_evaluator.nim` | 749, 769, 784 |
| Nim purity boundary + sha256 core | `tools/readiness_evaluator.nim` | 1-12 |
| Status label ≠ proof obligation | `docs/spec/evidence_calculus.md` | 12 |
| ClaimOutcome vs CertificateStatus separation | `docs/design/phase5_claimstore_index.md` | 100 |
| Promotion = one authority; aggregate() ≠ evidence verifier | `docs/design/r4_promotion_eligibility_aggregate.md` | 11, 114 |
| Policy SSOT | `config/readiness_policy.json` | whole file |

## Appendix B: Terms

| Term | Definition |
|---|---|
| EvaluationInputIdentity | B2: inputs + execution contract only; no verdict |
| DecisionIdentity | B2: EvaluationInputIdentity + verdict + outcome |
| Identity | deterministic content hash (B2-1) |
| Provenance | recording metadata: time, run ids, host — auditability only (B2-2) |
| ExecutionContractDigest | B2-4: how the evaluator runs |
| Normative artifact | B4: what is authoritative, decided before persistence |

## Appendix C: Divergence register (open items, bound to §7)

1. `decisionId` timestamp-in-identity — Python, violates B2-3 / FROZEN-B3-2b.
2. `evaluatorBinaryDigest` CWD-fragile — Python, violates FROZEN-B3-2c.
3. `decisionDigest` in Nim does not yet include `executionContractDigest` (nor the
   B2 two-identity split); pending the §7 B3/B4 ratification order.

Each entry maps to exactly one "Open-to-ratify" cell in §7 and must close through
the B3/B4 ratification sequence before any product code changes.

---

## 7. Decision surface (Axis | Frozen decision | Open-to-ratify)

| Axis | Frozen decision | Open-to-ratify |
|---|---|---|
| B1 | Three-way separation PromotionState / ProofStatus / CertificateClaim; cross-axis implication rules (Q1); candidate state models (§2.2) | Final state names/values for PromotionState and its persistence locus; how certificate-type -> required ProofStatus gets codified |
| B2 | Identity ≠ Provenance (B2-3); the two identity formulas (§3.2); refinement of locked §6(e); ExecutionContractDigest first-class (B2-4) | Canonical `SchemaDigest` input material (which schema bytes/version); digest serialization (input order, field names); whether extra fields (conditions, failureCategory) enter DecisionIdentity |
| B3 | Relationship class must be ratified before any alignment (FORK-B3-1 / FORK-B3-2); no blanket-align; divergence is admissible only as independent evaluation | Ratify the Python evaluator's class (independent cross-check vs same-normative); then converge its identity schema (timestamp out, CWD out) |
| B4 | Normative artifact set (five classes) is the authority; set decided before persistence; selection authority ≠ execution authority | Concrete persistence per artifact class (commit / tag / content-digest); track the currently untracked and gitignored artifacts; define SchemaArtifact explicitly |
| C0 | Guards G1 and G2 are non-negotiable | None — the guards are the freeze |

This document is a **read-only design freeze**: it proposes **no changes to
`src/`, `tests/`, or product-facing `config/`** — no product code changes, no test
changes. It freezes design boundaries only. Changing any "Frozen" cell above —
or weakening any invariant — requires the human-architect review path and the
decision-binding waiver (§0.10, `config/decision_binding.waiver.toml`).