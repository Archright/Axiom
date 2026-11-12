# Phase 6 — T0 Replay Contract: Deterministic Reproduction

**Status**: Design
**Date**: 2026-08-14
**Applies to**: Axiom integrity engine — Phase 6 T0 replay
**Extends**: `docs/design/z3_replay_evidence_capture.md` (V2 capture anchors), `docs/design/phase3_evidence_claiming.md` (Claim model)

---

## 0. Invariant

Re-running the SAME canonical inputs + solver identity/options MUST yield the SAME outcome/evidence identity.

```
T0:  same(scriptDigest, solverIdentity, solverOptions, semanticProfileId, encodingIdentity, env)
   → same(SolverOutcome.status, SolverOutcome.statistics, evidenceIdentity)
```

Replay **never overwrites** a Claim's authority. It produces NEW evidence and COMPARES identities.
Replay does **NOT** imply kernel-checked proof (the proof object is T2 — optional).

---

## 1. The Replay Key — `SolverInvocation`

Solver options today are **ephemeral**: `buildZ3QueryEnvelope` (z3_pool.nim:607) prepends
`(set-option ...)` directives into the query string at invocation time; `z3ExecPersistent`
(z3_pool.nim:745) passes them as a transient `query` string. Neither the options nor the
solver identity are persisted alongside the evidence. This makes T0 replay impossible —
there is no anchor for "same solver configuration."

### 1.1 Persisted Type

```nim
SolverInvocation* = object {.axiomDecision(
  id = "DECISION-0XXX",
  reason = "Persisted replay key: canonical inputs + solver identity/options for T0 determinism",
  adr = "docs/spec/phase6_replay_contract.md",
  introduced = "v38").}
  scriptDigest*: string            # SHA256 of the certified SMT text (irToSmtScript output)
  solverIdentity*: string          # e.g. "z3" (DefaultSolverCommand, constants.nim:39)
  solverOptions*: string           # serialized SMT options hash: rlimit, random-seed, timeout, mode
  semanticProfileId*: string       # hash of the semantic contract governing this verification
  encodingIdentity*: string        # hash of the IR→SMT encoding version (translationVersion)
  env*: string                     # frozen build environment hash (BuildEnvGitHash, BuildEnvZ3Version)
```

**Field rationale**:

| Field | Source | Why it belongs in the replay key |
|-------|--------|----------------------------------|
| `scriptDigest` | `irToSmtScript` output (ir_to_smt_chunk3.nim:131) — SHA256 of the SMT text | The canonical input to the solver |
| `solverIdentity` | `DefaultSolverCommand` (z3_pool.nim:587) — `"z3"` | Different solvers (z3, cvc5) produce different results |
| `solverOptions` | Deterministic hash of `rlimit`, `random-seed`, `timeout`, `Z3ExecutionMode` (z3_pool.nim:619-637) | Options like `:random-seed 0` and `:rlimit` are part of the deterministic contract |
| `semanticProfileId` | `SemanticProfileID` from the verification profile | Different semantic contracts change the IR→SMT mapping |
| `encodingIdentity` | `translationVersion` (evidence_identity.nim:27) — `"axiom-ir-smt-v1"` | The IR→SMT encoding version is part of the canonical input |
| `env` | `BuildEnvZ3Version` + `BuildEnvGitHash` (from hermetic build, `tools/hermetic_build.nim`) | Z3 version and build environment affect solver behavior |

### 1.2 Why `solverOptions` Is a Hash, Not Raw Options

`buildZ3QueryEnvelope` (z3_pool.nim:607) injects options deterministically:
- `rlimit` from `z3DeterministicBudget` (z3_pool.nim:620)
- `random-seed 0` for Z3, sat, and fp.spacer (z3_pool.nim:632-637)
- `timeout` safety net (z3_pool.nim:626-628)
- `(reset)` prefix in `zmRaw` mode (z3_pool.nim:644)

These are **part of the solver invocation contract**. We hash the concatenation of all
injected options into `solverOptions` so that the replay key captures the full deterministic
configuration without storing the mutable query string.

---

## 2. Replay Input: The Certified SMT Script

### 2.1 `irToSmtScript` as the Replayed Input

`irToSmtScript` (ir_to_smt_chunk3.nim:131) generates a complete, self-contained SMT-LIB2
script from an `IRFuncDef`. The output is the **certified SMT text** — the exact input fed
to the solver. Its SHA256 digest is `scriptDigest` in `SolverInvocation`.

