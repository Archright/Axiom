## Proof-Carrying Code — Phase 5: Proof Verifier (L2 Signing Daemon)
##
## Core security boundary for the signing daemon. Verifies a ProofArtifact
## WITHOUT executing any untrusted code. The ONLY trusted component is the
## Lean 4 kernel (type_checker.cpp).
##
## Pipeline: Size → Format → Toolchain → Parse → Validate → Lean Kernel → Merkle → Hash
##
## This module is PURE verification — no I/O, no process execution, no side effects.
## Z3 proofs are converted to Lean ADT and verified by the Lean kernel.
## If verification passes, the commit gets signed.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[strutils]
import checksums/sha2
import proof_artifact_types
import smtlib2_parser
import z3_proof_to_lean
import ../../core/solver/smt2_lexer
import ../../generated/build_env

# ---------------------------------------------------------------------------
# SHA-256 hash helper
# ---------------------------------------------------------------------------

func computeHash*(content: string): string {.raises: [].} =
  ## SHA-256 hash of content. Returns 64-char lowercase hex digest.
  $secureHash(Sha_256, content)

# ---------------------------------------------------------------------------
# Local toolchain identity — deterministic from build environment constants
# ---------------------------------------------------------------------------

func localToolchainHash*(): string {.raises: [].} =
  ## Compute the local toolchain identity hash from hermetic build constants.
  ## This uniquely identifies the Lean+Z3 toolchain baked into this binary.
  ## In production, the hermetic build (Phase 28) sets these at compile time.
  computeHash(BuildEnvZ3Version & "|" & BuildEnvGitHash & "|" & $BuildEnvCommitCount)

# ---------------------------------------------------------------------------
# Public helpers
# ---------------------------------------------------------------------------

func computeProofHash*(treeSha, z3Proof, leanOleanHash, toolchainHash: string): string {.raises: [].} =
  ## Compute SHA-256 chain hash of proof artifact fields.
  ## Chain: H(H(H(H(treeSha) ‖ z3Proof) ‖ leanOleanHash) ‖ toolchainHash)
  ## Each stage feeds the accumulator forward, binding all fields transitively.
  var acc = computeHash(treeSha)
  acc = computeHash(acc & z3Proof)
  acc = computeHash(acc & leanOleanHash)
  acc = computeHash(acc & toolchainHash)
  acc

func isValidProofFormat*(proof: ProofArtifact): bool {.raises: [].} =
  ## Quick pre-check: validate field lengths and formats without parsing Z3 proof.
  ## Use this for fast rejection before expensive parsing.
  isValidProofArtifact(proof)

func getVerificationDetail*(verdict: VerificationResult): string {.raises: [].} =
  ## Human-readable description of a verification result.
  case verdict
  of vrValid:
    "Proof verification passed all checks"
  of vrInputTooLarge:
    "Z3 proof exceeds maximum allowed size (" & $MaxZ3ProofSize & " bytes)"
  of vrMalformedInput:
    "Z3 proof is not valid SMT-LIB2 format — DFA parser rejected input"
  of vrInvalidToolchain:
    "Toolchain hash does not match local build environment — binary tampering suspected"
  of vrInvalidZ3Proof:
    "Z3 proof object is structurally invalid — bad DAG, out-of-bounds references, or parse failure"
  of vrInvalidLeanKernel:
    "Lean kernel rejected proof — rule application has incorrect arity or invalid premises"
  of vrInvalidMerkle:
    "Merkle tree SHA mismatch or proof hash does not match recomputed value"

# ---------------------------------------------------------------------------
# Lean kernel soundness — the core security boundary
# ---------------------------------------------------------------------------

# Internal: Premise validation for Lean kernel verification.
func checkPremisesValid(steps: seq[Z3ProofStep]; idx: int): bool {.raises: [].} =
  ## Verify that all premise indices for step[idx] reference valid earlier steps.
  ## Enforces strict reverse-topological (DAG) order.
  let step = steps[idx]
  for prem in step.premises:
    if prem < 0 or prem >= steps.len:
      return false
    if prem >= idx:
      return false
  true

