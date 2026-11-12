# R8 — Productization Blocking Surface — Isolated Research Charter (Phase 2 / Research)

**Status**: Charter (scoping only — NO product code, NO test, NO readiness-artifact changes)
**Gates on**: Phase-0 ADR-0015 → **F4 = B** (no admissible golden target exists without new verification semantics — research blocker, `docs/adr/0015-phase0-decision-gate-evidence-boundary.md:83-102`)
**Deliverable**: this scoping document only. It authorizes a *research workstream envelope*; every experiment inside that envelope requires its own research-branch approval. Nothing in this document creates a product-path obligation, proof, or evidence claim.
**Related**: DEBT#416 (`data/debt_registry.json:2438`), `docs/spec/obligation_semantics.md` (normative SSOT), ADR-0014 (`docs/adr/0014-canonical-verification-obligation-ir.md`), `docs/design/r4_promotion_eligibility_aggregate.md` (R4 — sealed), `docs/design/r7_cli_outcome_contract.md` (R7 — sealed).

---

## 1. The R8 Problem (as verified at HEAD `2e31b2587`)

R8 ("Productization Blocking Surface", CRITICAL in `data/readiness/independent_policy.json` → `invariants.R8`) is blocked not by persistence engineering but by a **verification-semantics research gap**: the pipeline cannot produce a single genuine verification obligation, so no certificate can ever become `certGreen`, and the canonical vault has no admissible certificate.

Ground truth (all numbers read from the canonical measurement SSOT, `data/baseline.json`):