```nim
# Replay input construction:
let smtScript = irToSmtScript(loweredIRFunc, includeOverflowDefines = true)
let scriptDigest = sha256(smtScript)
```

The script includes: `(set-logic QF_BV)`, `(set-option :rlimit ...)`, overflow define-funs,
function declarations, pre/postcondition asserts, and `(check-sat)`. All of these are
deterministic for a given IRFuncDef + translationVersion + overflow configuration.

### 2.2 `CertificateIdentity` Anchors (Optional)

`CertificateIdentity` (evidence_identity.nim:14-30) carries two optional fields that serve
as evidence identity anchors for replay:

- `smtHash*` (line 26) — SHA256 of the SMT script; populated at cert write time
- `proofArtifactDigest*` (line 29) — SHA256 of the Z3 stdout output (proof terms when
  `enableProofs=true`); populated at cert write time

These are **optional** in the T0 contract: a replay may succeed even if neither field is
populated on the stored claim. When present, they provide cross-reference integrity — the
replayed evidence identity must match the stored `smtHash`/`proofArtifactDigest` if they
exist.

---

## 3. Replay Operation

### 3.1 Algorithm

```
replayClaim(claim: VerifiedClaim, invocation: SolverInvocation): ReplayResult
  1. Reconstruct smtScript from claim.irHash + claim.translationVersion
     (irToSmtScript on the canonical IR function)
  2. Compute scriptDigest = SHA256(smtScript)
  3. Assert scriptDigest == invocation.scriptDigest  (canonical input check)
  4. Build query = buildZ3QueryEnvelope(smtScript, timeoutMs, sentinel,
       enableProofs=false, mode=zmRaw)
     — NOTE: enableProofs=false for replay; proof artifact is T2 optional
  5. Run z3 via z3ExecPersistent(query, timeoutMs, ...)  (z3_pool.nim:745)
  6. Compute newOutcome: SolverOutcome from z3 stdout
  7. Compute newEvidenceIdentity:
       - newSmtHash = SHA256(smtScript)
       - newProofArtifactDigest = SHA256(z3stdout) if enableProofs else ""
       - Compare newSmtHash == claim.certificate.smtHash (if populated)
       - Compare newProofArtifactDigest == claim.certificate.proofArtifactDigest (if populated)
  8. Compute outcomeEquality = (newOutcome.status == claim.outcome)
  9. Return ReplayResult(outcomeEquality, newEvidenceIdentity, newOutcome)
```

### 3.2 Critical Constraint: No Mutation

The replay operation **MUST NOT** mutate the stored Claim. It reads the Claim's
`CertificateIdentity` and `EvidenceBundle` fields to compute comparison targets, then
returns a `ReplayResult` with the new evidence identity and outcome equality boolean.

```nim
type ReplayResult* = object
  outcomeEqual*: bool           # new SolverOutcome.status == stored outcome
  evidenceIdentityMatch*: bool  # new evidence identity == stored evidence identity
  newEvidence*: EvidenceBundle  # freshly computed evidence (never written to store)
  invocation*: SolverInvocation # the replay key used
```

### 3.3 Why `enableProofs=false` in Replay

The proof object (Z3 proof terms in stdout) is a **T2 artifact** — optional, kernel-checked
only if a separate kernel verification step is performed. Replay at T0 must not imply
kernel-checked status. Setting `enableProofs=false` keeps the replay path clean: the
replayed evidence is purely the solver's status decision (`unsat`/`sat`/`unknown`), which
is the T0-relevant outcome.

If `proofArtifactDigest` is populated on the stored claim (from a prior T2 kernel check),
the replay may optionally compute it for comparison purposes only — but the comparison
result is evidence, not authority.

---

## 4. Authority Boundary: Evidence ≠ Authority

### 4.1 Basis: `EvidenceBundle` + `Claim` Authority

`EvidenceBundle` (evidence_calculus.nim:72-74) contains `EvidenceFact` which carries
`SolverEvidence` (line 37-42) with `replayResult*` field (`"" | "ACCEPTED" | "REJECTED"`).
This field is the **only** place replay results are recorded. It is populated by the replay
operation, never by a cert writer or claim authority.

The `Claim` authority — the `outcome` field (`VerifiedClaim.outcome`, populated by the
Judge role per phase3_evidence_claiming.md §2.2) — is **never set by replay**. Replay
produces a `ReplayResult` that is compared against the stored outcome, but the comparison
result is evidence about determinism, not a new authority decision.

### 4.2 The Invariant in Type Terms

