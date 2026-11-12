import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Shadow CLI — Shadow execution mode.
##
## Run commands without side effects and compare output against expected results.
##
## Subcommands:
##   run <command...>            — execute in shadow mode (no side effects)
##   compare <a> <b>             — compare two output files
##   digest <analysisJson> <proofStateJson>
##                               — compute 6-dimension digests from artifacts
##   compare-digests <a.json> <b.json>
##                               — compare two digest-result JSON files
##
## Usage: ax shadow [run|compare|digest|compare-digests] [args...]

import std/os
import std/strutils
import std/json
import infrastructure/logging_facade
import core/axiom_pragmas
import core/utils/shadow_digests
import core/json/json_safe
import core/sorter/sorter_core
import core/types/results
import core/topology/topology_types
import core/topology/verified_set

proc shadowRun(command: seq[string]): int  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if command.len == 0:
    logInfo("shadow_cli", "[shadow] No command provided.")
    return 1
  echo "[shadow] Dry-run: " & command.join(" ")
  echo "[shadow] (no side effects executed)"
  return 0

proc shadowCompare(pathA, pathB: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(pathA):
    logInfo("shadow_cli", "[shadow] File not found: " & pathA)
    return 1
  if not fileExists(pathB):
    logInfo("shadow_cli", "[shadow] File not found: " & pathB)
    return 1
  let contentA = readFile(pathA)
  let contentB = readFile(pathB)
  if contentA == contentB:
    echo "[shadow] Outputs match."
    return 0
  else:
    echo "[shadow] Outputs differ."
    return 1

## Parse a JSON node into a SorterNodeId.
func parseSorterNodeId*(n: JsonNode): SorterNodeId {.raises: [].} =
  sorterNodeId(n.getStr())

## Parse a JSON object into a minimal SorterNode (only id + dependencyIds).
func parseSorterNode*(n: JsonNode): SorterNode {.raises: [].} =
  let idNode = n.getOrDefault("id")
  if idNode.kind != JNull:
    result.id = parseSorterNodeId(idNode)
  let depsNode = n.getOrDefault("dependencyIds")
  if depsNode.kind == JArray:
    for dep in depsNode.items:
      result.dependencyIds.add(parseSorterNodeId(dep))

## Parse a JSON object into a minimal TopologyAnalysis for digest computation.
## Only populates the fields needed by plannedQueueDigest and dependencyGraphDigest.
func parseTopologyAnalysis*(n: JsonNode): TopologyAnalysis {.raises: [].} =
  let vqNode = n.getOrDefault("verificationQueue")
  if vqNode.kind == JArray:
    for nid in vqNode.items:
      result.verificationQueue.add(parseSorterNodeId(nid))
  let stateNode = n.getOrDefault("state")
  if stateNode.kind == JObject:
    let nodesNode = stateNode.getOrDefault("nodes")
    if nodesNode.kind == JArray:
      for node in nodesNode.items:
        result.state.nodes.add(parseSorterNode(node))

## Parse a JSON array of uint64 into the raw bitset word list.
func parseVerifiedSetBits(n: JsonNode): seq[uint64] {.raises: [].} =
  ## Consumes the serialized backing words directly; no access to
  ## VerifiedSet's private `bits` field.
  if n.kind != JArray:
    return @[]
  var words: seq[uint64]
  for item in n.items:
    case item.kind
    of JInt: words.add(uint64(item.getInt()))
    of JString:
      try:
        words.add(uint64(parseBiggestUInt(item.getStr())))
      except ValueError:
        discard  # axiom:best-effort(non-numeric shadow field is ignored; parsing is best-effort, never fatal)
    else: discard
  words

proc shadowDigest(analysisPath, proofStatePath: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let analysisResult = safeParseJsonFile(analysisPath)
  if analysisResult.isErr():
    logInfo("shadow_cli", "[shadow] Failed to read analysis JSON: " & analysisResult.error)
    return 1
  let proofStateResult = safeParseJsonFile(proofStatePath)
  if proofStateResult.isErr():
    logInfo("shadow_cli", "[shadow] Failed to read proof state JSON: " & proofStateResult.error)
    return 1

  let analysisJson = analysisResult.get()
  let proofStateJson = proofStateResult.get()

  let analysis = parseTopologyAnalysis(analysisJson)
  let projection = projectionDigest(proofStateJson)
  let planned = plannedQueueDigest(analysis)
  let depGraph = dependencyGraphDigest(analysis)

  var obligationIds: seq[string]
  if analysisJson.hasKey("obligationIds") and analysisJson["obligationIds"].kind == JArray:
    for item in analysisJson["obligationIds"].items:
      obligationIds.add(item.getStr())
  let obligationList = obligationListDigest(obligationIds)

  var replayKeys: seq[string]
  if analysisJson.hasKey("solverReplayKeys") and analysisJson["solverReplayKeys"].kind == JArray:
    for item in analysisJson["solverReplayKeys"].items:
      replayKeys.add(item.getStr())
  let solverRun = solverRunDigest(replayKeys)

  let verifiedBits = parseVerifiedSetBits(analysisJson.getOrDefault("verifiedSetBits"))
  let verifiedSetDigest = verifiedSetBitsDigest(verifiedBits)

  let fingerprint = sixDimensionFingerprint(projection, planned, depGraph,
                                             obligationList, solverRun, verifiedSetDigest)

  echo "[shadow] projection:      " & projection
  echo "[shadow] planned:         " & planned
  echo "[shadow] dependencyGraph: " & depGraph
  echo "[shadow] obligationList:  " & obligationList
  echo "[shadow] solverRun:       " & solverRun
  echo "[shadow] verifiedSet:     " & verifiedSetDigest
  echo "[shadow] fingerprint:     " & fingerprint
  return 0

proc shadowCompareDigests(pathA, pathB: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(pathA):
    logInfo("shadow_cli", "[shadow] File not found: " & pathA)
    return 1
  if not fileExists(pathB):
    logInfo("shadow_cli", "[shadow] File not found: " & pathB)
    return 1

  let aResult = safeParseJsonFile(pathA)
  if aResult.isErr():
    logInfo("shadow_cli", "[shadow] Failed to parse " & pathA & ": " & aResult.error)
    return 1
  let bResult = safeParseJsonFile(pathB)
  if bResult.isErr():
    logInfo("shadow_cli", "[shadow] Failed to parse " & pathB & ": " & bResult.error)
    return 1

  let a = aResult.get()
  let b = bResult.get()

  let dims = ["projection", "planned", "dependencyGraph",
              "obligationList", "solverRun", "verifiedSet",
              "sixDimensionFingerprint"]
  var allMatch = true
  for dim in dims:
    let aVal = a.getOrDefault(dim)
    let bVal = b.getOrDefault(dim)
    if aVal.kind == JNull or bVal.kind == JNull:
      echo "[shadow] FAIL " & dim & ": missing key"
      allMatch = false
    elif aVal.getStr() == bVal.getStr():
      echo "[shadow] PASS " & dim
    else:
      echo "[shadow] FAIL " & dim & ": " & aVal.getStr()[0..min(16, aVal.getStr().len-1)] & " vs " & bVal.getStr()[0..min(16, bVal.getStr().len-1)]
      allMatch = false

  if allMatch:
    echo "[shadow] All dimensions match."
  else:
    echo "[shadow] Mismatch detected."
  return if allMatch: 0 else: 1

proc runShadowCli*(args: seq[string]): int =
  if args.len == 0:
    logInfo("shadow_cli", "Usage: ax shadow <command> [args]")
    logInfo("shadow_cli", "Commands: run <command...>, compare <file_a> <file_b>, digest <analysisJson> <proofStateJson>, compare-digests <a.json> <b.json>")
    return 1

  let cmd = args[0]
  case cmd
  of "run":
    return shadowRun(args[1 .. ^1])
  of "compare":
    if args.len < 3:
      logInfo("shadow_cli", "Usage: ax shadow compare <file_a> <file_b>")
      return 1
    return shadowCompare(args[1], args[2])
  of "digest":
    if args.len < 3:
      logInfo("shadow_cli", "Usage: ax shadow digest <analysisJson> <proofStateJson>")
      return 1
    return shadowDigest(args[1], args[2])
  of "compare-digests":
    if args.len < 3:
      logInfo("shadow_cli", "Usage: ax shadow compare-digests <a.json> <b.json>")
      return 1
    return shadowCompareDigests(args[1], args[2])
  else:
    logInfo("shadow_cli", "Unknown shadow subcommand: " & cmd)
    logInfo("shadow_cli", "Commands: run <command...>, compare <file_a> <file_b>, digest <analysisJson> <proofStateJson>, compare-digests <a.json> <b.json>")
    return 1
{.pop.}
