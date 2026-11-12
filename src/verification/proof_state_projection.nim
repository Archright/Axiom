import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/trusted/axiom_pragmas
import core/types/verification_tier
import core/utils/constants
import core/json/json_utils
import core/json/std_redirect
import std/options
import std/os
import std/strutils
import std/tables
# axiomIoBoundary

type
  CertificateProjection* = object
    path*: string
    label*: string
    modulePath*: string
    functionName*: string
    status*: string
    node*: JsonNode
const
  certifiedExemptProofStateStatus* = "certified_exempt"
  certifiedExemptReasonPrefix = "certified-exempt:"
  certifiedExemptSourceReason = "axiom-pure-or-vacuous-primitive"
func normalizedSlashPath(value: string): string {.raises: [].} =
  value.replace("\\", "/")
func proofStateLabelFromModuleFunction*(modulePath, functionName: string): string {.raises: [].} =
  if modulePath.len == 0 or functionName.len == 0:
    return ""
  splitFile(modulePath).name & ".nim::" & functionName
func proofStateLabelFromEntry*(entry: JsonNode): string {.raises: [].} =
  if entry.isNil or entry.kind != JObject:
    return ""
  let explicitLabel = entry.getOrDefault(labelKey).getStr("")
  if explicitLabel.len > 0:
    return explicitLabel
  proofStateLabelFromModuleFunction(
    entry.getOrDefault(modulePathKey).getStr(""),
    entry.getOrDefault(functionNameKey).getStr("")
  )
func certificateStatusToProofStateStatus*(status: string): string {.raises: [].} =
  case status
  of "certGreen", "certVerifiedAxiom", "certIntrinsic", "certLeanVerified", "certDualVerified", verifiedKey:
    verifiedKey
  of "certPseudoVerified", "pseudo_verified":
    "pseudo_verified"
  # DECISION-0630: unsat candidate evidence projects to the honest candidate
  # state — never "unknown" (erasure) and never counter_example_found
  # (SAT-only). certZ3Verified is the legacy spelling, canonicalized to
  # certZ3Candidate on read (test_evidence_truth_boundary migration rule).
  of "certZ3Candidate", "certZ3Verified":
    "z3_candidate"
  of "certStale":
    "certStale"
  of "certPending", "pending":
    unattemptedKey
  of "certYellow", "yellow", "bounded":
    "partially_verified"
  of "certNoObligation", "no_obligation":
    "no_obligation"
  of "certRed", "red", "failed":
    "counter_example_found"
  of "timed_out":
    timedOutKey
  else:
    "unknown"
func isCertifiedExemptProofStateEntry*(entry: JsonNode): bool {.raises: [].} =
  if entry.isNil or entry.kind != JObject:
    return false
  if entry.getOrDefault(statusKey).getStr("") != certifiedExemptProofStateStatus:
    return false
  let reason = entry.getOrDefault(reasonKey).getStr("")
  let exemptionReason = entry.getOrDefault("exemptionReason").getStr("")
  reason.startsWith(certifiedExemptReasonPrefix) or
    exemptionReason == certifiedExemptSourceReason
func proofStateEntryConvergesWithCertificate*(
  entry: JsonNode;
  projection: CertificateProjection
): bool {.raises: [].} =
  if entry.isNil or entry.kind != JObject:
    return false
  let expected = certificateStatusToProofStateStatus(projection.status)
  if expected.len == 0 or expected == "unknown":
    return false
  let actual = entry.getOrDefault(statusKey).getStr("")
  if actual == expected:
    return true
  expected == verifiedKey and isCertifiedExemptProofStateEntry(entry)
func sourceScopePrefix(proofState: JsonNode): string {.raises: [].} =
  if proofState.isNil or proofState.kind != JObject:
    return ""
  let raw = normalizedSlashPath(proofState.getOrDefault(sourceRootKey).getStr(""))
  if raw.len == 0 or raw.endsWith("/src"):
    return ""
  let marker = "/src/"
  let idx = raw.rfind(marker)
  if idx < 0:
    return ""
  let suffix = raw[(idx + marker.len) .. ^1].strip(chars = {'/'})
  if suffix.len == 0:
    return ""
  suffix & "/"
