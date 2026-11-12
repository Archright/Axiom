## experiments/act2-wp4c-symbol-syntax-robustness/wp4c_boundary_probe.nim
## — Act2-WP4c Boundary Extraction Probe
##
## EXPERIMENT-ONLY instrument.
##   - NOT a canonical execution path
##   - NOT a production API
##   - NOT part of the shipped product / CLI
##   - NOT wired into the engine
##
## Reproduces the exact topology admission decision for two external symbols:
##   - stew/base36.nim::encodedLength  (observed ALIVE in frontier)
##   - stew/bitops2.nim::getBitsBE      (observed NOT-FOUND in frontier)
##
## It calls extractBoundaries(nodeId, sourceCode) — the same function invoked by
## topology_engine.updateBoundaryKinds (topology_engine.nim:263) — and reports
## the resulting completeness kind, so we can see whether getBitsBE is dropped
## via bcTrivialDiscard at the topology eligibility gate.
##
## Usage: wp4c_boundary_probe <subjectRoot> <outJsonPath>
## Exit: 0 always (regardless of stage statuses).

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, strutils, json, tables, sequtils, algorithm]
import core/boundary/boundary_extractor_part1
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

proc completenessKind*(c: BoundaryCompleteness): string =
  $c

# ---------------------------------------------------------------------------
# Per-symbol boundary measurement
# ---------------------------------------------------------------------------

proc measure*(modulePath: string; funcName: string; source: string): JsonNode =
  ## nodeId format used by topology: "<module>::<funcName>" — but topology uses
  ## sorterNodeIdString. For the boundary extractor, what matters is the second
  ## part (function name), because initBoundaryContext splits on "::".
  let nodeId = modulePath & "::" & funcName
  result = newJObject()
  result["nodeId"] = %nodeId
  try:
    let res = extractBoundaries(nodeId, source)
    result["completeness"] = %(completenessKind(res.completeness))
    result["functionName"] = %(res.functionName)
    result["returnType"] = %(res.returnType)
    var paramsArr = newJArray()
    for p in res.params:
      var o = newJObject()
      o["name"] = %p.name
      o["nimType"] = %p.nimType
      o["isVar"] = %p.isVar
      o["smtConstraint"] = %p.smtConstraint
      o["leanProposition"] = %p.leanProposition
      paramsArr.add(o)
    result["params"] = paramsArr
    var smtArr = newJArray()
    for s in res.smtParts: smtArr.add(%s)
    result["smtParts"] = smtArr
    var leanArr = newJArray()
    for l in res.leanParts: leanArr.add(%l)
    result["leanParts"] = leanArr
    result["isTrivialDiscard"] = %(res.completeness == bcTrivialDiscard)
  except CatchableError as e:
    result["measured"] = %false
    result["error"] = %("extractBoundaries raised: " & e.msg)
  result["measured"] = %true

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  let args = commandLineParams()
  if args.len < 2:
    stderr.writeLine("usage: wp4c_boundary_probe <subjectRoot> <outJsonPath>")
    quit(2)
  let subjectRoot = args[0]
  let outJsonPath = args[1]

  var report = newJObject()
  report["experimentId"] = %"act2-wp4c-symbol-syntax-robustness"
  report["probeType"] = %"experiment-only"
  report["notCanonicalExecutionPath"] = %true
  report["notProductionAPI"] = %true

  let symbols = @[
    ("stew/base36.nim", "encodedLength"),
    ("stew/bitops2.nim", "getBitsBE"),
    ("stew/base36.nim", "decodedLength")
  ]

  var results = newJObject()
  for (modRel, fn) in symbols:
    let path = subjectRoot / modRel
    var src = ""
    var ok = false
    try:
      if path.fileExists:
        src = readFile(path)
        ok = true
    except CatchableError:
      ok = false
    if not ok:
      results[fn] = %*{"measured": false, "error": "cannot read " & path}
      continue
    results[fn] = measure(modRel, fn, src)

  report["symbols"] = results

  let outDir = parentDir(outJsonPath)
  if outDir != "" and not outDir.dirExists:
    outDir.createDir
  try:
    writeFile(outJsonPath, canonicalJsonMinified(report))
  except CatchableError as e:
    stderr.writeLine("cannot write output: " & e.msg)
    quit(1)
  quit(0)
