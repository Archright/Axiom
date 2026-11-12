## experiments/act2-wp4c-symbol-syntax-robustness/wp4c_frontier_localizer.nim
## — Act2-WP4c Frontier Localization Probe
##
## EXPERIMENT-ONLY instrument.
##   - NOT a canonical execution path
##   - NOT a production API
##   - NOT part of the shipped product / CLI
##   - NOT wired into the engine
##
## Determines the EXACT reason getBitsBE is excluded from computeVerifiedFrontier.
## Tests hypotheses H1–H4 against the REAL analysis pipeline.
##
## Usage: wp4c_frontier_localizer <subjectRoot> <outJsonPath>
## Exit: 0 always (regardless of stage statuses).

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, strutils, json, tables, sequtils, algorithm, options]
import cli/topology_cli
import core/topology/topology_engine
import core/topology/verified_frontier
import core/topology/verified_set
import core/topology/symbol_interning
import core/sorter/sorter_core
import core/proof/proof_integrity
import core/types/results
import core/boundary/boundary_extraction_types

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc canonicalJsonMinified*(n: JsonNode): string =
  if n == nil: return "null"
  case n.kind
  of JObject:
    var parts: seq[string] = @[]
    for k in n.keys:
      let v = n.getOrDefault(k)
      parts.add(escapeJson(k) & ":" & canonicalJsonMinified(v))
    parts.sort(cmp[string])
    result = "{" & parts.join(",") & "}"
  of JArray:
    var parts: seq[string] = @[]
    for it in n.items:
      parts.add(canonicalJsonMinified(it))
    result = "[" & parts.join(",") & "]"
  of JString:
    result = escapeJson(n.getStr())
  of JInt:
    result = $n.getInt()
  of JFloat:
    result = $n.getFloat()
  of JBool:
    result = if n.getBool(): "true" else: "false"
  of JNull:
    result = "null"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  let args = commandLineParams()
  if args.len < 2:
    stderr.writeLine("usage: wp4c_frontier_localizer <subjectRoot> <outJsonPath>")
    quit(2)
  let subjectRoot = args[0]
  let outJsonPath = args[1]

  var report = newJObject()
  report["experimentId"] = %"act2-wp4c-symbol-syntax-robustness"
  report["probeType"] = %"experiment-only"
  report["notCanonicalExecutionPath"] = %true
  report["notProductionAPI"] = %true

  # ── Step 1: Build the real topology analysis ──────────────────
  let analysisRes = analyzeTopologySourceRoot(subjectRoot)
  if analysisRes.isErr():
    report["error"] = %("analyzeTopologySourceRoot failed: " & analysisRes.error)
    let outDir = parentDir(outJsonPath)
    if outDir != "" and not outDir.dirExists:
      outDir.createDir
    writeFile(outJsonPath, canonicalJsonMinified(report))
    quit(0)
  let bundle = analysisRes.get()
  let analysis = bundle.analysis

  # ── Step 2: Build internPool from analysis.state.nodes ────────
  var internPool = initInternPool(analysis.state.nodes.len)
  for node in analysis.state.nodes:
    discard nodeIdForSorter(internPool, node.id)
  let internSnapshot = freezeInternPool(internPool)

  # ── Step 3: Build empty verified set ──────────────────────────
  let emptyVerified = initVerifiedSet(analysis.state.nodes.len)

  # ── Step 4: Build empty kernel scope ──────────────────────────
  let emptyScope = KernelScopeInfo(
    kernelSymbols: @[],
    kernelExemptSymbols: @[]
  )

  # ── Step 5: Call computeVerifiedFrontier with subjectMode=true ─
  let frontierSubjectMode = computeVerifiedFrontier(
    analysis, emptyVerified, internSnapshot, 0, emptyScope, subjectMode = true)

  # ── Step 6: Call computeVerifiedFrontier with subjectMode=false ─
  let frontierSelfMode = computeVerifiedFrontier(
    analysis, emptyVerified, internSnapshot, 0, emptyScope, subjectMode = false)

  # ── Step 7: Check getBitsBE in verificationQueue ──────────────
  let targetNodeId = sorterNodeId("stew/bitops2.nim::getBitsBE")
  let targetNodeIdStr = sorterNodeIdString(targetNodeId)

  var inQueue = false
  var queueCount = 0
  for qid in analysis.verificationQueue:
    if sorterNodeIdString(qid) == targetNodeIdStr:
      inQueue = true
    queueCount += 1

  # ── Step 8: Find getBitsBE node in analysis.state.nodes ───────
  var nodeIdx = -1
  var nodeType = ""
  var depIds: seq[string] = @[]
  for idx, node in analysis.state.nodes:
    if sorterNodeIdString(node.id) == targetNodeIdStr:
      nodeIdx = idx
      nodeType = node.nodeType
      for dep in node.dependencyIds:
        depIds.add(sorterNodeIdString(dep))
      break

  # ── Step 9: Check each dependency resolution ──────────────────
  var depReport = newJObject()
  var allDepsResolved = true
  var allDepsInVerified = true
  var resolvedDepCount = 0
  var unresolvedDepCount = 0
  var verifiedDepCount = 0
  var unverifiedDepCount = 0

  for depStr in depIds:
    let depOpt = nodeIdForSorter(internSnapshot, sorterNodeId(depStr))
    var depEntry = newJObject()
    depEntry["depNodeId"] = %depStr
    if depOpt.isNone:
      depEntry["resolved"] = %false
      depEntry["inInternPool"] = %false
      allDepsResolved = false
      unresolvedDepCount += 1
    else:
      let depNodeId = depOpt.get()
      depEntry["resolved"] = %true
      depEntry["inInternPool"] = %true
      depEntry["inVerifiedSet"] = %emptyVerified.contains(depNodeId)
      if emptyVerified.contains(depNodeId):
        verifiedDepCount += 1
      else:
        allDepsInVerified = false
        unverifiedDepCount += 1
      resolvedDepCount += 1
    depReport[depStr] = depEntry

  depReport["totalDependencies"] = %depIds.len
  depReport["resolvedCount"] = %resolvedDepCount
  depReport["unresolvedCount"] = %unresolvedDepCount
  depReport["verifiedCount"] = %verifiedDepCount
  depReport["unverifiedCount"] = %unverifiedDepCount
  depReport["allDependenciesResolved"] = %allDepsResolved
  depReport["allDependenciesInVerified"] = %allDepsInVerified

  # ── Step 10: Check if getBitsBE is in each frontier ───────────
  var inFrontierSubject = false
  var inFrontierSelf = false
  for fid in frontierSubjectMode:
    if sorterNodeIdString(fid) == targetNodeIdStr:
      inFrontierSubject = true
  for fid in frontierSelfMode:
    if sorterNodeIdString(fid) == targetNodeIdStr:
      inFrontierSelf = true

  # ── Step 11: Frontier size and sample ─────────────────────────
  var frontierSubjectIds: seq[string] = @[]
  for fid in frontierSubjectMode:
    frontierSubjectIds.add(sorterNodeIdString(fid))
  var frontierSelfIds: seq[string] = @[]
  for fid in frontierSelfMode:
    frontierSelfIds.add(sorterNodeIdString(fid))

  # ── Step 12: Check if getBitsBE is already verified ───────────
  # With empty verified set, it cannot be. This tests H3.
  let alreadyVerified = emptyVerified.contains(
    nodeIdForSorter(internSnapshot, targetNodeId).get())

  # ── Step 13: H4 test — simulate non-empty kernel scope ────────
  # If externalSubjectMode is false in the real run, the kernel
  # scope gate would apply. We test with a scope that does NOT
  # include getBitsBE.
  var kernelScopeExcluding = KernelScopeInfo(
    kernelSymbols: @["stew/base36.nim::encodedLength"],
    kernelExemptSymbols: @[]
  )

  let frontierWithScope = computeVerifiedFrontier(
    analysis, emptyVerified, internSnapshot, 0, kernelScopeExcluding,
    subjectMode = false)
  var inFrontierWithScope = false
  for fid in frontierWithScope:
    if sorterNodeIdString(fid) == targetNodeIdStr:
      inFrontierWithScope = true

  # ── Assemble report ────────────────────────────────────────────
  report["targetNodeId"] = %targetNodeIdStr
  report["inVerificationQueue"] = %inQueue
  report["verificationQueueLength"] = %queueCount
  report["nodeIndex"] = %nodeIdx
  report["nodeType"] = %nodeType
  report["dependencyIds"] = %depIds
  report["dependencyReport"] = depReport
  report["frontierSubjectModeLength"] = %frontierSubjectMode.len
  report["frontierSubjectModeContainsTarget"] = %inFrontierSubject
  report["frontierSelfModeContainsTarget"] = %inFrontierSelf
  report["alreadyVerified"] = %alreadyVerified
  report["scopeGateReport"] = %*{
    "emptyScope_subjectMode_true_containsTarget": %inFrontierSubject,
    "emptyScope_subjectMode_false_containsTarget": %inFrontierSelf,
    "nonEmptyScope_excludingTarget_subjectMode_false_containsTarget": %inFrontierWithScope,
    "nonEmptyScope_excludingTarget_subjectMode_false_frontierSize": %frontierWithScope.len
  }

  # ── Hypothesis verdict ────────────────────────────────────────
  var hypotheses = newJObject()
  if not inQueue:
    hypotheses["H1"] = %"CONFIRMED — getBitsBE NOT in analysis.verificationQueue"
  else:
    hypotheses["H1"] = %"REJECTED — getBitsBE IS in analysis.verificationQueue"

  if inQueue:
    if not allDepsResolved:
      hypotheses["H2"] = %"CONFIRMED — some dependencyId maps to None via nodeIdForSorter"
    elif not allDepsInVerified:
      hypotheses["H2"] = %"CONFIRMED — a dependency is not in the verified set"
    else:
      hypotheses["H2"] = %"REJECTED — all dependencies resolve and are in verified set"
  else:
    hypotheses["H2"] = %"NOT TESTED — getBitsBE not in queue"

  hypotheses["H3"] = %"REJECTED — verified set is empty, getBitsBE cannot be pre-verified"

  if not inFrontierSubject and inFrontierSelf:
    hypotheses["H4"] = %"CONFIRMED — subjectMode=false (kernel scope gate) excludes getBitsBE"
  elif inFrontierSubject:
    hypotheses["H4"] = %"REJECTED — subjectMode=true includes getBitsBE in frontier"
  else:
    hypotheses["H4"] = %"INCONCLUSIVE — getBitsBE excluded even with subjectMode=true"

  report["hypotheses"] = hypotheses

  let outDir = parentDir(outJsonPath)
  if outDir != "" and not outDir.dirExists:
    outDir.createDir
  try:
    writeFile(outJsonPath, canonicalJsonMinified(report))
  except CatchableError as e:
    stderr.writeLine("cannot write output: " & e.msg)
    quit(1)
  quit(0)