func certificateInProofStateScope(node: JsonNode; scopePrefix: string): bool {.raises: [].} =
  if scopePrefix.len == 0:
    return true
  normalizedSlashPath(node.getOrDefault(modulePathKey).getStr("")).startsWith(scopePrefix)
proc loadCertificateProjection(path: string): Option[CertificateProjection] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let nodeOpt = readJsonFile(path)
  if nodeOpt.isNone:
    return none(CertificateProjection)
  let node = nodeOpt.get()
  if node.kind != JObject:
    return none(CertificateProjection)
  let modulePath = normalizedSlashPath(node.getOrDefault(modulePathKey).getStr(""))
  let functionName = node.getOrDefault(functionNameKey).getStr("")
  let label = proofStateLabelFromModuleFunction(modulePath, functionName)
  if label.len == 0:
    return none(CertificateProjection)
  some(CertificateProjection(
    path: path,
    label: label,
    modulePath: modulePath,
    functionName: functionName,
    status: node.getOrDefault(statusKey).getStr(""),
    node: node
  ))
proc loadCertificateProjections*(
  certDir: string;
 proofState: JsonNode = nil
): Table[string, CertificateProjection] {.raises: [].} =
  if certDir.len == 0 or not dirExists(certDir):
    return
  let scopePrefix = sourceScopePrefix(proofState)
  var existingLabels: Table[string, bool]
  if not proofState.isNil and proofState.kind == JObject:
    let entries = proofState.getOrDefault(entriesKey)
    if not entries.isNil and entries.kind == JArray:
      for entry in entries.elems:
        let label = proofStateLabelFromEntry(entry)
        if label.len > 0:
          existingLabels[label] = true
  try:
    for path in walkPattern(joinPath(certDir, "*.json")):
      let projectionOpt = loadCertificateProjection(path)
      if projectionOpt.isNone:
        continue
      let projection = projectionOpt.get()
      if certificateInProofStateScope(projection.node, scopePrefix) or
          existingLabels.hasKey(projection.label):
        result[projection.label] = projection
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
proc certificateStatusByLabel*(
  certDir: string;
 proofState: JsonNode = nil
): Table[string, string] {.raises: [].} =
  let projections = loadCertificateProjections(certDir, proofState)
  for label, projection in projections:
    result[label] = projection.status
func jsonBoolField(node: JsonNode; key: string): bool {.raises: [].} =
  if node.isNil or node.kind != JObject:
    return false
  let value = node.getOrDefault(key)
  if value.isNil:
    return false
  value.kind == JBool and value.getBool()
func jsonStringField(node: JsonNode; key: string): string {.raises: [].} =
  if node.isNil or node.kind != JObject:
    return ""
  let value = node.getOrDefault(key)
  if value.isNil:
    return ""
  if value.kind == JString:
    return value.getStr().strip()
  ""
func hasSubstantiveProofStateEvidence*(entry: JsonNode): bool {.raises: [].} =
  ## Validates that proof state entry has genuine evidence (leanCompilerVerified,
  ## negativeTestResult, evidencePath, negativeEvidencePath).
  ## Provenance guard applied in applyProofStateSyncStatus to prevent NoObligation
  ## laundering — proof state entries lack solverProvenance, so check happens
  ## at the certificate node level during status sync.
  jsonBoolField(entry, "leanCompilerVerified") and
    jsonBoolField(entry, "negativeTestResult") and
    jsonStringField(entry, "evidencePath").len > 0 and
    jsonStringField(entry, "negativeEvidencePath").len > 0

func isNoObligationDerived*(entry: JsonNode): bool {.raises: [].} =
  ## Detects NoObligation-derived artifacts by checking provenance markers.
  ## Used as a guard against certYellow→certGreen upgrades where provenance
  ## would otherwise be lost.
  let prover = jsonStringField(entry, "solverProvenance")
  if prover == "spNoObligation":
    return true
  let solverMeta = entry.getOrDefault("solverMeta")
  if solverMeta.isNil or solverMeta.kind != JObject:
    return false
  solverMeta.getOrDefault("solverProvenance").getStr("") == "spNoObligation"

