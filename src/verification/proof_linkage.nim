import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Proof Linkage Verifier (Hard Mode → Wave 15)
##
## Hard Mode enforces: every verdict "certGreen" requires a physical
## .lean proof file whose SHA-256 hash matches the certificate.
##
## Wave 15 upgrade: Axiom Linkage Integrity — every certVerifiedAxiom
## certificate must record axiomId + axiomVersion + axiomHash.
## On re-verification, hash mismatch → gate closure.

import std/os
import core/verified_axioms/verified_axioms_catalog_part1
import core/verified_axioms/verified_axioms_core
import std/strutils
import std/options
import checksums/sha2
import core/verified_axioms/verified_axioms
import core/domain_types
import core/utils/file_utils
import ../core/trusted/axiom_pragmas
# axiomIoBoundary

const evidenceDir = "logs/evidence"

# ---------------------------------------------------------------------------
# Hash Computation
# ---------------------------------------------------------------------------

proc computeLeanHash*(leanPath: string): string {.raises: [], axiom: ["(assert (and (>= (str.len leanPath) 0) external_io_isolated (>= result 0) external_io_isolated))", "leanPath.length ≥ 0 ∧ external_io_isolated ∧ (result ≥ 0) ∧ external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(leanPath): return ""
  try:
    var hasher = initSha_256()
    hasher.update(readFileSafe(leanPath))
    result = $hasher.digest()
  except CatchableError:
    result = ""

# ---------------------------------------------------------------------------
# Legacy Proof Linkage (certGreen)
# ---------------------------------------------------------------------------

proc verifyProofLinkage*(nodeId: string; leanSourceHash: string): bool {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) (>= (str.len leanSourceHash) 0) (= (str.len leanSourceHash) 0) (not (= kind pcFile)) (= actualHash leanSourceHash) (> (str.len actualHash) 0) false true (=> (= (str.len leanSourceHash) 0) (= result false)) (=> (= actualHash leanSourceHash) (= result true)) (=> (> (str.len actualHash) 0) (= result false))))", "nodeId.length ≥ 0 ∧ leanSourceHash.length ≥ 0 ∧ leanSourceHash.length = 0 ∧ kind ≠ pcFile ∧ actualHash = leanSourceHash ∧ actualHash.length > 0 ∧ false ∧ true ∧ leanSourceHash.length = 0 → result = false ∧ actualHash = leanSourceHash → result = true ∧ actualHash.length > 0 → result = false"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns true if a .lean evidence file exists for this node
  ## and its hash matches the expected hash.
  if leanSourceHash.len == 0: return false
  let safeId = nodeId.replace("/", "_").replace("::", "_").replace("\\", "_")
  try:
    for kind, path in walkDir(evidenceDir):
      if kind != pcFile: continue
      if not path.endsWith(".lean"): continue
      if safeId notin extractFilename(path): continue
      let actualHash = computeLeanHash(path)
      if actualHash == leanSourceHash: return true
      if actualHash.len > 0: return false  # mismatch
  except CatchableError:
    return false
  return false  # no evidence file found

# ---------------------------------------------------------------------------
# Axiom Linkage Integrity (Wave 15 — certVerifiedAxiom)
# ---------------------------------------------------------------------------

# AxiomLinkageResult — SSOT in core/types/domain_types.nim
# (moved to break gate→verification dependency)

