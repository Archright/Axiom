import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## PersistedArtifactValidator — Authority D (R4)
##
## Validates persisted artifacts for schema/identity/provenance ONLY.
## Treats persisted records as HistoricalRecord — NEVER restores a
## current CVR verdict from persisted labels.
##
## Produces a ReplayRequest (fresh process/workspace, same binary/
## toolchain/input → canonical check re-run → new receipt → new KAA)
## instead of restoring a verdict from persisted state.
##
## Invariant: PersistedArtifactValidator does NOT produce KAA.
## KAA creation is exclusively Authority B (KernelAcceptanceAuthority.bind).
## KAA private constructor import-graph access is FORBIDDEN from this module.

import std/[os, json, strutils, options]
import core/crypto/hash_kernel
import core/types/certificate_types
import verification/obligation/lean_kernel_boundary

# ---------------------------------------------------------------------------
# HistoricalRecord — a persisted artifact as a neutral historical record
# ---------------------------------------------------------------------------
## A HistoricalRecord is a past observation of a certificate/persisted
## artifact.  It records WHAT was observed at persistence time but
## carries NO authority to produce a current verdict.  It is the
## specification for a ReplayRequest, not a substitute for one.
##
## Key invariant: no field in HistoricalRecord may be used to directly
## construct or reconstruct vvVerified (v3.8 high fixed invariant 3).
## Persisted `verified=true` → CVR is FORBIDDEN.

type HistoricalRecord* = object
  artifactIdentity*: string          ## SHA256 of the persisted artifact
  theoremIdentity*: string           ## theorem name from the artifact
  persistedStatus*: string           ## raw status string from persisted record
  persistedCertificateStatus*: CertificateStatus ## parsed cert status
  sourceHash*: string                ## source fingerprint at persistence time
  toolchainFingerprint*: string      ## toolchain at persistence time
  persistenceTimestamp*: int64       ## epoch ms when persisted
  provenance*: string                ## where this record came from (e.g. "trust-commit")

# ---------------------------------------------------------------------------
# ReplayRequest — triggers a fresh canonical check
# ---------------------------------------------------------------------------
## A ReplayRequest instructs the system to re-run the canonical kernel
## check with the same binary/toolchain/input that produced the original
## artifact.  The result is a NEW receipt → new KAA → new Decision →
## new CVR.  The semantic identity of the fresh result is compared to
## the HistoricalRecord for reproducibility, but the fresh result's
## authority comes from the canonical sink, NOT from the persisted state.
##
## fresh KAA = authority, persisted KAA digest = historical claim.
## `fresh KAA ≠ historical digest` means "this replay differs from
## the historical record" — NOT "the fresh KAA is wrong".

type ReplayRequest* = object
  artifactIdentity*: string          ## what to re-run (same as original)
  leanSource*: string                ## the canonical lean source to re-check
  toolchainFingerprint*: string      ## the canonical toolchain to use
  invocationContract*: string        ## the canonical argv string
  expectedTheoremIdentity*: string   ## theorem identity to verify
  historicalRecord*: Option[HistoricalRecord] ## the historical record for comparison (may be none for fresh artifacts)

# ---------------------------------------------------------------------------
# PersistedArtifactValidator — schema/identity/provenance validation only
# ---------------------------------------------------------------------------

type PersistedArtifactValidator* = object
  ## Opaque validator — private fields, private constructor.
  ## Only `validate` may produce a result.
  allowedSources*: seq[string]       ## trusted persistence sources

# ---------------------------------------------------------------------------
# Validation result — either a HistoricalRecord (valid persisted artifact)
# or a ReplayRequest (trigger fresh canonical check)
# ---------------------------------------------------------------------------

type PersistedValidationResult* = enum
  pvrHistoricalRecord   ## valid persisted record → HistoricalRecord only
  pvrReplayRequest      ## valid persisted record → ReplayRequest for fresh check
  pvrRejected           ## invalid persisted record → reject

type PersistedValidationOutcome* = object
  status*: PersistedValidationResult
  historicalRecord*: Option[HistoricalRecord]
  replayRequest*: Option[ReplayRequest]
  reason*: string

# ---------------------------------------------------------------------------
# validate — schema/identity/provenance check, NO verdict restoration
# ---------------------------------------------------------------------------
## Validates a persisted artifact for schema conformance, identity
## integrity, and provenance.  NEVER restores a current CVR verdict
## from persisted labels.  Produces either a HistoricalRecord or a
## ReplayRequest — never a KAA, never a verified verdict.
##
## This is Authority D: the persisted artifact is treated as a
## historical record, not as an authority.  The only path to a
## verified verdict is fresh canonical check → new receipt → bind → KAA.

