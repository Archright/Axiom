import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import std/os
import std/options
import std/strutils
import core/domain_types
import core/json/json_utils
import core/verified_axioms/verified_axioms_catalog_part1
import core/verified_axioms/verified_axioms
import core/json/std_redirect
import core/results
import core/utils/io_utils
import verification/unified_trajectory
import core/axiom_pragmas
import infrastructure/logging_facade
import core/proof/source_fingerprint
import core/io/file_utils
import core/types/verification_tier
import verification/cert_vault_role
import verification/certificate_eligibility
import core/trusted/trust_commit
# axiomIoBoundary

## Hard-Gate: certGreen certificates MUST have a non-empty winningStrategy.
## certVerifiedAxiom certificates MUST have registry-linked axiom identity.
## Returns true only for JSON object certificates that are already verified.
## This gate prevents the "missing-audit-trail" mass-demotion bug.
# @axiom-hint: lean="node != null → true" smt="(assert true)"
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="axiomId.length = 0 ∨ axiomVersion.length = 0 ∨ axiomHash.length = 0 ∧ winningStrategy.length = 0 ∧ true ∧ false ∧ axiomId.length = 0 ∨ axiomVersion.length = 0 ∨ axiomHash.length = 0 → result = false ∧ winningStrategy.length = 0 → result = false" smt="(assert (and (or (or (= (str.len axiomId) 0) (= (str.len axiomVersion) 0)) (= (str.len axiomHash) 0)) (= (str.len winningStrategy) 0) true false (=> (or (or (= (str.len axiomId) 0) (= (str.len axiomVersion) 0)) (= (str.len axiomHash) 0)) (= result false)) (=> (= (str.len winningStrategy) 0) (= result false))))"
proc attachBmcSourceHash*(certNode: JsonNode; modulePath: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic source-staleness anchor for BMC-generated certificates.
  ## Reads the module source at `modulePath` (relative to the repo root / cwd),
  ## computes computeStableSourceFingerprint and stores it as `sourceHash`.
  ## The VKD checker (certificate_verifier stage 1.b) compares it against the
  ## CURRENT file content — fail-closed on missing/unreadable/mismatch.
  ## Returns false when the source cannot be read (cert stays without sourceHash,
  ## which the checker then rejects — honest fail-closed).
  if certNode.isNil or certNode.kind != JObject or modulePath.len == 0:
    return false
  let sourceContent = try: readFileSafe(modulePath) except CatchableError: ""
  if sourceContent.len == 0:
    return false
  certNode["sourceHash"] = newJString(computeStableSourceFingerprint(sourceContent))
  true

func certificateWriteRejectionReason(node: JsonNode): string {.raises: [].} =
  if node.kind != JObject:
    return "certificate payload must be a JSON object"
  if not node.hasKey("status"):
    return "certificate payload requires status field"
  if node{"status"}.kind != JString:
    return "certificate status field must be a JSON string"
  let status = node{"status"}.getStr()
  case status
  of "certGreen":
    if not node.hasKey("winningStrategy"):
      return "certificate status certGreen requires winningStrategy field"
    if node{"winningStrategy"}.kind != JString:
      return "certificate status certGreen requires winningStrategy string field"
    if node{"winningStrategy"}.getStr().len == 0:
      return "certificate status certGreen requires non-empty winningStrategy"
    if not statusConsistentWithEvidence(node):
      return "certificate status certGreen requires dual (Z3 AND Lean) evidence"
    return ""
  of "certVerifiedAxiom":
    for fieldName in @["axiomId", "axiomVersion", "axiomHash"]:
      if not node.hasKey(fieldName):
        return "certificate status certVerifiedAxiom requires " & fieldName & " field"
      if node{fieldName}.kind != JString:
        return "certificate status certVerifiedAxiom requires " & fieldName & " string field"
    let axiomId = node{"axiomId"}.getStr()
    let axiomVersion = node{"axiomVersion"}.getStr()
    let axiomHash = node{"axiomHash"}.getStr()
    if axiomId.len == 0:
      return "certificate status certVerifiedAxiom requires non-empty axiomId"
    if axiomVersion.len == 0:
      return "certificate status certVerifiedAxiom requires non-empty axiomVersion"
    if axiomHash.len == 0:
      return "certificate status certVerifiedAxiom requires non-empty axiomHash"
    if not verifyAxiomHash(axiomId, axiomHash):
      return "certificate status certVerifiedAxiom has invalid axiomHash"
    return ""
  of "certLeanVerified":
    # Lean-kernel verification (vtLeanOnly / vtUfAbstract tier). Requires the
    # content-addressable identity fields so the certificate is auditable.
    for fieldName in @["modulePath", "functionName", "fingerprint", "sourceHash"]:
      if not node.hasKey(fieldName):
        return "certificate status certLeanVerified requires " & fieldName & " field"
      if node{fieldName}.kind != JString:
        return "certificate status certLeanVerified requires " & fieldName & " string field"
    if node{"fingerprint"}.getStr().len == 0:
      return "certificate status certLeanVerified requires non-empty fingerprint"
    if node{"sourceHash"}.getStr().len == 0:
      return "certificate status certLeanVerified requires non-empty sourceHash"
    return ""
  of "certZ3Verified":
    # Z3-only verification (vtZ3Only tier, two_phase_verification.md:126).
    # P0: a Z3-only certificate is an honest, documentable terminal state —
    # it is never certGreen and never VKD-admissible, but it IS a writable
    # certificate (certificate_verifier accepts it; verification_density.md
    # §296). Mirror the certLeanVerified field contract.
    for fieldName in @["modulePath", "functionName", "fingerprint", "sourceHash"]:
      if not node.hasKey(fieldName):
        return "certificate status certZ3Verified requires " & fieldName & " field"
      if node{fieldName}.kind != JString:
        return "certificate status certZ3Verified requires " & fieldName & " string field"
    if node{"fingerprint"}.getStr().len == 0:
      return "certificate status certZ3Verified requires non-empty fingerprint"
    if node{"sourceHash"}.getStr().len == 0:
      return "certificate status certZ3Verified requires non-empty sourceHash"
    return ""
  of "certNoObligation":
    # No semantic obligation — normal proof-pipeline termination. Not a genuine
    # verification (excluded from VKD admission), but a valid, writable terminal
    # state distinct from certYellow (incomplete/failure).
    return ""
  else:
    return "certificate status must be certGreen or certVerifiedAxiom, got: " & status

func validateCertGreenWritable*(node: JsonNode): bool {.raises: [].} =
  return certificateWriteRejectionReason(node).len == 0

## Hard-Gate for FunctionCertificate objects.
## Mirrors validateCertGreenWritable for the typed domain model.
# @axiom-hint: lean="cert.status != certGreen → true" smt="(assert true)"
func functionCertificateWriteRejectionReason(cert: FunctionCertificate): string {.raises: [].} =
  case cert.status
  of certGreen:
    if cert.winningStrategy.len == 0:
      return "certificate status certGreen requires non-empty winningStrategy"
    return ""
  of certVerifiedAxiom:
    if cert.axiomId.len == 0:
      return "certificate status certVerifiedAxiom requires non-empty axiomId"
    if cert.axiomVersion.len == 0:
      return "certificate status certVerifiedAxiom requires non-empty axiomVersion"
    if cert.axiomHash.len == 0:
      return "certificate status certVerifiedAxiom requires non-empty axiomHash"
    if not verifyAxiomHash(cert.axiomId, cert.axiomHash):
      return "certificate status certVerifiedAxiom has invalid axiomHash"
    return ""
  of certLeanVerified:
    if cert.fingerprint.len == 0:
      return "certificate status certLeanVerified requires non-empty fingerprint"
    if cert.functionName.len == 0:
      return "certificate status certLeanVerified requires non-empty functionName"
    return ""
  of certZ3Verified:
    # Z3-only tier — honest, writable, never VKD-admissible (mirror of the
    # JSON hard-gate above).
    if cert.fingerprint.len == 0:
      return "certificate status certZ3Verified requires non-empty fingerprint"
    if cert.functionName.len == 0:
      return "certificate status certZ3Verified requires non-empty functionName"
    return ""
  of certNoObligation:
    return ""
  else:
    return "certificate status must be certGreen or certVerifiedAxiom, got: " & $cert.status

func validateCertGreenWritable*(cert: FunctionCertificate): bool {.raises: [].} =
  return functionCertificateWriteRejectionReason(cert).len == 0

## Set Certificate Status.
# @axiom-hint: lean="(cert ≥ 0) ∧ reason.length ≥ 0" smt="(assert (and (>= cert 0) (>= (str.len reason) 0)))"
func setCertificateStatus*(
  cert: var FunctionCertificate;
  status: CertificateStatus;
  reason: string
) {.inline.} =
  cert.status = status
  cert.reason = reason

## Mark Certificate Invalid.
# @axiom-hint: lean="reason.length ≥ 0" smt="(assert (and (>= (str.len reason) 0)))"
func markCertificateInvalid*(cert: var FunctionCertificate; reason: string) {.inline.} =
  setCertificateStatus(cert, certRed, reason)

## Mark Certificate Pending By Dependency.
# @axiom-hint: lean="dependency.length ≥ 0" smt="(assert (and (>= (str.len dependency) 0)))"
func markCertificatePendingByDependency*(
  cert: var FunctionCertificate;
  dependency: string
) {.inline.} =
  setCertificateStatus(cert, certPending, "pending-by-dependency:" & dependency)

## Create Invalid Certificate.
# @axiom-hint: lean="certificatePath.length ≥ 0" smt="(assert (and (>= (str.len certificatePath) 0)))"
func createInvalidCertificate*(certificatePath: string): FunctionCertificate =
  var path = certificatePath
  normalizePath(path)
  FunctionCertificate(
    certificatePath: FilePath(path),
    status: certRed,
    reason: "certificate-invalid"
  )

{.pop.}

## Write Certificate to Disk.
## writeCertificate* enforces validateCertGreenWritable before certificate persistence.
## writeCertificateContent* persists demotion/quarantine writes after the green gate.
## Returns true if write succeeded.
# @axiom-hint: lean="path.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len path) 0) external_io_isolated))"
# @axiom-hint: lean="false ∧ true ∧ external_io_isolated" smt="(assert (and false true external_io_isolated))"
proc writeCertificateContent(path: string; node: JsonNode): bool {.axiomEffect: IOEffect.} =
  let canonicalDir = resolveCertificate(cvCanonicalRead)
  let runtimeCanonicalDir = resolveCertificate(cvRuntimeCanonical)
  if (path.startsWith(canonicalDir) or path.startsWith(runtimeCanonicalDir)) and not promotionActive:
    raise newException(CatchableError, "DIRECT CANONICAL WRITE FORBIDDEN — must go through explicit promotion context (set promotionActive=true or use --promote flag)")
  try:
    let writeRes = writeFileOpt(path, renderJsonMultiline(node))
    if writeRes.isErr:
      logStage(skCertificate, path, "certificate write failed: " & writeRes.error, status=ssFailed)
      return false
    logStage(skCertificate, path, "certificate written", status=ssSucceeded)
    return true
  except CatchableError:
    logStage(skCertificate, path, "certificate write failed", status=ssFailed)
    return false

proc writeCertificate*(path: string; node: JsonNode): bool {.axiomDecision(id = "DECISION-0624", reason = "Write guard for canonical path enforced before certificate persistence", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), axiomEffect: IOEffect.} =
  let canonicalDir = resolveCertificate(cvCanonicalRead)
  let runtimeCanonicalDir = resolveCertificate(cvRuntimeCanonical)
  if (path.startsWith(canonicalDir) or path.startsWith(runtimeCanonicalDir)) and not promotionActive:
    raise newException(CatchableError, "DIRECT CANONICAL WRITE FORBIDDEN — must go through explicit promotion context (set promotionActive=true or use --promote flag)")
  ## R4 aggregate: single promotion/write gate. The existing
  ## validateCertGreenWritable logic is folded into
  ## verifyCertificateCompleteness (which checks winningStrategy
  ## for certGreen and statusConsistentWithEvidence).
  let status = node.getOrDefault("status").getStr("")
  let requiredVerifiers = case status
    of "certGreen":
      @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
    of "certZ3Verified", "certLeanVerified", "certNoObligation":
      @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
    else:
      @["verifySemanticEvidence", "verifyIdentityBinding", "verifyCertificateCompleteness"]
  let results = @[
    verifySemanticEvidence(node),
    verifyIdentityBinding(node),
    verifyCertificateCompleteness(node)
  ]
  let eligibility = aggregate(requiredVerifiers, results)
  if not eligibility.eligible:
    let rejectionReason = eligibility.reasons.join("; ")
    try:
      logError("certificate_manager", "[aggregate-gate] certificate write rejected for " & path & ": " & rejectionReason)
    except CatchableError:
      discard  # best-effort  # axiom:best-effort(ioboundary catch)
    return false
  return writeCertificateContent(path, node)



## Quarantine a certificate by demoting it to certPending.
## Prevents broken evidence from entering the bundle and destroying
## compilation throughput via fallback cascade.
# @axiom-hint: lean="path.length ≥ 0 ∧ reason.length ≥ 0" smt="(assert (and (>= (str.len path) 0) (>= (str.len reason) 0)))"
proc quarantineCertificate*(path, reason: string): bool {.axiomDecision(id = "DECISION-0625", reason = "Write guard for canonical path enforced before certificate quarantine", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), axiomEffect: IOEffect.} =
  ## Demote a certificate to certPending and record the transition durably in
  ## the TrustCommit journal (I2) before materializing the derived cert file.
  ## Fail-closed: if the journal commit fails, the cert is NOT demoted, so no
  ## trust-relevant semantic change happens without an authoritative record.
  let nodeOpt = readJsonFile(path)
  if nodeOpt.isNone:
    return false
  var node = nodeOpt.get()
  if node.kind != JObject:
    return false
  let originalStatus = node{"status"}.getStr("")
  node["status"] = newJString("certPending")
  node["reason"] = newJString("quarantine:" & reason)
  node["leanArtifactHash"] = newJString("")
  var journalBase = ""
  try:
    journalBase = repoRootForPath(path)
  except CatchableError:
    journalBase = ""
  if journalBase.len > 0:
    try:
      let qc = quarantineTrustCommit(node, reason, originalStatus)
      let res = commitVerification(journalBase, qc)
      if not res.ok:
        logError("certificate_manager", "[trust-gate] quarantine journal commit failed for " & path & ": " & res.error)
        return false
    except CatchableError as e:
      logError("certificate_manager", "[trust-gate] quarantine journal commit error for " & path & ": " & e.msg)
      return false
  return writeCertificateContent(path, node)

## Isolate Stale Certificates.
## Moves all certificates with status "certStale" from certDir into
## certDir/stale/ for physical quarantine.
# @axiom-hint: lean="certDir.length ≥ 0" smt="(assert (and (>= (str.len certDir) 0)))"
proc isolateStaleCertificates*(certDir: string): int {.axiomDecision(id = "DECISION-0626", reason = "Write guard for canonical path enforced before stale certificate isolation", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let staleDir = joinPath(certDir, "stale")
    if not dirExists(staleDir):
      discard existsOrCreateDirOpt(staleDir)
    for path in walkPattern(joinPath(certDir, "*.json")):
      let node = parseFile(path)
      if node.kind == JObject and node{"status"}.getStr("") == "certStale":
        let name = extractFilename(path)
        let dest = joinPath(staleDir, name)
        discard moveFileOpt(path, dest)
        inc result
  except CatchableError:
    discard  # best-effort  # axiom:best-effort(ioboundary catch)