```
Claim.outcome     ∈ {PROVED, DISPROVED, UNKNOWN, UNSUPPORTED}  — set by Judge only
EvidenceBundle.facts.solver.replayResult ∈ {"", "ACCEPTED", "REJECTED"}  — set by replay only

replayClaim(claim, invocation):
  newOutcome = runZ3(invocation)
  outcomeEqual = (newOutcome.status == claim.outcome)  # comparison, not assignment
  evidenceBundle.facts.solver.replayResult =
    if outcomeEqual: "ACCEPTED" else: "REJECTED"
  return ReplayResult(..., newEvidence = evidenceBundle)  # NEW evidence, no mutation
```

### 4.3 What Replay Proves vs Does Not Prove

| Replay proves | Replay does NOT prove |
|---------------|----------------------|
| T0 determinism: same inputs → same outcome | Kernel correctness (T2) |
| Evidence identity stability: `smtHash`/`proofArtifactDigest` match | That the solver's answer is mathematically correct |
| That the Claim's stored evidence is reproducible | That the Claim's `outcome` should be changed |

---

## 5. T0 Boundary and P2 Separation

### 5.1 T0 Scope (this contract)

T0 covers: **same canonical inputs + solver identity/options → same outcome**.

The persisted `SolverInvocation` fields define the T0 replay key:
- `scriptDigest` — the SMT script (irToSmtScript output)
- `solverIdentity` — the solver binary identity
- `solverOptions` — deterministic hash of all solver configuration
- `semanticProfileId` — the semantic contract
- `encodingIdentity` — the IR→SMT encoding version
- `env` — the build environment (Z3 version, git hash)

### 5.2 P2 Boundary (outside T0)

P2 (proof object / kernel-check) is **outside** the T0 replay contract:

- `proofArtifactDigest` on `CertificateIdentity` (evidence_identity.nim:29) is optional
  and is only populated when a T2 kernel check has been performed
- The proof object itself (the S-expression proof term in Z3 stdout) is never replayed
  at T0 — replay uses `enableProofs=false`
- Kernel-checked proof verification is a separate operation that consumes the proof object
  and validates it against the solver's internal proof rules; it is not part of T0 replay

The boundary is explicit: T0 replay anchors on `scriptDigest` + `solverIdentity` +
`solverOptions` + `env`. Anything beyond these (proof objects, kernel checks, semantic
foundations) belongs to P2 and later phases.

---

## 6. Edit Points (Future Implementation)

| # | File | Line(s) | Change |
|---|------|---------|--------|
| 1 | `src/verification/solver/z3_pool.nim` | 607 | `buildZ3QueryEnvelope` — expose `solverOptions` hash for `SolverInvocation` construction |
| 2 | `src/verification/solver/z3_pool.nim` | 745 | `z3ExecPersistent` — add `SolverInvocation` parameter for replay mode |
| 3 | `src/core/trusted/private/ir_to_smt_chunk3.nim` | 131 | `irToSmtScript` — expose `scriptDigest` computation path |
| 4 | `src/core/trusted/private/evidence_identity.nim` | 26,29 | `CertificateIdentity.smtHash`/`proofArtifactDigest` — mark optional in replay context |
| 5 | `src/core/trusted/evidence_calculus.nim` | 42 | `SolverEvidence.replayResult` — already present; replay populates it |
| 6 | `src/core/trusted/evidence_calculus.nim` | 72-74 | `EvidenceBundle` — replay produces new bundle, never mutates stored one |
| 7 | `src/verification/solver_adapter.nim` | 28-33 | `SolverOutcome` — replay produces new outcome for comparison |
| 8 | New module | — | `SolverInvocation` type + `replayClaim` operation |

---

## 7. Summary

1. **T0 replay key** = `SolverInvocation(scriptDigest, solverIdentity, solverOptions, semanticProfileId, encodingIdentity, env)` — persisted alongside evidence.
2. **Replay input** = `irToSmtScript` output (ir_to_smt_chunk3.nim:131), hashed as `scriptDigest`.
3. **Replay operation** = run `z3` on persisted script+options → new `SolverOutcome` → compare outcome equality + evidence identity → return `ReplayResult` (NEW evidence, no mutation).
4. **Authority boundary** = replay never writes `Claim.outcome`; it only produces `EvidenceBundle` with `replayResult` for comparison. Based on `EvidenceBundle` (evidence_calculus.nim:72-74) + Claim authority separation.
5. **P2 boundary** = proof objects and kernel checks are outside T0; `proofArtifactDigest` is optional and only relevant for T2.