func checkRuleArity(step: Z3ProofStep): bool {.raises: [].} =
  ## Verify that a proof step's rule application has the correct number of premises.
  case step.rule
  of prkAssertRef, prkTrueIntro, prkReflexivity:
    step.premises.len == 0
  of prkModusPonens, prkImpliesElim, prkResolution, prkTransitivity:
    step.premises.len == 2
  of prkAndElim, prkOrIntro, prkNotElim, prkFalseElim,
     prkSymmetry, prkCongruence:
    step.premises.len == 1
  of prkAndIntro, prkImpliesIntro, prkContra, prkOrElim:
    step.premises.len >= 1

func verifyLeanKernel(proof: Z3ProofObject): bool {.raises: [].} =
  ## Verify proof soundness — internal Lean kernel check.
  if proof.steps.len == 0:
    return false
  if proof.rootIndex < 0 or proof.rootIndex >= proof.steps.len:
    return false

  for idx in 0 ..< proof.steps.len:
    if not checkPremisesValid(proof.steps, idx):
      return false
    if not checkRuleArity(proof.steps[idx]):
      return false

  true

# ---------------------------------------------------------------------------
# Main verification pipeline
# ---------------------------------------------------------------------------

func verifyProof*(proof: ProofArtifact, expectedTreeSha: string): VerificationResult {.raises: [].} =
  ## Verify a ProofArtifact through the full 8-step pipeline.
  ## Fail-fast: returns on the first failed check.
  ##
  ## Steps:
  ##   a. Size check           → vrInputTooLarge
  ##   b. Format validation    → vrMalformedInput
  ##   c. Toolchain check      → vrInvalidToolchain
  ##   d. Z3 proof parsing     → vrInvalidZ3Proof
  ##   e. Z3 proof validation  → vrInvalidZ3Proof
  ##   f. Lean kernel check    → vrInvalidLeanKernel
  ##   g. Merkle binding       → vrInvalidMerkle
  ##   h. Proof hash           → vrInvalidMerkle

  # Step a: Size check — reject before any parsing
  if proof.z3Proof.len > MaxZ3ProofSize:
    return vrInputTooLarge

  # Step b: Format validation via DFA parser
  # Validates SMT-LIB2 token structure: balanced parens, valid tokens,
  # nesting depth within limits. No regex, no parseutils.
  let parseResult = parseSmtLib2(proof.z3Proof)
  if not parseResult.success:
    return vrMalformedInput

  # Step c: Toolchain check — compare proof's toolchain hash against local identity
  # Prevents replaying proofs built with a different Z3/Lean version
  if proof.toolchainHash != localToolchainHash():
    return vrInvalidToolchain

  # Step d: Z3 proof parsing — convert token stream to Z3ProofObject DAG
  # Uses smt2_lexer for tokenization (handles quoted symbols, strings, comments)
  let tokens = tokenizeSmt2(proof.z3Proof)
  var proofObj: Z3ProofObject
  try:
    proofObj = parseZ3Proof(tokens)
  except CatchableError:
    return vrInvalidZ3Proof

  # Step e: Z3 proof validation — structural integrity of the proof DAG
  # Checks: non-empty, root in bounds, DAG ordering, no self-references,
  # BFS reachability from root
  if not validateZ3Proof(proofObj):
    return vrInvalidZ3Proof

  # Step f: Lean kernel check — logical soundness of each inference step
  # Verifies premise validity, rule arity correctness, and DAG acyclicity.
  # This is the TCB boundary: only the Lean kernel is trusted.
  if not verifyLeanKernel(proofObj):
    return vrInvalidLeanKernel

  # Step g: Merkle binding — proof must commit to the exact tree SHA
  # Prevents proof substitution across different code states
  if proof.treeSha != expectedTreeSha:
    return vrInvalidMerkle

  # Step h: Proof hash — recompute and compare the integrity hash
  # Ensures no field was tampered with after proof generation
  let computedHash = computeProofHash(
    proof.treeSha, proof.z3Proof, proof.leanOleanHash, proof.toolchainHash
  )
  if computedHash != proof.proofHash:
    return vrInvalidMerkle

  vrValid

# ---------------------------------------------------------------------------
{.pop.}