proc validate*(validator: PersistedArtifactValidator;
               artifact: JsonNode;
               source: string): PersistedValidationOutcome {.raises: [].} =
  ## Validate a persisted artifact node.  Returns a PersistedValidationOutcome
  ## containing either a HistoricalRecord or a ReplayRequest, never a KAA
  ## or a verified verdict.

  # Schema check: must have required fields
  let modulePath = artifact.getOrDefault("modulePath").getStr("")
  let functionName = artifact.getOrDefault("functionName").getStr("")
  if modulePath.len == 0 or functionName.len == 0:
    return PersistedValidationOutcome(
      status: pvrRejected,
      reason: "schema validation failed: missing modulePath or functionName"
    )

  # Identity check: artifact identity must be present
  let artifactIdentity = artifact.getOrDefault("identityDigest").getStr("")
  if artifactIdentity.len == 0:
    return PersistedValidationOutcome(
      status: pvrRejected,
      reason: "identity validation failed: missing identityDigest"
    )

  # Provenance check: source must be in allowed list
  if validator.allowedSources.len > 0 and source notin validator.allowedSources:
    return PersistedValidationOutcome(
      status: pvrRejected,
      reason: "provenance validation failed: source '" & source & "' not in allowed sources"
    )

  # Extract persisted status — this is a HISTORICAL label, NOT a current verdict
  let persistedStatus = artifact.getOrDefault("status").getStr("certPending")
  let certStatus = parseCertificateStatus(persistedStatus)

  # Build the HistoricalRecord — this is a NEUTRAL past record
  let histRecord = HistoricalRecord(
    artifactIdentity: artifactIdentity,
    theoremIdentity: artifact.getOrDefault("theoremIdentity").getStr(""),
    persistedStatus: persistedStatus,
    persistedCertificateStatus: certStatus,
    sourceHash: artifact.getOrDefault("sourceHash").getStr(""),
    toolchainFingerprint: artifact.getOrDefault("toolchainIdentity").getStr(""),
    persistenceTimestamp: artifact.getOrDefault("persistenceTimestamp").getInt(0),
    provenance: source
  )

  # Produce a ReplayRequest — fresh canonical check, NOT verdict restoration
  # The ReplayRequest contains the canonical lean source and toolchain info
  # so that the system can re-run the canonical kernel check.
  let replayReq = ReplayRequest(
    artifactIdentity: artifactIdentity,
    leanSource: "",  # caller must supply the actual lean source
    toolchainFingerprint: histRecord.toolchainFingerprint,
    invocationContract: "",  # caller must supply the canonical invocation
    expectedTheoremIdentity: histRecord.theoremIdentity,
    historicalRecord: some(histRecord)
  )

  PersistedValidationOutcome(
    status: pvrReplayRequest,
    historicalRecord: some(histRecord),
    replayRequest: some(replayReq),
    reason: "persisted artifact validated as historical record; replay requested"
  )

# ---------------------------------------------------------------------------
# Convenience: validate and produce a ReplayRequest for fresh canonical check
# ---------------------------------------------------------------------------

proc requestReplay*(validator: PersistedArtifactValidator;
                    artifact: JsonNode;
                    source: string;
                    leanSource: string;
                    invocationContract: string): ReplayRequest {.raises: [].} =
  ## Validate a persisted artifact and produce a ReplayRequest for a
  ## fresh canonical kernel check.  The ReplayRequest carries the
  ## same binary/toolchain/input as the original execution so that
  ## the fresh check produces a new receipt → new KAA → new Decision.
  let outcome = validator.validate(artifact, source)
  if outcome.status == pvrReplayRequest and outcome.replayRequest.isSome:
    var req = outcome.replayRequest.get()
    req.leanSource = leanSource
    req.invocationContract = invocationContract
    req
  else:
    ReplayRequest(
      artifactIdentity: artifact.getOrDefault("identityDigest").getStr(""),
      leanSource: leanSource,
      toolchainFingerprint: "",
      invocationContract: invocationContract,
      expectedTheoremIdentity: artifact.getOrDefault("theoremIdentity").getStr(""),
      historicalRecord: none(HistoricalRecord)
    )

{.pop.}