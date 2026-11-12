import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/axiom_pragmas

## verification_tier.nim — SSOT for 2-Stage Verification Pipeline tier classification.
## Phase 4A: Z3 + Lean Role Separation.
##
## Pipeline flow:
##   Nim func → Syntactic Guard → Axiom Core IR → [Z3 FFI] + [Lean 4]
##   - Z3 unsat  → certZ3Candidate (candidate evidence, never VERIFIED)
##   - Z3 unknown → fallback to Lean
##   - Z3 sat     → certRed (counterexample)
##   - Lean pass  → certLeanVerified
##   - Both pass  → certDualVerified
##
## This module is purely functional (no I/O, no exceptions).

import std/json
import core/types/vkd_types

type
  VerificationTier* = enum
    vtNone        ## Neither Z3 nor Lean verified (initial / failed state)
    vtZ3Only      ## Verified by Z3 SMT solver only (decidable fragment)
    vtLeanOnly    ## Verified by Lean 4 kernel only (higher-order structural)
    vtDual        ## Verified by both Z3 and Lean (highest confidence)
    vtKInduction  ## Verified by k-induction (temporal/unbounded)
    vtUfAbstract  ## Verified by uninterpreted function abstraction

func tierFromResults*(z3Success: bool; leanSuccess: bool; kInduction: bool = false; ufAbstract: bool = false): VerificationTier =
  ## Pure mapping from solver results to verification tier.
  ## Exhaustive truth table — no gaps, no defaults needed.
  if kInduction:                    vtKInduction
  elif ufAbstract:                  vtUfAbstract
  elif z3Success and leanSuccess:   vtDual
  elif z3Success:                   vtZ3Only
  elif leanSuccess:                 vtLeanOnly
  else:                             vtNone

func isValidTier*(t: VerificationTier): bool =
  ## Always true for enum, but useful for runtime validation of external input.
  t in {vtNone, vtZ3Only, vtLeanOnly, vtDual, vtKInduction, vtUfAbstract}

func canTransitionTo*(current: VerificationTier; target: VerificationTier): bool =
  ## Defines allowed tier transitions.
  ## E.g., can upgrade vtZ3Only → vtDual, but not downgrade vtDual → vtZ3Only without re-verification.
  case current
  of vtNone:     target in {vtZ3Only, vtLeanOnly}
  of vtZ3Only:   target == vtDual
  of vtLeanOnly: target == vtDual
  of vtDual:     target == vtKInduction
  of vtKInduction: target == vtUfAbstract
  of vtUfAbstract: false

func tierFromRatio*(ratio: VerifiedKernelRatio): VerificationTier =
  ## Maps a verified kernel ratio to a verification tier.
  let r = ratio.toFloat
  if r >= 0.9:    vtDual
  elif r >= 0.5:  vtZ3Only
  else:           vtNone

func tierLabel*(t: VerificationTier): string =
  ## Human-readable label for each tier.
  case t
  of vtNone:        "none"
  of vtZ3Only:      "z3-verified"
  of vtLeanOnly:    "lean-verified"
  of vtDual:        "dual-verified"
  of vtKInduction:  "k-induction"
  of vtUfAbstract:  "uf-abstract"

func `$`*(t: VerificationTier): string =
  ## String conversion delegates to tierLabel for consistency.
  tierLabel(t)

func isValid*(t: VerificationTier): bool =
  ## True for any tier except vtNone (i.e., at least one solver passed).
  t != vtNone

func requiresFallback*(t: VerificationTier): bool =
  ## True when Z3 passed but Lean has not yet been attempted.
  ## Pipeline should fallback to Lean for structural invariants.
  t == vtZ3Only

