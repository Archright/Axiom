import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/json
import core/types/verification_tier
import core/trusted/evidence_calculus
import verification/certificate_identity

## ─── Structured Verifier Result ──────────────────────────────────────
## Each small verifier returns this. aggregate() only combines results.

type
  VerifierResult* = object
    passed*: bool
    verifier*: string
    reasons*: seq[string]

  CertificateEligibility* = object
    eligible*: bool
    reasons*: seq[string]

## ─── Verifier: Semantic Evidence ─────────────────────────────────────
## Uses the existing SSOT: certificateEvidenceFromJson → tierFromEvidence
## → statusConsistentWithEvidence. Pure func, no I/O.

func verifySemanticEvidence*(cert: JsonNode): VerifierResult {.raises: [].} =
  result.verifier = "verifySemanticEvidence"
  if cert.isNil or cert.kind != JObject:
    result.passed = false
    result.reasons.add("verifySemanticEvidence: certificate is not a JSON object")
    return
  let ev = certificateEvidenceFromJson(cert)
  if not ev.z3Passed and not ev.leanVerified:
    result.passed = false
    result.reasons.add("verifySemanticEvidence: no Z3 or Lean evidence present")
    return
  let tier = tierFromEvidence(ev)
  if tier == vtNone:
    result.passed = false
    result.reasons.add("verifySemanticEvidence: evidence yields vtNone tier")
    return
  if not statusConsistentWithEvidence(cert):
    result.passed = false
    result.reasons.add("verifySemanticEvidence: status exceeds stored evidence")
    return
  result.passed = true

## ─── Evidence Presence Helper ──────────────────────────────
## Pure check of whether the cert carries real semantic evidence
## (Z3 passed OR Lean verified), independent of status-labeled
## promotion eligibility. Used at the promotion entry to separate
## kernel-scope membership from promotion eligibility.

func hasSemanticEvidence*(cert: JsonNode): bool {.raises: [].} =
  if cert.isNil or cert.kind != JObject:
    return false
  let ev = certificateEvidenceFromJson(cert)
  ev.z3Passed or ev.leanVerified

## ─── Verifier: Proof Artifact (F2 placeholder) ──────────────────────
## No real proof object exists in v1. Returns NOT_APPLICABLE — never
## fabricates a pass. A real proof-object check lands here only when
## Z3 PROOF_MODE / real proof artifacts are wired into the pipeline.

func verifyProofArtifact*(cert: JsonNode): VerifierResult {.raises: [].} =
  result.verifier = "verifyProofArtifact"
  result.passed = false
  result.reasons.add("NOT_APPLICABLE: no real proof artifact in v1 (F2); proofDigest not fabricated")

## ─── Verifier: Acceptance ────────────────────────────────────────────
## Dual acceptance (admissibleEvidence) + deep verification (DIP callback).
## The deep-verify callback is injected by the caller (DIP) so this
## verifier stays testable without a real filesystem.
## This is a proc (not a func) because it calls an external callback.

type
  DeepVerifyCallback* = proc(cert: JsonNode; certPath: string): bool {.nimcall, raises: [].}

proc verifyAcceptance*(cert: JsonNode; bundle: EvidenceBundle;
    deepVerify: DeepVerifyCallback): VerifierResult {.raises: [].} =
  result.verifier = "verifyAcceptance"
  if not admissibleEvidence(bundle):
    result.passed = false
    result.reasons.add("verifyAcceptance: evidence is not dual-admissible (solverProved ∧ translationProved required)")
    return
  if deepVerify == nil:
    result.passed = false
    result.reasons.add("verifyAcceptance: deep-verify callback not provided")
    return
  if not deepVerify(cert, ""):
    result.passed = false
    result.reasons.add("verifyAcceptance: deep verification (isDeepVerified) failed")
    return
  result.passed = true

## ─── Verifier: Identity Binding ──────────────────────────────────────
## compV3Identity(reconstructed V3IdentityState) must equal stored
## identityDigest. Also checks inputHash/sourceHash/irHash consistency
## (no cycles; identity carries no provenance timestamp).