proc verifyAxiomLinkage*(cert: FunctionCertificate): AxiomLinkageResult {.raises: [], axiom: ["(assert (and (>= depth 0) (= (option.isNone axiomOpt) true) (not (= kind pcFile)) (> (str.len actualHash) 0) (= artifactFound true) (= artifactHashMatch true) (>= artifactFound 0) (>= artifactHashMatch 0)))", "depth >= 0 ∧ axiomOpt.isNone = true ∧ kind ≠ pcFile ∧ actualHash.length > 0 ∧ artifactFound = true ∧ artifactHashMatch = true ∧ (artifactFound ≥ 0) ∧ (artifactHashMatch ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Performs 4-stage hash-based axiom linkage verification:
  ##   1. Is cert.status == certVerifiedAxiom?
  ##   2. Look up the axiom by cert.axiomId in the registry
  ##   3. cert.axiomHash == current axiom.sourceHash?
  ##   4. cert.leanArtifactHash matches current .lean file hash?

  ## Stage 1: Only applicable to certVerifiedAxiom certificates
  if cert.status != certVerifiedAxiom:
    return AxiomLinkageResult(
      verified: true,
      reason: "not a verified-axiom certificate (bypass)",
      axiomId: ""
    )

  ## Stage 2: Look up axiom in registry
  if cert.axiomId.len == 0:
    return AxiomLinkageResult(
      verified: false,
      reason: "certVerifiedAxiom missing axiomId field",
      axiomId: ""
    )

  let axiomOpt = lookupAxiom(cert.axiomId)
  if axiomOpt.isNone:
    return AxiomLinkageResult(
      verified: false,
      reason: "axiom '" & cert.axiomId & "' not found in verified_axioms.nim registry",
      axiomId: cert.axiomId
    )

  let axiom = axiomOpt.get()

  ## Stage 2b: Version check
  if cert.axiomVersion.len > 0 and cert.axiomVersion != axiom.axiomVersion:
    return AxiomLinkageResult(
      verified: false,
      reason: "axiom version mismatch: cert=" & cert.axiomVersion &
              " current=" & axiom.axiomVersion,
      axiomId: cert.axiomId
    )

  ## Stage 3: Axiom hash match
  if cert.axiomHash.len == 0:
    return AxiomLinkageResult(
      verified: false,
      reason: "certVerifiedAxiom missing axiomHash (cert issued before Wave 15)",
      axiomId: cert.axiomId
    )

  let currentAxiomHash = computeAxiomHash(axiom.axiomId, axiom.nimSignature, axiom.leanSignature)
  if cert.axiomHash != currentAxiomHash:
    return AxiomLinkageResult(
      verified: false,
      reason: "axiom hash mismatch — axiom definition has changed since certification",
      axiomId: cert.axiomId,
      expectedHash: cert.axiomHash,
      currentHash: currentAxiomHash
    )

  ## Stage 4: Lean artifact hash match (if available)
  if cert.leanArtifactHash.len > 0:
    let safeId = cert.functionName.replace("/", "_").replace("::", "_").replace("\\", "_")
    var artifactFound = false
    var artifactHashMatch = false
    try:
      for kind, path in walkDir(evidenceDir):
        if kind != pcFile: continue
        if not path.endsWith(".lean"): continue
        if safeId notin extractFilename(path): continue
        artifactFound = true
        let actualHash = computeLeanHash(path)
        if actualHash == cert.leanArtifactHash:
          artifactHashMatch = true
          break
        if actualHash.len > 0:
          # mismatch — this is blocking
          return AxiomLinkageResult(
            verified: false,
            reason: "Lean artifact hash mismatch: evidence file has been modified",
            axiomId: cert.axiomId,
            expectedHash: cert.leanArtifactHash,
            currentHash: actualHash
          )
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    if artifactFound and not artifactHashMatch:
      return AxiomLinkageResult(
        verified: false,
        reason: "Lean artifact hash mismatch",
        axiomId: cert.axiomId
      )

    if not artifactFound and cert.leanArtifactHash.len > 0:
      return AxiomLinkageResult(
        verified: false,
        reason: "Lean evidence artifact not found for this certificate",
        axiomId: cert.axiomId
      )

  ## All stages passed
  return AxiomLinkageResult(
    verified: true,
    reason: "axiom linkage integrity verified (v" & axiom.axiomVersion & ")",
    axiomId: cert.axiomId,
    expectedHash: cert.axiomHash,
    currentHash: currentAxiomHash
  )

{.pop.}

