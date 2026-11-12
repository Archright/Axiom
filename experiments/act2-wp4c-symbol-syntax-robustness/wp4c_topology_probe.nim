## experiments/act2-wp4c-symbol-syntax-robustness/wp4c_topology_probe.nim
## — Act2-WP4c Topology Boundary Probe (canonical reproduction)
##
## EXPERIMENT-ONLY instrument.
##   - NOT a canonical execution path
##   - NOT a production API
##   - NOT part of the shipped product / CLI
##   - NOT wired into the engine
##
## Reproduces the EXACT topology admission decision used by the CLI engine:
##   scanTopologySource(relPath, source)          → TopologySymbol[]  (as in parseSingleFile)
##   updateBoundaryKinds(symbols, source)          → sets boundaryKind (via extractBoundaries)
##   then the verificationQueue exclusion check    (topology_engine.nim:67-77)
##
## We then report, per symbol, the nodeId, functionName, exported, and the
## post-updateBoundaryKinds boundaryKind, plus whether it would be dropped from
## verificationQueue (trivialNodes set). This tells us exactly where getBitsBE
## (vs encodedLength) falls out of the frontier.
##
## Usage: wp4c_topology_probe <subjectRoot> <outJsonPath>
## Exit: 0 always (regardless of stage statuses).

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, strutils, json, tables, sequtils, algorithm]
import core/topology/topology_symbol_scanner
import core/topology/topology_engine
import core/topology/topology_types
import core/sorter/sorter_core
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

proc boundaryKindStr*(k: TopologyBoundaryKind): string =
  case k
  of topologyBoundaryNone: "topologyBoundaryNone"
  of topologyBoundaryInterface: "topologyBoundaryInterface"
  of topologyBoundaryTrivialDiscard: "topologyBoundaryTrivialDiscard"
  else: $k

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  let args = commandLineParams()
  if args.len < 2:
    stderr.writeLine("usage: wp4c_topology_probe <subjectRoot> <outJsonPath>")
    quit(2)
  let subjectRoot = args[0]
  let outJsonPath = args[1]

  var report = newJObject()
  report["experimentId"] = %"act2-wp4c-symbol-syntax-robustness"
  report["probeType"] = %"experiment-only"
  report["notCanonicalExecutionPath"] = %true
  report["notProductionAPI"] = %true

  # Modules of interest. relPath is what parseSingleFile uses (relative to CWD
  # there); we pass a stable relative path to scanTopologySource.
  let modules = @[
    "stew/base36.nim",
    "stew/bitops2.nim"
  ]

  var modResults = newJObject()
  for modRel in modules:
    let absPath = subjectRoot / modRel
    var source = ""
    try:
      source = readFile(absPath)
    except CatchableError:
      modResults[modRel] = %*{"measured": false, "error": "cannot read " & absPath}
      continue

    var symbols = scanTopologySource(modRel, source)
    updateBoundaryKinds(symbols, source)

    var symArr = newJArray()
    for s in symbols:
      var o = newJObject()
      o["nodeId"] = %sorterNodeIdString(s.nodeId)
      o["functionName"] = %s.functionName
      o["nodeType"] = %s.nodeType
      o["exported"] = %s.exported
      o["boundaryKindBeforeGate"] = %boundaryKindStr(s.boundaryKind)
      o["droppedFromQueue"] = %(s.boundaryKind == topologyBoundaryTrivialDiscard)
      symArr.add(o)
    var m = newJObject()
    m["symbols"] = symArr
    m["measured"] = %true
    modResults[modRel] = m

  report["modules"] = modResults

  let outDir = parentDir(outJsonPath)
  if outDir != "" and not outDir.dirExists:
    outDir.createDir
  try:
    writeFile(outJsonPath, canonicalJsonMinified(report))
  except CatchableError as e:
    stderr.writeLine("cannot write output: " & e.msg)
    quit(1)
  quit(0)
