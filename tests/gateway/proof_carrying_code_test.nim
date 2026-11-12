{.push raises: [CatchableError].}

## Proof-Carrying Code — Phase 12: Integration Test
## See tests/gateway/proof_carrying_code.feature for the specification.
##
## Validates the proof-carrying code pipeline: artifact construction,
## verification, DFA parsing, and Z3 proof validation.
## All tests exercise pure functions — no I/O, no process execution.

import std/[unittest, strutils]
import ../../src/infrastructure/gate_signing/proof_artifact_types
import ../../src/infrastructure/gate_signing/proof_verifier
import ../../src/infrastructure/gate_signing/smtlib2_parser
import ../../src/infrastructure/gate_signing/z3_proof_to_lean
import ../../src/core/solver/smt2_lexer

# ─── Test constants and helpers (outside suite for Nim macro expansion) ──

const
  ValidTreeSha = "aabbccddee1122334455aabbccddee1122334455"
  ValidLeanHash = "aabbccddee1122334455aabbccddee1122334455aabbccddee1122334455aabb"
  SimpleZ3Proof = "(true-intro 0)"
  BadHash = "0000000000000000000000000000000000000000000000000000000000000000"

proc makeValidArtifact(treeSha: string = ValidTreeSha,
                       z3Proof: string = SimpleZ3Proof): ProofArtifact =
  ## Construct a fully valid proof artifact that passes all 8 verification steps.
  let toolchain = localToolchainHash()
  let ph = computeProofHash(treeSha, z3Proof, ValidLeanHash, toolchain)
  ProofArtifact(
    treeSha: treeSha,
    z3Proof: z3Proof,
    leanOleanHash: ValidLeanHash,
    toolchainHash: toolchain,
    timestamp: 1700000000,
    proofHash: ph
  )

{.push warning[BareExcept]:off.}
suite "proof-carrying code pipeline — integration":

  # ─── verifyProof pipeline ─────────────────────────────────────────

  test "valid proof artifact passes full verification pipeline":
    ## End-to-end: a correctly constructed artifact with matching treeSha
    ## must pass all 8 verification steps and return vrValid.
    let artifact = makeValidArtifact()
    check verifyProof(artifact, ValidTreeSha) == vrValid

  test "tampered treeSha fails Merkle binding check":
    ## Merkle binding (step g) must reject when expectedTreeSha differs
    ## from the artifact's treeSha, preventing proof substitution attacks.
    let artifact = makeValidArtifact()
    let differentTreeSha = "1122334455667788990011223344556677889900"
    check verifyProof(artifact, differentTreeSha) == vrInvalidMerkle

  test "oversized Z3 proof rejected before parsing":
    ## Size gate (step a) must reject proofs exceeding MaxZ3ProofSize
    ## before any parsing or hash computation occurs.
    let oversizedProof = repeat('x', MaxZ3ProofSize + 1)
    let artifact = makeValidArtifact(ValidTreeSha, oversizedProof)
    check verifyProof(artifact, ValidTreeSha) == vrInputTooLarge

  test "malformed SMT-LIB2 proof rejected by DFA parser":
    ## Format gate (step b) must reject input that the DFA tokenizer
    ## cannot parse — unclosed parenthesis is a common corruption signal.
    let artifact = makeValidArtifact(ValidTreeSha, "(unclosed")
    check verifyProof(artifact, ValidTreeSha) == vrMalformedInput

  test "toolchain hash mismatch rejects proof":
    ## Toolchain gate (step c) must reject proofs built with a different
    ## Z3/Lean version, preventing replay of stale proof objects.
    let artifact = ProofArtifact(
      treeSha: ValidTreeSha,
      z3Proof: SimpleZ3Proof,
      leanOleanHash: ValidLeanHash,
      toolchainHash: BadHash,  # does not match localToolchainHash()
      timestamp: 1700000000,
      proofHash: BadHash
    )
    check verifyProof(artifact, ValidTreeSha) == vrInvalidToolchain

  # ─── DFA parser (smtlib2_parser) ─────────────────────────────────

  test "DFA parser accepts valid SMT-LIB2 input":
    ## The DFA tokenizer must correctly handle balanced parentheses,
    ## symbols, and numerals in standard SMT-LIB2 format.
    let result = parseSmtLib2("(assert-ref 0)")
    check result.success
    check result.tokens.len > 0

  test "DFA parser rejects regex-like syntax":
    ## Square brackets are not valid in SMT-LIB2 — the DFA must reject
    ## regex patterns like [a-z] at the unexpected character gate.
    let result = parseSmtLib2("[a-z]")
    check not result.success

  # ─── Z3 proof validation ─────────────────────────────────────────

  test "Z3 proof 3-step roundtrip validates correctly":
    ## A 3-step proof (two assertions + modus ponens) must tokenize,
    ## parse into Z3ProofObject, and pass structural validation.
    ## Tests the full pure-function pipeline through the public API.
    let smt2Text = "(assert-ref 0)\n(assert-ref 1)\n(modus-ponens 2 0 1)"
    let tokens = tokenizeSmt2(smt2Text)
    let proofObj = parseZ3Proof(tokens)
    check validateZ3Proof(proofObj)
    check proofStepCount(proofObj) == 3

  test "self-referencing proof step rejected by DAG validation":
    ## A proof step whose premise references itself violates the strict
    ## reverse-topological ordering required by the DAG invariant.
    ## validateZ3Proof must detect and reject this structural defect.
    let selfRefProof = Z3ProofObject(
      steps: @[
        Z3ProofStep(
          rule: prkAssertRef,
          conclusion: Literal(polarity: true, atomId: 0),
          premises: @[0],  # self-reference — violates DAG ordering
          args: @[]
        )
      ],
      rootIndex: 0
    )
    check not validateZ3Proof(selfRefProof)

{.pop.}
