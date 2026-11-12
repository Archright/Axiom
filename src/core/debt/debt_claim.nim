## src/core/debt/debt_claim.nim — Claim creation + Quirk 3-way classification.
##
## Public API:
##   - newClaim*(kind, candidateId, text: string; evidence: seq[string]): Claim
##   - assessQuirk*(obs: DebtObservation; reproduction, toolchainVersion, upstreamRefs, localTestRefs: seq[string]): QuirkClaim
##   - QuirkAssessment* = QuirkClaim  (type alias)
##
## Ownership rules (evidence-first, no heuristics):
##   1. upstreamRefs non-empty AND localTestRefs non-empty → qoUpstreamConfirmed, confidence 1.0
##   2. upstreamRefs empty AND localTestRefs non-empty → qoProjectLocal
##   3. localTestRefs empty (no reproduction) → qoUnverifiedHistorical

import core/trusted/layer_declaration
axiomLayer "domain"

import core/types/debt_types
import core/crypto/hash_kernel
import std/strutils

{.push raises: [].}

# QuirkAssessment is a type alias for QuirkClaim — the task spec uses
# "QuirkAssessment" as the return type name but the actual data structure
# is QuirkClaim (already defined in debt_types.nim).
type
  QuirkAssessment* = QuirkClaim

func newClaim*(kind: ClaimKind; candidateId, text: string; evidence: seq[string]): Claim =
  ## Create a new Claim ref with a deterministic claimId.
  ## claimId is SHA-256 of the concatenated inputs, prefixed with "sha256:".
  let raw = $kind & "\x1e" & candidateId & "\x1e" & text & "\x1e" & evidence.join("\x1e")
  Claim(
    claimId: "sha256:" & computeContentHash(raw),
    kind: kind,
    candidateId: candidateId,
    text: text,
    evidenceIds: evidence
  )

func assessQuirk*(obs: DebtObservation; reproduction, toolchainVersion, upstreamRefs, localTestRefs: seq[string]): QuirkClaim =
  ## Determine QuirkOwnership from evidence.
  ##
  ## Ownership rules (3-way, evidence-first, no heuristics):
  ##   1. upstreamRefs non-empty AND localTestRefs non-empty →
  ##      qoUpstreamConfirmed, confidence 1.0
  ##   2. upstreamRefs empty AND localTestRefs non-empty →
  ##      qoProjectLocal
  ##   3. localTestRefs empty (no reproduction possible) →
  ##      qoUnverifiedHistorical
  ##
  ## Anti-heuristic: no "category contains quirk" or similar
  ## keyword-based classification is used. Ownership is determined
  ## solely by the presence/absence of upstream references and
  ## local reproduction evidence.
  let hasUpstream = upstreamRefs.len > 0
  let hasLocal = localTestRefs.len > 0

  var ownership: QuirkOwnership
  var confidence: float

  if hasUpstream and hasLocal:
    ownership = qoUpstreamConfirmed
    confidence = 1.0
  elif not hasUpstream and hasLocal:
    ownership = qoProjectLocal
    confidence = 0.8
  else:
    ownership = qoUnverifiedHistorical
    confidence = 0.0

  QuirkClaim(
    claim: newClaim(ckQuirkClaim, obs.subject & "\x1e" & obs.semanticIdentity, obs.payload, @[obs.observationId]),
    ownership: ownership,
    confidence: confidence,
    reproduction: reproduction.join("\n"),
    toolchainVersion: toolchainVersion.join(" "),
    upstreamRefs: upstreamRefs,
    localTestRefs: localTestRefs
  )

{.pop.}
