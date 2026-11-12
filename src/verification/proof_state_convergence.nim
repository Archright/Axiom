import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/axiom_pragmas
import core/utils/constants
import core/json/json_utils
import core/json/std_redirect
import std/options
import std/os
import std/tables
import verification/certificate_manager
import verification/proof_state_projection
import verification/state_manager
type
  ProofStateConvergenceReport* = object
    ok*: bool
    checkedCertificates*: int
    matchedCertificates*: int
    missingStateEntries*: int
    mismatchedStatuses*: int
    detail*: string

proc syncCertificatesWithProofState*(proofStateNode: JsonNode; certDir: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [IOEffect, TimeEffect, RootEffect].} =
  ## Reconciles only explicit verified proof-state entries into matching
  ## certificates. Absence from the transient proof-state is not evidence that a
  ## disk certificate is stale; disk certificates are the read-side SSOT.
  if certDir.len == 0 or not dirExists(certDir):
    return
  if proofStateNode.isNil or proofStateNode.kind != JObject:
    return
  let entries = proofStateNode.getOrDefault(entriesKey)
  if entries.isNil or entries.kind != JArray:
    return

  var verifiedLabels = initTable[string, bool]()
  for entry in entries.elems:
    if entry.kind != JObject:
      continue
    if entry.getOrDefault(statusKey).getStr("") != verifiedKey:
      continue
    let label = proofStateLabelFromEntry(entry)
    if label.len > 0:
      verifiedLabels[label] = hasSubstantiveProofStateEvidence(entry)

  if verifiedLabels.len == 0:
    return

  let projections = loadCertificateProjections(certDir, proofStateNode)
  for label, substantive in verifiedLabels:
    if not projections.hasKey(label):
      continue
    let projection =
      try:
        projections[label]
      except KeyError:
        continue
    var node = projection.node
    let currentStatus = node.getOrDefault(statusKey).getStr("")
    if currentStatus in ["certPending", "certStale", "certRed", "certYellow", "pending"]:
      applyProofStateSyncStatus(node, substantive)
      if not writeCertificate(projection.path, node):
        discard  # write failure is non-fatal; {.raises: [].} prevents stderr logging
func markConvergenceMetadata(
  proofState: var JsonNode;
  checkedCertificates, matchedCertificates: int
) {.raises: [].} =
  if proofState.isNil or proofState.kind != JObject:
    return
  var metadata = proofState.getOrDefault("metadata")
  if metadata.isNil or metadata.kind != JObject:
    metadata = newJObject()
    proofState["metadata"] = metadata
  metadata["certificateConvergence"] = %*{
    "source": "disk-certificates",
    "checkedCertificates": checkedCertificates,
    "matchedCertificates": matchedCertificates
  }
proc convergeProofStateWithCertificates*(
  proofState: var JsonNode;
  certDir: string
): int {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if proofState.isNil or proofState.kind != JObject:
    return 0
  var entries = proofState.getOrDefault(entriesKey)
  if entries.isNil or entries.kind != JArray:
    entries = newJArray()
    proofState[entriesKey] = entries

  let projections = loadCertificateProjections(certDir, proofState)
  var indexByLabel = initTable[string, int]()
  for idx, entry in entries.elems:
    let label = proofStateLabelFromEntry(entry)
    if label.len > 0 and not indexByLabel.hasKey(label):
      indexByLabel[label] = idx

  var matched = 0
  for label, projection in projections:
    if indexByLabel.hasKey(label):
      inc matched
      let entryIndex =
        try:
          indexByLabel[label]
        except KeyError:
          continue
      if applyCertificateProjection(entries[entryIndex], projection):
        inc result
    else:
      entries.add(proofStateEntryFromCertificate(projection))
      inc result

  markConvergenceMetadata(proofState, projections.len, matched)
  discard recomputeProofStateSummary(proofState)
proc synchronizeAndRenderUniverse*(
  proofState: var JsonNode;
  certDir: string
): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  syncCertificatesWithProofState(proofState, certDir)
  convergeProofStateWithCertificates(proofState, certDir)

# @axiom-hint: lean="repoRoot.length ≥ 0 ∧ certDirOverride.length ≥ 0 ∧ statePathOverride.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len repoRoot) 0) (>= (str.len certDirOverride) 0) (>= (str.len statePathOverride) 0) external_io_isolated))"
proc validateProofStateCertificateConvergence*(
  repoRoot: string;
 certDirOverride: string = "";
  statePathOverride: string = ""
): ProofStateConvergenceReport {.raises: [].} =
  let statePath =
    if statePathOverride.len > 0:
      statePathOverride
    else:
      joinPath(repoRoot, "logs", "ax_proof_state.json")
  if not fileExists(statePath):
    return ProofStateConvergenceReport(ok: true, detail: "proof-state-missing")
  let stateOpt = readJsonFile(statePath)
  if stateOpt.isNone:
    return ProofStateConvergenceReport(ok: false, detail: "proof-state-unreadable")
  let proofState = stateOpt.get()
  let entries = proofState.getOrDefault(entriesKey)
  if entries.isNil or entries.kind != JArray:
    return ProofStateConvergenceReport(ok: false, detail: "proof-state-entries-missing")

  let certDir =
    if certDirOverride.len > 0:
      certDirOverride
    else:
      joinPath(repoRoot, defaultCertDir)
  let projections = loadCertificateProjections(certDir, proofState)
  var stateEntryByLabel = initTable[string, JsonNode]()
  for entry in entries.elems:
    let label = proofStateLabelFromEntry(entry)
    if label.len > 0:
      stateEntryByLabel[label] = entry

  result.checkedCertificates = projections.len
  for label, projection in projections:
    if not stateEntryByLabel.hasKey(label):
      inc result.missingStateEntries
      continue
    inc result.matchedCertificates
    let stateEntry =
      try:
        stateEntryByLabel[label]
      except KeyError:
        nil
    if not proofStateEntryConvergesWithCertificate(stateEntry, projection):
      inc result.mismatchedStatuses

  result.ok = result.missingStateEntries == 0 and result.mismatchedStatuses == 0
  if result.ok:
    result.detail = "converged"
  elif result.missingStateEntries > 0:
    result.detail = "missing-state-entries"
  else:
    result.detail = "status-mismatch"
{.pop.}