- `metrics.vkd = { verified: 0, total: 23, ratio: 0.0 }` — i.e. **VKD = 0/23** (`data/baseline.json:29-33`).
- Kernel scope: `kernelTotal = 40`, `kernelExemptTotal = 17`, `vksTotal = 23`, `kernelVerified = 0` (`data/baseline.json:24-27`).
- **All 35 non-exempt kernel targets** report `psNoObligation` with provenance `solverMethod=smNone,provenance=pkNone,ObliSemanticNoApplicable`; the full-symbol IR pipeline pass summary is **Pass 0 / Skip 35** (ADR-0015 F4; DEBT#416 note). The probe log corroborates the classification at the symbol level (`tmp/col_probe_a.err:20-36`, summary blocks `:37-44,67-74`).
- Root cause is tracked as **DEBT#416** (`data/debt_registry.json:2438`, `resolution: "UNRESOLVED"`): the CHC/Spacer path (`[loop-chc-vm]`) declares **all** kernel symbols `not-applicable:cnaNoObligations` — the P1.2 fix (2026-08-11) restored obligation *propagation* (35→ Pass 17 / Fail 2 / Skip 16 in one probe), but the **numerator did not move**: `passes` are either absent obligations or non-kernel symbols; VKD numerator stays 0/23 per policy (only genuine kernel passes count, DEBT#416 note).

The admission predicate makes the consequence formal: `isVkdAdmissible` requires `isDeepVerified == dvcSuccess` **and** `admissibleEvidence(bundle)` **and** `status == certGreen` (`src/core/proof/proof_integrity.nim:154-182`). `admissibleEvidence` = `solverProved ∧ translationProved` (dual evidence, `src/core/trusted/evidence_calculus.nim:110-116`). With zero obligations, `solverProved = false` and `translationProved = false` for every non-exempt kernel target, hence **no target is admissible**.

**Per ADR-0015 F4 = B (`:83-102`)**: "Closing R8 requires fixing CHC/obligation generation semantics to produce real obligations for at least one admissible kernel target, which is a research effort separate from the evidence-boundary redesign." Consequence (`:143-145`): **R8 must NOT proceed as persistence engineering**; re-approval is required after the obligation-generation research blocker is resolved. This charter is the scoping of that research effort.

---

## 2. Strict Isolation (the key requirement)

R8 runs as a **separate parallel research workstream, sealed off from the C1–C3 evidence/policy/identity layer**. It is deliberately a research track, not an integration: nothing an R8 researcher produces may perturb the evidence on which R4/R7 closure is currently being designed.

### 2.1 Sealed layer (R8 MUST NOT write, change, or re-run)

| Artifact | Role |
|---|---|
| `data/readiness/evidence_manifest.json` | independent evaluator's canonical observable manifest |
| `data/readiness/independent_policy.json` | pre-ratified independent policy (R1–R8 criteria) |
| `data/readiness/evaluate.py` | independent evaluator (only an external invocation computes R1–R8) |
| `data/readiness/snapshots/`, `data/readiness/decision.*.json`, `data/readiness/readiness_history.json` | point-in-time evidence snapshots and verdicts |
| `src/verification/cert_promotion.nim`, `src/verification/certificate_manager.nim`, `src/verification/certificate_eligibility.nim`, `certificate_identity.nim`, `cert_writer.nim` | certificate / promotion aggregates (R4 layer) |
| `docs/design/r4_promotion_eligibility_aggregate.md`, `docs/design/r7_cli_outcome_contract.md`, `docs/adr/*` (0015, 0016…) | contemporaneous R4/R7 closure designs |
| `data/baseline.json` | measurement SSOT — VKD = 0/23 remains the report of record until the evaluator re-runs |
| `config/readiness_policy.json`, `tools/readiness_evaluator.nim` | repo self-assessment machinery |
| `.github/workflows/ci.yml`, `AGENTS.md` | immutable harness/SSOT (AGENTS.md §-1) |

Rationale: obligation generation / proof artifacts are a **different evidence domain** from identity/promotion/CLI-surface evidence. If R8 experiments perturb `evidence_manifest.json` or promotion aggregate state mid-flight, the R4/R7 evidence baseline becomes unstable and the whole Phase-0 decision rests on moving sand — the exact failure mode ADR-0015 F4=B guards against.

### 2.2 When does an R8 result touch the product path?

Only one trigger: **an R8 research result is deliberately adopted** (code + spec change proposal to the verification layer, with an architect decision). At that point a **NEW evidence snapshot begins**: fresh independent evaluator run on a clean manifest — the evaluator is the sole GO/NO-GO arbiter (ADR-0015 locked decision 3, independent-evaluator boundary). R8 never writes into the current, already-collected evidence.

### 2.3 Operational structure

```
R8 research branch (e.g. refs/heads/r8-obligation-research)
   │  └── scratch experiments (tmp/r8-*/), generated SMTLIB/CHC corpus, probe scripts
   ▼
research artifacts (docs/history/ + docs/evidence/ findings; DEBT-registry-tracked)
   │
   ▼
separate findings documents consumed by architect review — NOT by the R4/R7 closure path
```

---

## 3. Research Questions (grounded in ADR-0015 F4 + the obligation/CHC code)

Obligation semantics live in four places (canonical mapping):

| Stage | Location | Declines here | Zero-obligation classification |
|---|---|---|---|
| P3 generation | `src/verification/obligation/canonical_obligation_generator.nim` + `semantic_target_extractor.nim` | – | `ogrNoApplicableObligation` with `derivationRule = "obs:noObligations"` (`canonical_obligation_generator.nim:190-213`) |
| P3 wiring | `src/verification/batch_uap/ir_pipeline_runner.nim:418-489` | early-return `vsNoObligation` (`:428-447`) | `prov = "…,ObliSemanticNoApplicable"` (`:1230`) |
| CHC encoding | `src/core/trusted/private/canonical_chc_compiler.nim` (~`:289`), `src/core/trusted/private/ir_loop_to_horn.nim:279-297,437` | `cbNotApplicable(cnaNoObligations)` | vacuity skip — anti-theater, NOT capability (`proof_integrity.nim:47-62`) |
| CHC/Spacer attempt | `ir_pipeline_runner.nim` `[loop-chc-vm]` (`:542-707`) | `bpRequire` fail-closed (`:591-612,644-676`) | `cnaNoObligations` → `makeNoObligation` (`:654-658`) |

The core research questions (Q1–Q4):

Q1. **Why do zero obligations, in two layers?** For the 35 kernel symbols is the failure generator-level (0 candidates from `extractObligationCandidates`, `semantic_target_extractor.nim:129-244` — no `boDiv/boRem`, no `irCall("[]")`, no `irLoop` collected, no pre/post after `synthesizeContracts` at `ir_pipeline_runner.nim:410-416`) or CHC-admission-level (`buildChcFromLoop` → `cbNotApplicable(cnaNoObligations)`) — quantify per symbol. This is the *obligation-generation semantics* problem, the true F4 block.

Q2. **Is the semantic-target extractor complete enough for the 35?** — `collectLoops` only walks `irLoop` nodes (`semantic_target_extractor.nim:86-123`); do kernel loops actually lower to `irLoop`, or does the front-end emit back-jumps that CHC never sees? Do auto-synthesized postconditions materialize for these symbols at all (log shows "invariant does not imply postcondition" warnings for non-kernel symbols, `tmp/col_probe_a.err:9,13,15` — the same synthesis must be demonstrated for kernel targets)?

Q3. **SMTLib-encoding vs CHC-format vs genuine undecidability/performance?** — for the two symbols that DO build CHC successfully (`firstBoolCore`, `firstIntCore`): is their SMTLib2 text rejected by Z3 (parsing/encoding), is the CHC format valid but Spacer returns unknown/timeout, and is either case a modeling gap (QF_AUFBV arrays for `seq[T]`) rather than genuine hardness? (P1.2-errata: both build `cbSuccess` — the 2 `psFail` are honest Spacer nondischarge under `bpRequire`'s fail-closed verdict path, `ir_pipeline_runner.nim:591-612`, NOT encodability.)

Q4. **SPACER vs Z3 engine / strategy matrix** — the pipeline makes one canonical-CHC invocation per loop (`runZ3CheckViaIR`, `phase = spBmc`, fixed budget `getBudgetFor(spBmc).timeoutMs`) then fails closed under `bpRequire`. Research the space: SPACER engine alternatives (fixed-point vs BMC-bound, `fp.xform.inline_eager`, `spacer.q3`, `(set-logic QF_AUFBV)` ordering), and the loop-transition (VerificationModel) encoding of `lowerLoopToTransition` (CHC bridge) — i.e. whether the CHC *format* at the solver is the decline point, or the solver's *strategy*.

Q5. **Does `expectedObligation` ever get respected?** — the pipeline calls `generateCanonicalObligations(funcDef, defaultScopePolicy())` (`ir_pipeline_runner.nim:425`), whose `expectedObligation = false` (`canonical_obligation_generator.nim:44-46`); `proof_integrity.classifyNoObligation` (`proof_integrity.nim:47-62`) defines the `noObligationScopeMismatch` contract for `expectedObligation: true`, but the pipeline never sets it. Research: for a proof-mode kernel symbol, should the generator be fed the kernel scope's obligation expectation so that "zero obligations" is classified as a contract violation (`ObligationScopeMismatch`), not a legitimate no-op — and how does that interact with anti-theater (§0.9)?

---

## 4. Success Criteria (research outcome)

The R8 sequence has exactly one measurable tick:

**Primary signature (all three must hold for at least one non-exempt kernel target):**

1. **Real obligation generated**: `ObligationGenerationResult.kind == ogrGenerated` with ≥1 obligation whose `derivationRule` is a true semantic rule (`obs:division` / `obs:index` / `obs:loopBound` / `obs:loopVariant` / `obs:contract`) — not a fabricated/composite placeholder (anti-theater C0/C3).
2. **Real discharge evidence**: the obligation is discharged by a sound solver path and the Lean translation builds (genuine `solverProved ∧ translationProved` — `admissibleEvidence`, `evidence_calculus.nim:110-116`), i.e. the certificate reaches `certGreen`.
3. **Admission**: `isVkdAdmissible` returns `Admit` for that target (`proof_integrity.nim:154-182`), so **VKD > 0** (new evaluator snapshot — `data/baseline.json` is refreshed only via the independent evaluator).

**Secondary gate**: the per-layer diagnosis (Q1) has a written answer — symbol-by-symbol count of "generator-level zero" vs "CHC-admission zero" vs "solver-level inconclusive" — because that is the evidence the architect needs to judge whether the fix belongs in the extractor, the generator feed, the CHC writer, the solver strategy, or the scope policy.

**Boundary (per C0 B1: promotion ≠ proof status):** reaching this signature is a **research result only**. It does NOT by itself change R4 (the promotion aggregate gate is unchanged; a `certGreen` may not be promoted until the R4 closure re-approves), and it does NOT unblock R7 (the CLI contract is independent, C0 B1/C1). VKD > 0 in a new snapshot is a *readiness* milestone, not a license to skip the R4/R7 gates.

---

## 5. Non-Goals / Boundaries

- **Not woven into R4/R7**: R8 does not modify, consume, or react on the identity/promotion/CLI surfaces. It produces research artifacts only; integration requires a new approval cycle.
- **Not persistence work**: staging→reload→reverify, manifest write, vault promotion are explicitly deferred (and are themselves blocked by F4=B). R8 has zero persistence deliverables.
- **No fabricated obligations**: obligations must be derived from real IR semantic facts (spec §3 rules). Forcing an `ogrGenerated` via synthetic post-conditions, tautologies (prohibited C3), or `expectedObligation` gaming to tick the signature is **theater** (AGENTS.md §0.9) and fails the task — it would appear as a vacuous pass and would be rejected by the evaluator's re-run.
- **No side-effect on measurements**: OGR/PAR/VKD in `data/baseline.json` (vkd = 0/23, ogr ≈ 0.19, par = 1.0) must **not** be touched by this research; only a fresh evaluator snapshot updates them.
- **Not a faster engineering ticket**: Q1/Q3 must be answered (diagnosis) before any remedy; a "mechanical patch" is explicitly forbidden (`DEBT#416` errata).

---

## 6. Research carve-out / isolation boundary (summary)

| R8 MAY touch | R8 MUST NOT touch |
|---|---|
| `docs/design/r8_research_charter.md`, `docs/history/`, `docs/evidence/` (findings, one-direction: research → findings) | `data/readiness/**` (`evidence_manifest.json`, `independent_policy.json`, `evaluate.py`, `snapshots/`, `decision.*.json`, `readiness_history.json`) |
| A dedicated research branch (`r8-…`); scratch under `tmp/` (`tmp/r8-*/` — SMT scripts, CHC dumps, probe logs) | `src/verification/cert_promotion.nim`, `certificate_manager.nim`, `certificate_eligibility.nim`, `certificate_identity.nim`, `cert_writer.nim` (promotion/identity aggregates) |
| `src/verification/obligation/**` (generator/extractor/IR) — **analysis & experiments only, in the research branch** | `config/readiness_policy.json`, `tools/readiness_evaluator.nim` |
| `src/core/trusted/private/canonical_chc_compiler.nim` + `ir_loop_to_horn.nim` — analysis and regression probes only (branch) | `data/baseline.json` — VKD = 0/23 stays until evaluator re-runs |
| `src/verification/batch_uap/ir_pipeline_runner.nim` P3 / `[loop-chc-vm]` — analysis, experiment harness in branch | R4 / R7 design docs and their consecutive ADR-0015/0016 decisions |
| Independent invocations (read-only) of Z3/Spacer on exported CHC `.smt`/`.smtlib` bodies to test format/strategy | No modification of the evaluator invocation path or its expectations |
| New unit tests for a *research prototype* in the branch (not added to the product test suite) | The evaluator's rerun is only ever triggered by productized result, never by the research |

Entry rule for production: **a product-path change requires a separate approved step** (architecture review + a NEW evidence snapshot + evaluator run). This charter is not that approval.

---

*Report: `docs/design/r8_research_charter.md` — R8 "Productization Blocking Surface" isolated research scope: an obligation-semantics research workstream sealed from R4/R7 evidence to raise VKD 0/23 by producing the first genuine admissible obligation.*