func tierToCertStatusString(tier: VerificationTier): string {.raises: [].} =
  ## Mirrors cert_writer.tierToStatusString — the canonical dual-assurance
  ## status is certGreen; Z3-only is certZ3Verified (never certGreen). Kept
  ## local to preserve {.raises: [].} (cert_writer's mapping raises
  ## CatchableError under its module push).
  case tier
  of vtDual: "certGreen"
  of vtZ3Only: "certZ3Verified"
  of vtLeanOnly: "certLeanVerified"
  of vtNone: "certRed"
  of vtKInduction: "certZ3Verified"
  of vtUfAbstract: "certLeanVerified"

func applyProofStateSyncStatus*(node: var JsonNode; substantive: bool) {.raises: [].} =
  ## Applies status sync from proof state to certificate node.
  ## Provenance guard: NoObligation-derived certificates (spNoObligation) are
  ## NOT upgraded to certGreen, preventing vacuous skip laundering per §0.9.
  ## P0 (verification_density.md): certGreen is only legitimate when the stored
  ## evidence is dual (z3Passed ∧ leanVerified). Status is derived from the
  ## canonical evidence chain (certificateEvidenceFromJson → tierFromEvidence),
  ## never from a substantive flag alone — so a Lean-only/ambiguous artifact
  ## cannot overclaim dual assurance (no hand-rolled existence checks here).
  if substantive and not isNoObligationDerived(node):
    let tier = tierFromEvidence(certificateEvidenceFromJson(node))
    if tier == vtDual:
      node[statusKey] = newJString("certGreen")
      node[reasonKey] = newJString("proof-state-kernel-replay")
      if node.getOrDefault("winningStrategy").getStr("").len == 0:
        node["winningStrategy"] = newJString("lean-replay")
    else:
      # Evidence does not support dual assurance — assign the honest tier status
      # (certZ3Verified / certLeanVerified / certRed) instead of overclaiming.
      node[statusKey] = newJString(tierToCertStatusString(tier))
      node[reasonKey] = newJString("proof-state-sync-evidence-derived")
  else:
    node[statusKey] = newJString("certPseudoVerified")
    node[reasonKey] = newJString("proof-state-sync-missing-kernel-negative-test")
    node[trustedKey] = newJBool(false)
func applyCertificateProjection*(
  entry: JsonNode;
  projection: CertificateProjection
): bool {.raises: [].} =
  if entry.isNil or entry.kind != JObject:
    return false
  let mappedStatus = certificateStatusToProofStateStatus(projection.status)
  if mappedStatus.len == 0 or mappedStatus == "unknown":
    return false
  if entry.getOrDefault(statusKey).getStr("") != mappedStatus and
      not (mappedStatus == verifiedKey and isCertifiedExemptProofStateEntry(entry)):
    entry[statusKey] = newJString(mappedStatus)
    result = true
  entry["certificateStatus"] = newJString(projection.status)
  entry["certificatePath"] = newJString(projection.path)
  let reason = projection.node.getOrDefault(reasonKey).getStr("")
  if reason.len > 0:
    entry[reasonKey] = newJString(reason)
  let strategy = projection.node.getOrDefault(strategyKey).getStr("")
  let winningStrategy = projection.node.getOrDefault("winningStrategy").getStr("")
  if strategy.len > 0:
    entry[strategyKey] = newJString(strategy)
  if winningStrategy.len > 0:
    entry["winningStrategy"] = newJString(winningStrategy)
  entry["attempted"] = newJBool(mappedStatus != unattemptedKey)
func proofStateEntryFromCertificate*(projection: CertificateProjection): JsonNode {.raises: [].} =
  let mappedStatus = certificateStatusToProofStateStatus(projection.status)
  result = %*{
    nodeIdKey: projection.modulePath & "::" & projection.functionName,
    labelKey: projection.label,
    modulePathKey: projection.modulePath,
    functionNameKey: projection.functionName,
    statusKey: mappedStatus,
    "attempted": mappedStatus != unattemptedKey,
    "certificateStatus": projection.status,
    "certificatePath": projection.path
  }
  let reason = projection.node.getOrDefault(reasonKey).getStr("")
  if reason.len > 0:
    result[reasonKey] = newJString(reason)
  let winningStrategy = projection.node.getOrDefault("winningStrategy").getStr("")
  if winningStrategy.len > 0:
    result["winningStrategy"] = newJString(winningStrategy)
  if winningStrategy.len > 0:
    result["winningStrategy"] = newJString(winningStrategy)
{.pop.}
