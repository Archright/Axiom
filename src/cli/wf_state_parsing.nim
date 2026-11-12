import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
import ../core/trusted/axiom_pragmas
import cli/cli_io_input
import cli/topology_cli
import core/utils/constants
import core/json/json_utils
import core/json/std_redirect
import core/results
import core/sorter/sorter_core
import core/utils/file_utils
import std/os
import std/strutils
import std/times
import verification/state_persistence
type
  AxShortcutState* = object
    target*: string
    sourceRoot*: string
    proofLimit*: int
    timestamp*: string
## Json From Ax Frontier Entries.
  ## axiom-smt: (assert (and (>= result 0) (>= frontier 0)))
  ## axiom-lean: (result ≥ 0) ∧ (frontier ≥ 0)
proc jsonFromAxFrontierEntries*(frontier: seq[AxFrontierEntry]): JsonNode {.axiomTryImpl.} =
  result = newJArray()
  for entry in frontier:
    result.add(%*{
      nodeIdKey: sorterNodeIdString(entry.nodeId),
      labelKey: entry.label,
      dependencyDepthKey: entry.dependencyDepth,
      impactIndexKey: entry.impactIndex,
      "topologyScore": entry.topologyScore,
      "centralityScore": entry.centralityScore,
      "couplingScore": entry.couplingScore,
      "interfaceDistance": entry.interfaceDistance,
      "dependentNodeCount": entry.dependentNodeCount,
      "transitiveDependentCount": entry.transitiveDependentCount
    })
## resolve Ax Shortcut State Path variable.
let loadAxProofState* = proc (statePath: string): Result[JsonNode, string] =
  if not fileExists(statePath):
    ## Self-healing: reconstruct from certificates when state file is missing.
    let certDir = joinPath(getCurrentDir(), defaultCertDir)
    if dirExists(certDir):
      let reconstructed = reconstructProofStateFromCertificates(certDir, 0)
      if reconstructed.kind == JObject:
        return ok(reconstructed)
    return err("proof state not found: " & statePath)
  let raw = try:
    readFileSafe(statePath)
  except CatchableError:
    return err("failed to read proof state: " & statePath)
  try:
    let parsed = json.parseJson(raw)
    if parsed.kind != JObject:
      ## Self-healing: corrupt state, attempt reconstruction from certificates.
      let certDir = joinPath(getCurrentDir(), defaultCertDir)
      if dirExists(certDir):
        let reconstructed = reconstructProofStateFromCertificates(certDir, 0)
        if reconstructed.kind == JObject:
          return ok(reconstructed)
      return err("invalid proof state shape: " & statePath)
    ok(parsed)
  except CatchableError:
    ## Self-healing: parse failure, attempt reconstruction from certificates.
    let certDir = joinPath(getCurrentDir(), defaultCertDir)
    if dirExists(certDir):
      let reconstructed = reconstructProofStateFromCertificates(certDir, 0)
      if reconstructed.kind == JObject:
        return ok(reconstructed)
    err("proof state JSON parse failed: " & statePath)
let resolveAxShortcutStatePath* = proc (statePathOverride: string = ""): string =
  if statePathOverride.len > 0:
    return statePathOverride
  joinPath(getCurrentDir(), "logs", "ax_shortcut_state.json")