func verifyIdentityBinding*(cert: JsonNode): VerifierResult {.raises: [].} =
  result.verifier = "verifyIdentityBinding"
  if cert.isNil or cert.kind != JObject:
    result.passed = false
    result.reasons.add("verifyIdentityBinding: certificate is not a JSON object")
    return
  let storedDigest = cert.getOrDefault("identityDigest").getStr("")
  if storedDigest.len == 0:
    result.passed = false
    result.reasons.add("verifyIdentityBinding: missing identityDigest")
    return
  let rebuilt = v3IdentityFromJson(cert)
  if rebuilt != storedDigest:
    result.passed = false
    result.reasons.add("verifyIdentityBinding: identityDigest mismatch (rebuilt != stored)")
    return
  # inputHash consistency: must be non-empty
  let inputHash = cert.getOrDefault("inputHash").getStr("")
  if inputHash.len == 0:
    result.passed = false
    result.reasons.add("verifyIdentityBinding: missing inputHash")
    return
  # sourceHash and irHash must be present for identity to be meaningful
  let sourceHash = cert.getOrDefault("sourceHash").getStr("")
  let irHash = cert.getOrDefault("irHash").getStr("")
  if sourceHash.len == 0:
    result.passed = false
    result.reasons.add("verifyIdentityBinding: missing sourceHash")
    return
  if irHash.len == 0:
    result.passed = false
    result.reasons.add("verifyIdentityBinding: missing irHash")
    return
  result.passed = true

## ─── Verifier: Certificate Completeness ─────────────────────────────
## All required v3 fields present and non-empty. Also folds in the
## validateCertGreenWritable syntactic gate (winningStrategy for certGreen).

const requiredV3Fields*: seq[string] = @[
  "claim", "attestation", "inputHash", "provenance",
  "toolchainIdentity", "solverInvocation", "solverInputDigest",
  "solverResultDigest", "identityDigest", "schemaVersion",
  "modulePath", "functionName", "sourceHash", "irHash"
]

func verifyCertificateCompleteness*(cert: JsonNode): VerifierResult {.raises: [].} =
  result.verifier = "verifyCertificateCompleteness"
  if cert.isNil or cert.kind != JObject:
    result.passed = false
    result.reasons.add("verifyCertificateCompleteness: certificate is not a JSON object")
    return
  for field in requiredV3Fields:
    if not cert.hasKey(field):
      result.passed = false
      result.reasons.add("verifyCertificateCompleteness: missing required field '" & field & "'")
      return
    let val = cert.getOrDefault(field)
    if val.kind == JString and val.getStr().len == 0:
      result.passed = false
      result.reasons.add("verifyCertificateCompleteness: required field '" & field & "' is empty")
      return
    if val.kind == JObject and val.len == 0:
      result.passed = false
      result.reasons.add("verifyCertificateCompleteness: required field '" & field & "' is an empty object")
      return
  # validateCertGreenWritable syntactic gate: certGreen requires winningStrategy
  let status = cert.getOrDefault("status").getStr("")
  if status == "certGreen":
    if not cert.hasKey("winningStrategy"):
      result.passed = false
      result.reasons.add("verifyCertificateCompleteness: certGreen requires winningStrategy field")
      return
    let ws = cert.getOrDefault("winningStrategy")
    if ws.kind != JString:
      result.passed = false
      result.reasons.add("verifyCertificateCompleteness: certGreen winningStrategy must be a string")
      return
    if ws.getStr().len == 0:
      result.passed = false
      result.reasons.add("verifyCertificateCompleteness: certGreen requires non-empty winningStrategy")
      return
    if not statusConsistentWithEvidence(cert):
      result.passed = false
      result.reasons.add("verifyCertificateCompleteness: certGreen status inconsistent with stored evidence")
      return
  result.passed = true

## ─── Aggregate: Pure Policy Reducer ─────────────────────────────────
## Input: the set of required verifier IDs + per-verifier structured results.
## Output: ELIGIBLE iff every required verifier reports passed=true;
##         otherwise NOT_ELIGIBLE(reasons[]) = union of failing reasons.
## Performs NO new verification — does not read evidence or compute digests.
## Uses a simple linear scan instead of HashSet to avoid importing std/tables.

func aggregate*(policy: seq[string]; results: seq[VerifierResult]): CertificateEligibility {.raises: [].} =
  result.eligible = true
  for r in results:
    # Check if this verifier is in the required policy
    var required = false
    for p in policy:
      if r.verifier == p:
        required = true
        break
    if not required:
      continue
    if not r.passed:
      result.eligible = false
      for reason in r.reasons:
        result.reasons.add(r.verifier & ": " & reason)
  if result.eligible:
    result.reasons = @[]

{.pop.}