## ─── P0: Evidence-Derived Status (certGreen status-aliasing elimination) ─────
## DECISION-0630 — CANONICAL EVIDENCE CONTRACT (single semantic authority).
## Every terminal verdict consumer (ax verify closure
## `certificate_verifier.verifyCertificateClosure`, VKD admission
## `proof_integrity.isVkdAdmissible`, hydrate projection
## `proof_state_builder`, and the writer self-demotion in `cert_writer`)
## MUST interpret certificate trust through THIS module's reader predicate
## (`certificateEvidenceFromJson` + `statusConsistentWithEvidence` below):
##
##   z3Passed     := solverStatus == "unsat" (or smtlib2+z3outPath artifacts)
##   leanVerified := solverMeta.leanCompilerVerified ∧ kernel
##   certRed         — SAT/counterexample ONLY (unsat is never a red fact)
##   certZ3Candidate — unsat candidate evidence (never verified, never red)
##   status          — may never exceed what stored evidence supports
##                     (certGreen ⟹ dual; certZ3Candidate ⟹ z3Passed;
##                      certLeanVerified ⟹ leanVerified)
##
## Re-interpretations of this truth table elsewhere (e.g. mapping unsat
## candidates to counterexamples, or flags to verified) are semantic
## authority splits and must be projected through this contract instead.
##
## P0 invariant: a certificate's `status` string is DERIVED from its stored
## evidence, never a hardcoded label. In particular `certGreen` must never be
## emitted (or accepted) without dual (Z3 ∧ Lean) evidence. These helpers are
## the single source of truth for that derivation. Status strings are trusted
## only insofar as they are consistent with evidence (docs/spec/verification_density.md).

type CertificateEvidence* = object
  z3Passed*: bool      ## Z3 returned `unsat` on the negated obligation
  leanVerified*: bool  ## Lean kernel accepted the generated theorem/source

func certificateEvidenceFromJson*(node: JsonNode): CertificateEvidence {.raises: [].} =
  ## Extract `(z3Passed, leanVerified)` from a certificate JSON node.
  ## Mirrors verified_set_hydration z3Unsat logic (smtlib2 + z3outPath),
  ## extended with the explicit `solverStatus == "unsat"` signal written by the
  ## IR pipeline path (axiom_engine). Fail-closed: any missing/ambiguous signal
  ## yields false, never true (§0.9).
  result = CertificateEvidence(z3Passed: false, leanVerified: false)
  if node.isNil or node.kind != JObject:
    return
  let solverMeta = node.getOrDefault("solverMeta")
  if solverMeta != nil and solverMeta.kind == JObject:
    let kernelAccepted = node.getOrDefault("kernel").getBool(false)
    result.leanVerified = solverMeta.getOrDefault("leanCompilerVerified").getBool(false) and kernelAccepted
  let solverStatus = node.getOrDefault("solverStatus").getStr("")
  let smtlib2 = node.getOrDefault("smtlib2").getStr("")
  let z3outPath = node.getOrDefault("z3outPath").getStr("")
  if solverStatus == "unsat":
    result.z3Passed = true
  elif smtlib2.len > 0 and z3outPath.len > 0:
    result.z3Passed = true

func tierFromEvidence*(ev: CertificateEvidence): VerificationTier {.raises: [].} =
  ## Canonical: tier is a PURE function of evidence, never of a status string.
  tierFromResults(ev.z3Passed, ev.leanVerified)

func statusConsistentWithEvidence*(node: JsonNode): bool {.raises: [], axiomDecision(id = "DECISION-0630", reason = "P0 invariant gate: status must not exceed what stored evidence supports", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## P0 invariant gate. Returns true only when the certificate's declared
  ## `status` is NO stronger than what its stored evidence supports:
  ##   certGreen          ⟹ z3Passed ∧ leanVerified   (dual)
  ##   certZ3Candidate    ⟹ z3Passed
  ##   certZ3Verified     ⟹ z3Passed   (legacy spelling of certZ3Candidate —
  ##                       same migration rule as test_evidence_truth_boundary)
  ##   certLeanVerified   ⟹ leanVerified
  ## Any other status is out of scope → true (this is a lower-bound check).
  ## Callers use this to reject writes and demote/reject reads (§0.9).
  if node.isNil or node.kind != JObject:
    return false
  let status = node.getOrDefault("status").getStr("")
  if status == "certGreen":
    let ev = certificateEvidenceFromJson(node)
    return ev.z3Passed and ev.leanVerified
  elif status == "certZ3Candidate" or status == "certZ3Verified":
    return certificateEvidenceFromJson(node).z3Passed
  elif status == "certLeanVerified":
    return certificateEvidenceFromJson(node).leanVerified
  true

{.pop.}