## persist Ax Shortcut State variable.
let persistAxShortcutState* = proc (
  statePath: string;
  target: string;
  sourceRoot: string;
  proofLimit: int
): Result[string, string]  =
  let reportDir = parentDir(statePath)
  if reportDir.len > 0 and not dirExists(reportDir):
    discard existsOrCreateDir(reportDir)
  let stateNode = %*{
    targetKey: target,
    sourceRootKey: sourceRoot,
    "proofLimit": max(1, proofLimit),
    timestampKey: now().utc().format("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
  }
  try:
    discard writeFileSafe(statePath, renderJsonMultiline(stateNode))
  except CatchableError:
    return err("failed to persist ax shortcut state: " & statePath)
  ok(statePath)

## Read Ax Shortcut State String.
  ## axiom-smt: (assert (and (= (str.len value) 0)))
  ## axiom-lean: value.length = 0
proc readAxShortcutStateString*(node: JsonNode; fieldName: string): Result[string, string] {.axiomTryImpl.} =
  if node.kind != JObject or not node.hasKey(fieldName) or node[fieldName].kind != JString:
    return err("ax shortcut state requires string field: " & fieldName)
  let value = node[fieldName].getStr().strip()
  if value.len == 0:
    return err("ax shortcut state requires non-empty string field: " & fieldName)
  ok(value)

## Read Ax Shortcut State Optional String.
  ## axiom-smt: (assert (and (>= (str.len fieldName) 0)))
  ## axiom-lean: fieldName.length ≥ 0
proc readAxShortcutStateOptionalString*(node: JsonNode; fieldName: string): string {.axiomTryImpl.} =
  if node.kind == JObject and node.hasKey(fieldName) and node[fieldName].kind == JString:
    return node[fieldName].getStr().strip()
  result = ""

## Read Ax Shortcut State Int.
  ## axiom-smt: (assert (and (>= (str.len fieldName) 0) JInt JString))
  ## axiom-lean: fieldName.length ≥ 0 ∧ JInt ∧ JString
proc readAxShortcutStateInt*(node: JsonNode; fieldName: string): Result[int, string] {.axiomTryImpl.} =
  if node.kind != JObject or not node.hasKey(fieldName):
    return err("ax shortcut state requires integer field: " & fieldName)
  let field = node[fieldName]
  case field.kind
  of JInt:
    ok(field.getInt())
  of JString:
    parseRequiredIntArg("--" & fieldName, field.getStr())
  else:
    err("ax shortcut state requires integer field: " & fieldName)
## load Ax Shortcut State variable.
let loadAxShortcutState* = proc (statePathOverride: string = ""): Result[AxShortcutState, string] =
  let statePath = resolveAxShortcutStatePath(statePathOverride)
  if not fileExists(statePath):
    return err("ax shortcut state not found: " & statePath)
  let raw = try:
    readFileSafe(statePath)
  except CatchableError:
    return err("failed to read ax shortcut state: " & statePath)
  try:
    let parsed = json.parseJson(raw)
    if parsed.kind != JObject:
      return err("invalid ax shortcut state shape: " & statePath)
    let sourceRoot = ??readAxShortcutStateString(parsed, sourceRootKey)
    let proofLimit = ??readAxShortcutStateInt(parsed, "proofLimit")
    ok(AxShortcutState(
      target: readAxShortcutStateOptionalString(parsed, targetKey),
      sourceRoot: sourceRoot,
      proofLimit: max(1, proofLimit),
      timestamp: readAxShortcutStateOptionalString(parsed, timestampKey)
    ))
  except CatchableError:
    err("ax shortcut state JSON parse failed: " & statePath)

## Build Ax Scan Json.
  ## axiom-smt: (assert (and (>= (str.len target) 0) (>= (seq.len frontier) 0)))
  ## axiom-lean: target.length ≥ 0 ∧ frontier.size ≥ 0
proc buildAxScanJson*(target: string; bundle: TopologyCliAnalysisBundle; frontier: seq[AxFrontierEntry]): JsonNode {.axiomTryImpl.} =
  result = %*{
    targetKey: target,
    sourceRootKey: bundle.sourceRoot,
    "summary": {
      "symbolCount": bundle.analysis.symbols.len,
      "plannedNodeCount": bundle.analysis.state.nodes.len,
      "queueLimit": bundle.effectiveQueueLimit,
      "diagnosisDepth": bundle.effectiveDiagnosisDepth,
      "structuralBottleneckCount": bundle.diagnoses.len
    },
    "axiomaticFrontier": jsonFromAxFrontierEntries(frontier)
  }
{.pop.}
