import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/utils/constants
import core/domain_types
import core/json/json_utils
import core/json/std_redirect
import core/parsers/pnode_nav
import core/results as res
import core/types/verification_tier
import core/utils/file_utils
import std/options
import std/os
import std/sequtils
import std/sets
import std/tables
import compiler/ast
import verification/analyzer/analyzer_shared_cert
import verification/analyzer/analyzer_shared_json
import verification/ast_extractor
import verification/cert_writer
import verification/certificate_manager
import verification/dependency_analyzer
import verification/fingerprint_engine
import verification/state_manager
proc loadCertificateFromFile*(certificatePath: string): FunctionCertificate =
  var cert = createInvalidCertificate(certificatePath)
  let root = readJsonFileNode(certificatePath)
  if root.isNil or root.kind != JObject:
    return cert
  cert.theoremName = firstStringField(root, @["theorem", "theoremName"])
  cert.functionName = firstStringField(root, @[functionNameKey, "function",
      "symbol", "name"])
  cert.modulePath = FilePath(firstStringField(root, @[modulePathKey, "module",
      "sourcePath", "file"]))
  cert.fingerprint = firstStringField(root, @["fingerprint", "digest",
      "certificateFingerprint"])
  cert.structuralFingerprint = firstStringField(root, @["structuralFingerprint",
      "structureFingerprint"])
  cert.currentStructuralFingerprint = firstStringField(root, @[
      "currentStructuralFingerprint", "currentStructureFingerprint"])
  cert.trusted = firstBoolField(root, @[trustedKey], true)
  cert.calls = firstArrayField(root, @["calls", "dependencies", "callGraph"])
  cert.accessedResources = firstArrayField(root, @["accessedResources",
      "resources", "globalDependencies"])
  cert.mutatedResources = firstArrayField(root, @["mutatedResources",
      "mutations", "writes"])
  cert.imports = firstArrayField(root, @["imports", "importDependencies", "modules"])
  cert.constraints = firstArrayField(root, @["constraints", "asserts"])
  cert.selfHealingAsserts = firstArrayField(root, @["selfHealingAsserts",
      "autoAsserts", "injectedAsserts"])
  cert.recoveredDefects = firstArrayField(root, @["recoveredDefects",
      "selfHealingSummary"])
  cert.retryCount = firstIntField(root, @[retryCountKey, "retries", "attempts"], 0)
  cert.winningStrategy = firstStringField(root, @["winningStrategy",
      strategyKey, "winning_strategy"])
  cert.globalGraphFingerprint = firstStringField(root, @[
      "globalGraphFingerprint", "graphFingerprint", "global_graph_fingerprint"])
  cert.leanArtifactHash = firstStringField(root, @["leanArtifactHash",
      "lean_hash", "leanArtifact"])
  cert.axiomId = firstStringField(root, @["axiomId", "axiom_id"])
  cert.axiomVersion = firstStringField(root, @["axiomVersion", "axiom_version"])
  cert.axiomHash = firstStringField(root, @["axiomHash", "axiom_hash"])
  cert.linkageVerified = firstBoolField(root, @["linkageVerified",
      "linkage_verified"], false)
  let rawReason = firstStringField(root, @[reasonKey, "statusReason",
      "proofReason"])
  let rawStatus = firstStringField(root, @[statusKey, "safetyStatus"])
  if rawStatus.len > 0:
    let parsed = keyToStatus(rawStatus)
    var finalStatus = parsed
    # P0 (verification_density.md): certGreen is only legitimate when the stored
    # evidence is dual (z3Passed ∧ leanVerified). A status string alone never
    # grants Green — when Green is claimed, derive the honest tier from the
    # canonical evidence chain so Z3-only evidence cannot overclaim certGreen.
    if parsed == certGreen and not statusConsistentWithEvidence(root):
      finalStatus = tierToCertStatus(tierFromEvidence(certificateEvidenceFromJson(root)))
    setCertificateStatus(
      cert,
      finalStatus,
      if rawReason.len > 0: rawReason else: "status-from-certificate"
    )
  else:
    # P0-a: fail-closed — a certificate with a missing status field
    # must NEVER default to certGreen. It remains in its initial
    # invalid state (certRed / "certificate-invalid").
    setCertificateStatus(cert, certRed, "status-missing-fail-closed")
  return cert

# @axiom-hint: lean="cert_certificatePath.length ≥ 0 ∧ cert_reason.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len cert_certificatePath) 0) (>= (str.len cert_reason) 0) external_io_isolated))"
# @axiom-hint: lean="rootOpt.isNone = true ∧ (root ≥ 0)" smt="(assert (and (= (option.isNone rootOpt) true) (>= root 0)))"
proc persistCertificateGateStatus*(cert: FunctionCertificate) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  if string(cert.certificatePath).len == 0 or not fileExists(string(
      cert.certificatePath)):
    return
  var root = readJsonFileNode(string(cert.certificatePath))
  if root.isNil or root.kind != JObject:
    return
  root[statusKey] = newJString($cert.status)
  root[reasonKey] = newJString(cert.reason)
  root["linkageVerified"] = newJBool(cert.linkageVerified)
  if not writeCertificate(string(cert.certificatePath), root):
    discard # write failure is non-fatal; {.raises: [].} prevents stderr logging

