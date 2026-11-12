## Proof-Carrying Code — IPC Contract (Phase 0)
## Shared type definitions for gate signing IPC protocol.
## This file is the interface contract between all gate signing components.
## Changes here require coordinated updates across all dependent phases.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[strutils, json]

const
  MaxZ3ProofSize* = 10_000_000      ## 10MB — Z3 proof object max size
  MaxIpcMessageSize* = 15_000_000   ## 15MB — total IPC message max size
  MaxSmtNestingDepth* = 100         ## Maximum parenthesis nesting depth
  MaxTokenSize* = 1_000_000         ## 1MB — single token max size
  CommitShaLen* = 40                ## Git commit SHA hex length
  HashLen* = 64                     ## SHA-256 hex digest length

type
  ProofArtifact* = object
    ## Serializable proof artifact exchanged between L1 (sandbox) and L2 (daemon).
    treeSha*: string          ## Git tree SHA (40 hex chars) — Merkle binding
    z3Proof*: string          ## Z3 proof object (SMT-LIB2 format, ≤10MB)
    leanOleanHash*: string    ## .olean file SHA-256 (64 hex chars)
    toolchainHash*: string    ## musl binary SHA-256 (64 hex chars) — determinism pinning
    timestamp*: int64         ## Unix timestamp of proof generation
    proofHash*: string        ## SHA-256(treeSha + z3Proof + leanOleanHash + toolchainHash)

  VerificationResult* = enum
    ## Result of proof verification by Lean kernel.
    vrValid = "valid"
    vrInvalidLeanKernel = "lean_kernel_rejected"
    vrInvalidZ3Proof = "z3_proof_rejected"
    vrInvalidMerkle = "merkle_mismatch"
    vrInvalidToolchain = "toolchain_mismatch"
    vrInputTooLarge = "input_too_large"
    vrMalformedInput = "malformed_input"

  SignRequest* = object
    ## IPC request: agent sends only commitSha. No gateResults (zero-trust).
    action*: string           ## Must be "sign"
    commitSha*: string        ## 40 hex chars

  SignResponse* = object
    ## IPC response: signed commit or denial reason.
    status*: string           ## "signed" | "denied"
    commitSha*: string        ## Echo back the requested commit SHA
    reason*: string           ## Human-readable denial reason (empty if signed)
    proofHash*: string        ## Proof artifact hash for audit trail

  HexCharset = set[char]

const HexDigits*: HexCharset = {'0'..'9', 'a'..'f'}

func isValidHex*(s: string, expectedLen: int): bool =
  ## Validate that `s` is exactly `expectedLen` lowercase hex chars.
  result = s.len == expectedLen and s.allCharsInSet(HexDigits)

func isValidCommitSha*(sha: string): bool =
  ## Validate commit SHA format (40 lowercase hex chars).
  result = isValidHex(sha, CommitShaLen)

func isValidHash*(h: string): bool =
  ## Validate SHA-256 hash format (64 lowercase hex chars).
  result = isValidHex(h, HashLen)

func isValidProofArtifact*(pa: ProofArtifact): bool =
  ## Validate all fields of a ProofArtifact without deserializing Z3 proof.
  result = isValidCommitSha(pa.treeSha) and
           pa.z3Proof.len <= MaxZ3ProofSize and
           isValidHash(pa.leanOleanHash) and
           isValidHash(pa.toolchainHash) and
           pa.timestamp > 0 and
           isValidHash(pa.proofHash)

func isValidSignRequest*(req: SignRequest): bool =
  ## Validate SignRequest fields.
  result = req.action == "sign" and isValidCommitSha(req.commitSha)

func toJson*(pa: ProofArtifact): JsonNode =
  ## Serialize ProofArtifact to JSON.
  result = %*{
    "treeSha": pa.treeSha,
    "z3Proof": pa.z3Proof,
    "leanOleanHash": pa.leanOleanHash,
    "toolchainHash": pa.toolchainHash,
    "timestamp": pa.timestamp,
    "proofHash": pa.proofHash
  }

func fromJson*(node: JsonNode, _: typedesc[ProofArtifact]): ProofArtifact {.raises: [CatchableError].} =
  ## Deserialize ProofArtifact from JSON. Raises on missing/invalid fields.
  try:
    result = ProofArtifact(
      treeSha: node["treeSha"].getStr(),
      z3Proof: node["z3Proof"].getStr(),
      leanOleanHash: node["leanOleanHash"].getStr(),
      toolchainHash: node["toolchainHash"].getStr(),
      timestamp: node["timestamp"].getInt(),
      proofHash: node["proofHash"].getStr()
    )
  except KeyError:
    raise newException(CatchableError, "ProofArtifact JSON missing required fields")

func toJson*(req: SignRequest): JsonNode =
  ## Serialize SignRequest to JSON.
  result = %*{"action": req.action, "commitSha": req.commitSha}

func fromJson*(node: JsonNode, _: typedesc[SignRequest]): SignRequest {.raises: [CatchableError].} =
  ## Deserialize SignRequest from JSON.
  try:
    result = SignRequest(
      action: node["action"].getStr(),
      commitSha: node["commitSha"].getStr()
    )
  except KeyError:
    raise newException(CatchableError, "SignRequest JSON missing required fields")

func toJson*(resp: SignResponse): JsonNode =
  ## Serialize SignResponse to JSON.
  result = %*{
    "status": resp.status,
    "commitSha": resp.commitSha,
    "reason": resp.reason,
    "proofHash": resp.proofHash
  }

func fromJson*(node: JsonNode, _: typedesc[SignResponse]): SignResponse {.raises: [CatchableError].} =
  ## Deserialize SignResponse from JSON.
  try:
    result = SignResponse(
      status: node["status"].getStr(),
      commitSha: node["commitSha"].getStr(),
      reason: node{"reason"}.getStr(""),
      proofHash: node{"proofHash"}.getStr("")
    )
  except KeyError:
    raise newException(CatchableError, "SignResponse JSON missing required fields")