func selfHealMatchedStatus*(current: CertificateStatus;
                            root: JsonNode): CertificateStatus {.raises: [CatchableError].} =
  ## Evidence-based status resolution for the fingerprint-matched self-healing
  ## path. P0 invariant (docs/spec/verification_density.md): certGreen requires
  ## dual (Z3 AND Lean) validated evidence — a matching fingerprint credits
  ## source freshness only, it NEVER promotes a certificate on its own.
  ## The healed status is derived from the stored evidence chain
  ## (certificateEvidenceFromJson → tierFromEvidence → tierToCertStatus):
  ##   dual evidence       → certGreen
  ##   Z3-only evidence    → certZ3Verified
  ##   Lean-only evidence  → certLeanVerified
  ##   missing/unparseable evidence → current status unchanged (no promotion)
  ## certVerifiedAxiom is axiom-trust (not Z3/Lean evidence) and is preserved.
  if current == certVerifiedAxiom:
    return current
  let evidenceTier = tierFromEvidence(certificateEvidenceFromJson(root))
  if evidenceTier == vtNone:
    return current
  tierToCertStatus(evidenceTier)

# @axiom-hint: lean="n ≥ -9223372036854775808 ∧ n ≤ 9223372036854775807" smt="(assert (and (and (>= n -9223372036854775808) (<= n 9223372036854775807))))"
# @axiom-hint: lean="n ≤ 0" smt="(assert (and (<= n 0)))"
proc hydrateCertificate*(
  cert: var FunctionCertificate;
  certBaseDir: string;
  knownFunctions: HashSet[string];
  globalsByModule: var Table[string, HashSet[string]];
  moduleFunctionsByPath: var Table[string, HashSet[string]];
  missingCertificates: var int;
  mismatchedFingerprints: var int;
  currentGraphHash: string = "";
  engineSalt: string = ""
) {.axiomDecision(id = "DECISION-0630", reason = "Updated raises clause to accommodate canonical write guard in writeCertificate", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if string(cert.modulePath).len == 0:
    cert.modulePath = FilePath(inferModulePathFromTheorem(certBaseDir,
        cert.theoremName))
  if cert.functionName.len == 0:
    cert.functionName = inferFunctionNameFromTheorem(cert.theoremName, string(
        cert.modulePath))
  if cert.functionName.len == 0 or string(cert.modulePath).len == 0 or
      cert.fingerprint.len == 0:
    markCertificateInvalid(cert, "missing-certificate-fields")
    inc missingCertificates
    return
  let sourcePath = resolveSourcePath(certBaseDir, string(cert.modulePath))
  if sourcePath.len == 0 or not fileExists(sourcePath):
    if isPreludeOnlyVerifiedAxiom(cert):
      return
    setCertificateStatus(cert, certStale, "orphaned-certificate:source-not-found")
    return
  let source = readFileSafe(sourcePath)
  if not globalsByModule.hasKey(sourcePath):
    let gsRes = collectGlobalSymbols(source)
    if gsRes.isOk:
      globalsByModule[sourcePath] = gsRes.value
  if not moduleFunctionsByPath.hasKey(sourcePath):
    let mfRes = collectModuleFunctions(source)
    if mfRes.isOk:
      moduleFunctionsByPath[sourcePath] = mfRes.value
  var fnNodeOpt = none(PNode)
  let indexRes = getCachedFunctionNodeIndex(source)
  if indexRes.isOk:
    let index = res.get(indexRes)
    fnNodeOpt = if index.hasKey(cert.functionName): some(index[
        cert.functionName]) else: none(PNode)
  let extractedRes = extractFunctionBody(source, cert.functionName)
  if not extractedRes.isOk:
    if isPreludeOnlyVerifiedAxiom(cert):
      return
    setCertificateStatus(cert, certStale, "orphaned-certificate:function-not-found")
    return
  if not res.get(extractedRes).found:
    if isPreludeOnlyVerifiedAxiom(cert):
      return
    setCertificateStatus(cert, certStale, "orphaned-certificate:function-not-found")
    return
  let extracted = res.get(extractedRes)
  if cert.calls.len == 0 and fnNodeOpt.isSome:
    cert.calls = inferCallsFromBody(fnNodeOpt.get, knownFunctions,
        cert.functionName)
  let moduleStem = splitFile(string(cert.modulePath)).name
  cert.calls = cert.calls
    .mapIt(normalizeDependencyName(it, moduleStem, moduleFunctionsByPath[sourcePath]))
    .filterIt(it.len > 0)
    .deduplicate()
  if cert.accessedResources.len == 0 and fnNodeOpt.isSome:
    cert.accessedResources = inferAccessedResourcesFromBody(
      fnNodeOpt.get,
      globalsByModule[sourcePath],
      cert.functionName
    )
  if cert.mutatedResources.len == 0 and fnNodeOpt.isSome:
    cert.mutatedResources = collectMutatedResourcesP(
      fnNodeOpt.get,
      globalsByModule[sourcePath]
    )
  var candidates = computeFingerprintCandidates(extracted.body,
      cert.constraints, engineSalt)
  let fullSourceCandidates = computeFingerprintCandidates(source,
      cert.constraints, engineSalt)
  for c in fullSourceCandidates:
    candidates.add(c)
  candidates = candidates.deduplicate()
  let structuralCandidates = computeStructuralFingerprintCandidates(
      extracted.body, cert.constraints, cert.functionName)
  if candidates.len > 0:
    cert.currentFingerprint = candidates[0]
  if structuralCandidates.len > 0:
    cert.currentStructuralFingerprint = structuralCandidates[0]
  var matched = false
  for candidate in candidates:
    if candidate == cert.fingerprint:
      cert.currentFingerprint = candidate
      matched = true
      break
  if cert.structuralFingerprint.len > 0:
    var structuralMatched = false
    for candidate in structuralCandidates:
      if candidate == cert.structuralFingerprint:
        cert.currentStructuralFingerprint = candidate
        structuralMatched = true
        break
    if not structuralMatched and cert.currentStructuralFingerprint.len == 0 and
        structuralCandidates.len > 0:
      cert.currentStructuralFingerprint = structuralCandidates[0]
  let repoRoot = if certBaseDir.len > 0: parentDir(parentDir(parentDir(
      certBaseDir))) else: getCurrentDir()
  let localAuditPath = joinPath(repoRoot, "logs", "audit", "stream.jsonl")
  if not matched:
    let fpReason = if cert.currentFingerprint.len > 0 and
        cert.currentFingerprint !=
        cert.fingerprint: "source-changed" else: "fingerprint-mismatch"
    setCertificateStatus(cert, certStale, fpReason)
    inc mismatchedFingerprints
    try:
      let rootOpt = readJsonFile(string(cert.certificatePath))
      if rootOpt.isSome:
        var node = rootOpt.get()
        node[statusKey] = newJString("certStale")
        node[reasonKey] = newJString(fpReason)
        node["currentFingerprint"] = %cert.currentFingerprint
        if not writeCertificate(string(cert.certificatePath), node):
          discard # write failure is non-fatal; {.raises: [].} prevents stderr logging
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    let fpPayload = %*{
      "fingerprint": cert.fingerprint,
      "currentFingerprint": cert.currentFingerprint,
      "reason": fpReason
    }
    discard appendGenericAuditEvent(localAuditPath,
        "certificate_fingerprint_stale", cert.functionName, fpPayload)
  elif cert.status != certPending:
    # L2 (verification_density.md): self-healing is evidence-based — see
    # selfHealMatchedStatus. A matching fingerprint never promotes a certificate
    # to certGreen by default; the healed status is derived from stored
    # evidence, and missing/unparseable evidence leaves the status unchanged.
    var matchedStatus = cert.status
    let rootOpt = readJsonFile(string(cert.certificatePath))
    if rootOpt.isSome:
      matchedStatus = selfHealMatchedStatus(cert.status, rootOpt.get())
    setCertificateStatus(cert, matchedStatus, "fingerprint-matched")
    ## Self-Healing: update stale globalGraphFingerprint when body fingerprint matches.
    if currentGraphHash.len > 0 and cert.globalGraphFingerprint != currentGraphHash:
      let oldGraphFingerprint = cert.globalGraphFingerprint
      cert.globalGraphFingerprint = currentGraphHash
      try:
        let rootOpt = readJsonFile(string(cert.certificatePath))
        if rootOpt.isSome:
          var node = rootOpt.get()
          node["globalGraphFingerprint"] = %cert.globalGraphFingerprint
          if not writeCertificate(string(cert.certificatePath), node):
            discard # write failure is non-fatal; {.raises: [].} prevents stderr logging
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
      let healPayload = %*{
        "functionName": cert.functionName,
        "oldGraphFingerprint": oldGraphFingerprint,
        "newGraphFingerprint": currentGraphHash
      }
      discard appendGenericAuditEvent(localAuditPath,
          "certificate_graph_fingerprint_healed", cert.functionName, healPayload)
    let fpPayload = %*{
      "fingerprint": cert.fingerprint,
      "currentFingerprint": cert.currentFingerprint,
      "reason": "fingerprint-matched"
    }
    discard appendGenericAuditEvent(localAuditPath,
        "certificate_fingerprint_matched", cert.functionName, fpPayload)

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="cyclicFunctions.length = 0 ∧ (summary ≥ 0)" smt="(assert (and (= (str.len cyclicFunctions) 0) (>= summary 0)))"

{.pop.}
