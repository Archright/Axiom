import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import api/tools_facade
import shared_types/analysis_bridge
import std/[json, os, strutils, tables, math, algorithm]
type
  PropertyTag* = object
    ## Inferred algebraic property with confidence level.
    property*: string
    confidence*: string  ## "high", "medium", or "low"
    body*: string        ## Function body for identity extraction

  FunctionSig* = tuple[name: string, kind: string, arity: int, body: string]
# ---------------------------------------------------------------------------
# Branch extraction helpers (AST-like text scanning for if/case branches)
# ---------------------------------------------------------------------------

type
  BranchInfo* = object
    filePath*: string
    lineNo*: int
    kind*: string           ## "if", "elif", "else", "of"
    condition*: string      ## condition expression or case label
    isUnconditional*: bool  ## true for else/default arms

func extractIfBranches(content: string): seq[BranchInfo] {.raises: [].} =
  ## Scan source content for if/elif/else branches.
  result = @[]
  let lines = content.splitLines()
  for i, rawLine in lines:
    let stripped = rawLine.strip()
    if stripped.startsWith("if "):
      let cond = stripped[3..^1].strip()
      result.add(BranchInfo(filePath: "", lineNo: i + 1, kind: "if",
                            condition: cond, isUnconditional: false))
    elif stripped.startsWith("elif "):
      let cond = stripped[5..^1].strip()
      result.add(BranchInfo(filePath: "", lineNo: i + 1, kind: "elif",
                            condition: cond, isUnconditional: false))
    elif stripped == "else":
      result.add(BranchInfo(filePath: "", lineNo: i + 1, kind: "else",
                            condition: "else", isUnconditional: true))

func extractCaseBranches(content: string): seq[BranchInfo] {.raises: [].} =
  ## Scan source content for case/of branch labels.
  result = @[]
  let lines = content.splitLines()
  for i, rawLine in lines:
    let stripped = rawLine.strip()
    if stripped.startsWith("of "):
      let label = stripped[3..^1].strip()
      result.add(BranchInfo(filePath: "", lineNo: i + 1, kind: "of",
                            condition: label, isUnconditional: false))

func extractAllBranches(content: string): seq[BranchInfo] {.raises: [].} =
  ## Combine if/elif/else and case/of branches into a unified list.
  result = extractIfBranches(content)
  let caseBranches = extractCaseBranches(content)
  result.add(caseBranches)

func countBranches(content: string): tuple[total: int, ifs: int, cases: int] {.raises: [].} =
  ## Count total branches, separating conditional vs unconditional.
  let all = extractAllBranches(content)
  var total = 0
  var ifs = 0
  var cases = 0
  for b in all:
    inc total
    if b.kind in ["if", "elif", "else"]:
      inc ifs
    elif b.kind == "of":
      inc cases
  (total: total, ifs: ifs, cases: cases)

# ---------------------------------------------------------------------------
# Body analysis helpers (text-based, not AST)
# ---------------------------------------------------------------------------

func bodyOnlyUsesCommutativeOps(body: string): bool {.raises: [].} =
  ## Tier 1: Check if body only uses known commutative operators.
  ## Operators: +, *, min, max, and, or, &, |, ^, xor, +=, *=
  ## Returns true only when at least one commutative op is used AND no
  ## non-commutative operators are present in non-comment lines.
  let nonCommutativeOps = [" - ", " / ", " mod ", " div ", " shl ", " shr ",
                           " < ", " > ", " <= ", " >= ", " == ", " != ",
                           " not ", " in ", " notin ", " @", " .. ",
                           "echo ", "echo("]
  let commutativeOps = [" + ", " * ", " min(", " max(", " min (", " max (",
                        " and ", " or ", " & ", " | ", " ^ ", " xor ",
                        " += ", " *= "]
  var hasCommutative = false
  for rawLine in body.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line in ["end", "}", "]:"]:
      continue
    for op in nonCommutativeOps:
      if op in line:
        return false
    if not hasCommutative:
      for op in commutativeOps:
        if op in line:
          hasCommutative = true
          break
  hasCommutative
func hasAccumulatorPattern(body: string): bool {.raises: [].} =
  ## Tier 2: Check for single accumulator loop/reduce pattern.
  for rawLine in body.splitLines():
    let line = rawLine.strip()
    if "result +=" in line or "result *=" in line:
      return true
    if "result = result +" in line or "result = result *" in line:
      return true
    if "result = result and" in line or "result = result or" in line:
      return true
    if "result = result |" in line or "result = result &" in line:
      return true
  return false
func hasIdentityPattern(body: string): bool {.raises: [].} =
  ## Check if function sets result to a known identity element.
  for rawLine in body.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if not line.startsWith("result = "):
      continue
    let value = line[9..^1].strip()
    if value in ["0", "1", "-1", "false", "true", "\"\"", "0.0",
                 "nil", "defaultVal", "zero", "initResult()"]:
      return true
  return false
func extractIdentityValue(body: string): string {.raises: [].} =
  ## Extract the actual identity value from the first result assignment.
  ## Returns empty string if no identity pattern found.
  for rawLine in body.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if not line.startsWith("result = "):
      continue
    let value = line[9..^1].strip()
    if value in ["0", "1", "-1", "false", "true", "\"\"", "0.0",
                 "nil", "defaultVal", "zero", "initResult()"]:
      return value
  return ""
# ---------------------------------------------------------------------------
# Tier classification heuristic
# ---------------------------------------------------------------------------

proc extractFunctionSignatures(filePath: string): seq[FunctionSig] {.raises: [OSError].} =
  ## Parse func/proc declarations and extract (name, kind, arity, body).
  let content = try: readFile(filePath) except CatchableError: ""
  result = @[]
  if content.len == 0:
    return
  let lines = content.splitLines()
  var funcIndices: seq[int] = @[]
  # First pass: find signature line indices
  for i, rawLine in lines:
    let line = rawLine.strip()
    if line.startsWith("func ") or line.startsWith("proc "):
      funcIndices.add(i)
  # Second pass: extract signatures and bodies
  for pos, idx in funcIndices:
    let line = lines[idx].strip()
    let kind = if line.startsWith("func "): "func" else: "proc"
    var startIdx = kind.len + 1
    while startIdx < line.len and line[startIdx] == ' ':
      startIdx.inc
    var name = ""
    while startIdx < line.len and line[startIdx] in {'a'..'z', 'A'..'Z', '0'..'9', '_', '*'}:
      if line[startIdx] != '*':
        name.add(line[startIdx])
      startIdx.inc
    if name.len == 0:
      continue
    let openParen = line.find('(', startIdx)
    if openParen < 0:
      continue
    let closeParen = line.find(')', openParen)
    if closeParen <= openParen:
      continue
    let paramsStr = line[openParen+1..<closeParen]
    let arity = if paramsStr.strip().len == 0: 0 else: paramsStr.split(';').len
    # Extract body: lines between this signature and next (or EOF)
    let bodyStart = idx + 1
    let bodyEnd = if pos + 1 < funcIndices.len: funcIndices[pos + 1] else: lines.len
    var body = ""
    for j in bodyStart..<bodyEnd:
      body.add(lines[j] & "\n")
    result.add((name: name, kind: kind, arity: arity, body: body))
proc inferProperties(name, kind: string, arity: int, body: string): seq[PropertyTag] {.raises: [].} =
  ## 3-tier type-aware property inference with identity detection.
  ## Tier 1 (High Confidence Static): func + body only commutative ops
  ## Tier 2 (Medium Confidence Static): func + single accumulator pattern
  ## Tier 3 (Low Confidence): arity fallback
  result = @[]
  if kind != "func":
    # Only func (pure) functions can have algebraic properties
    return
  var tagged = initTable[string, bool]()
  # Tier 1: High Confidence Static — body only uses commutative operators
  if arity >= 2 and bodyOnlyUsesCommutativeOps(body):
    result.add(PropertyTag(property: "commutative_candidate", confidence: "high"))
    tagged["commutative_candidate"] = true
    result.add(PropertyTag(property: "associative_candidate", confidence: "medium"))
    tagged["associative_candidate"] = true
  # Tier 2: Medium Confidence Static — single accumulator pattern
  elif arity >= 2 and hasAccumulatorPattern(body):
    result.add(PropertyTag(property: "associative_candidate", confidence: "medium"))
    tagged["associative_candidate"] = true
  # Identity detection (any arity)
  if hasIdentityPattern(body):
    result.add(PropertyTag(property: "identity_candidate", confidence: "high"))
    tagged["identity_candidate"] = true
  # Tier 3: Low Confidence — arity fallback (only for untagged properties)
  if arity >= 1 and "idempotent_candidate" notin tagged:
    result.add(PropertyTag(property: "idempotent_candidate", confidence: "low"))
  if arity >= 2:
    if "associative_candidate" notin tagged:
      result.add(PropertyTag(property: "associative_candidate", confidence: "low"))
    if "commutative_candidate" notin tagged:
      result.add(PropertyTag(property: "commutative_candidate", confidence: "low"))
proc classifyModule(filePath: string): string {.raises: [OSError].} =
  ## Heuristic: classify module as Tier 1 (Pure) or Tier 2 (IO-bound).
  ## Tier 1: >80% func, no os/posix/asyncdispatch import.
  ## Tier 2: everything else (I/O-bound, mixed, or external-dependency).
  let content = try: readFile(filePath) except CatchableError: ""
  if content.len == 0:
    return "tier2"
  var funcCount = 0
  var procCount = 0
  var hasBannedImport = false
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.startsWith("func "):
      funcCount.inc
    elif line.startsWith("proc "):
      procCount.inc
    if (line.startsWith("import ") or line.startsWith("from ")) and
       ("std/os" in line or "std/posix" in line or "asyncdispatch" in line):
      hasBannedImport = true
  let totalRoutines = funcCount + procCount
  if totalRoutines > 0 and funcCount.float / totalRoutines.float > 0.8 and not hasBannedImport:
    result = "tier1"
  else:
    result = "tier2"
# ---------------------------------------------------------------------------
# Deterministic JSON serialization — key-sorted JObject recursion
# ---------------------------------------------------------------------------
## Nim std/json Table iteration order is non-deterministic across runs.
## This helper forces lexicographic key ordering so every emit produces
## byte-identical output given identical inputs (determinism proof).

func emitSortedJson(node: JsonNode): string {.raises: [].} =
  ## Recursively serialize a JsonNode with **sorted keys** at every JObject level.
  case node.kind
  of JNull: result = "null"
  of JBool: result = if node.getBool: "true" else: "false"
  of JInt:  result = intToStr(node.getInt)
  of JFloat: result = $(node.getFloat)
  of JString:
    # Escape control characters for valid JSON strings
    var escaped = newStringOfCap(node.str.len * 2)
    for ch in node.str:
      case ch
      of '\\': escaped.add("\\\\")
      of '"':  escaped.add("\\\"")
      of '\b': escaped.add("\\b")
      of '\f': escaped.add("\\f")
      of '\n': escaped.add("\\n")
      of '\r': escaped.add("\\r")
      of '\t': escaped.add("\\t")
      else: escaped.add(ch)
    result = "\"" & escaped & "\""
  of JArray:
    if node.len == 0:
      result = "[]"
    else:
      result = "["
      for idx in 0 ..< node.len:
        if idx > 0: result.add ", "
        result.add emitSortedJson(node[idx])
      result.add "]"
  of JObject:
    # Collect (key, value) pairs from node.pairs, sort by key
    # lexicographically for deterministic output.
    var pairs: seq[tuple[k: string, v: JsonNode]] = @[]
    for k, v in node.pairs:
      pairs.add((k, v))
    pairs.sort(proc(a, b: tuple[k: string, v: JsonNode]): int =
                 if a.k < b.k: -1 elif a.k > b.k: 1 else: 0)
    if pairs.len == 0:
      result = "{}"
    else:
      result = "{"
      for pIdx in 0 ..< pairs.len:
        let p = pairs[pIdx]
        if pIdx > 0: result.add ", "
        result.add "\"" & p.k & "\": " & emitSortedJson(p.v)
      result.add "}"
  else: discard

proc emitSorted*(node: JsonNode): string {.raises: [].} =
  ## Public wrapper: deterministic pretty-printed JSON with sorted keys.
  ## Produces multi-line output indented by 2 spaces.
  let compact = emitSortedJson(node)
  # Simple pretty-printer: insert newlines after , { [ and before } ]
  var indent = 0
  var prev = ' '
  for c in compact:
    if c in ['}', ']']:
      indent.dec
      if prev != '{' and prev != '[' and prev != ',':
        result.add '\n'
      for _ in 0 ..< indent: result.add "  "
    result.add c
    if c in ['{', '[']:
      indent.inc
      result.add '\n'
      for _ in 0 ..< indent: result.add "  "
    elif c == ',':
      result.add '\n'
      for _ in 0 ..< indent: result.add "  "
    prev = c
  if result.len > 0 and result[^1] != '\n':
    result.add '\n'

proc emitBatchManifest(graph: Table[string, seq[string]],
                       layers: seq[seq[string]],
                       outPath: string) {.raises: [OSError, IOError].} =
  var layersArr = newJArray()
  var totalModules = 0
  for layerIndex, layer in layers:
    var modulesArr = newJArray()
    for modPath in layer:
      let fullPath = CoreDir / modPath & ".nim"
      let tier = classifyModule(fullPath)
      modulesArr.add(%* {
        "path": modPath,
        "tier": tier,
        "imports": %graph.getOrDefault(modPath)
      })
      totalModules.inc
    let layerObj = %* {"layer": layerIndex, "modules": modulesArr}
    layersArr.add(layerObj)
  let manifest = %* {
    "layers": layersArr,
    "totalModules": totalModules,
    "totalLayers": layers.len
  }
  writeFile(outPath, emitSorted(manifest))
proc emitAlgebraicRegistry(layers: seq[seq[string]],
                           outPath: string) {.raises: [OSError, IOError].} =
  ## Emit tests/specs/algebraic_registry.json with inferred properties.
  ## Structure: "inferred" entries now include confidence levels.
  ## Each property is {"property": "...", "confidence": "high|medium|low"}.
  ## "verified" remains empty until human review.
  var registry = newJObject()
  var modulesObj = newJObject()
  for layer in layers:
    for modPath in layer:
      let fullPath = CoreDir / modPath & ".nim"
      let funcs = extractFunctionSignatures(fullPath)
      if funcs.len == 0:
        continue
      var modObj = newJObject()
      var inferred = newJObject()
      for f in funcs:
        let props = inferProperties(f.name, f.kind, f.arity, f.body)
        if props.len > 0:
          var propsArr = newJArray()
          for p in props:
            propsArr.add(%*{"property": p.property, "confidence": p.confidence, "body": p.body})
          inferred[f.name] = propsArr
      if inferred.len > 0:
        modObj["inferred"] = inferred
        modObj["verified"] = newJObject()
        modulesObj[modPath] = modObj
  registry["modules"] = modulesObj
  createDir(parentDir(outPath))
  writeFile(outPath, emitSorted(registry))
# ---------------------------------------------------------------------------
# PBT code generation pipeline
# ---------------------------------------------------------------------------

proc generatePbtTestBody(funcName: string,
                         props: seq[PropertyTag]): string =
  ## Generate test body for a single function's high-confidence properties.
  result = ""
  for p in props:
    if p.confidence != "high":
      continue  # Only generate tests for high-confidence candidates
    case p.property
    of "commutative_candidate":
      result.add "## Commutativity: f(a,b) == f(b,a) — verified over random inputs\n"
      result.add "let gen_" & funcName & "_int = genInt(-100, 100)\n"
      result.add "let prop_" & funcName & "_comm = proc(a, b: int): bool =\n"
      result.add "  " & funcName & "(a, b) == " & funcName & "(b, a)\n"
      result.add "let res_" & funcName & "_comm = checkProperty(\n"
      result.add "  gen_" & funcName & "_int, prop_" & funcName & "_comm,\n"
      result.add "  iterations = 200, tier = PbtBasic, verbosity = PbtSilent)\n"
      result.add "check res_" & funcName & "_comm.passed == true\n\n"
    of "identity_candidate":
      ## Extract actual identity value from function body for precise testing
      let identityVal = extractIdentityValue(p.body)
      if identityVal.len > 0:
        result.add "## Identity: f(x, " & identityVal & ") == x — verified over random inputs\n"
        result.add "let gen_" & funcName & "_int = genInt(-100, 100)\n"
        result.add "let prop_" & funcName & "_id = proc(x: int): bool =\n"
        result.add "  " & funcName & "(x, " & identityVal & ") == x\n"
        result.add "let res_" & funcName & "_id = checkProperty(\n"
        result.add "  gen_" & funcName & "_int, prop_" & funcName & "_id,\n"
        result.add "  iterations = 100, tier = PbtBasic, verbosity = PbtSilent)\n"
        result.add "check res_" & funcName & "_id.passed == true\n\n"
      else:
        ## No concrete identity found — generate failing test to flag manual review needed
        result.add "## IDENTITY REVIEW: f(x) == x assertion needs manual verification\n"
        result.add "## The function initializes result but identity element is ambiguous\n"
        result.add "check false  # axiom:theater-fix: placeholder until identity is confirmed\n\n"
    else:
      discard  # Only generate for high confidence
proc emitGeneratedPbtTests(registryPath: string,
                           outDir: string) {.raises: [OSError, IOError, ValueError].} =
  ## Generate PBT test files from high-confidence registry entries.
  ## Only functions tagged with confidence="high" get generated tests.
  let content = try: readFile(registryPath) except CatchableError: return
  let registry = try: parseJson(content) except CatchableError: return
  let modules = registry{"modules"}
  if modules.isNil or modules.kind != JObject:
    return
  createDir(outDir)
  var totalGenerated = 0
  for modPath, modObj in modules:
    let inferred = modObj{"inferred"}
    if inferred.isNil or inferred.kind != JObject:
      continue
    var testBody = ""
    var hasHighConfidence = false
    for funcName, propsNode in inferred:
      if propsNode.kind != JArray:
        continue
      var props: seq[PropertyTag] = @[]
      for pElem in propsNode:
        if pElem.kind == JObject:
          let prop = pElem{"property"}.getStr("")
          let conf = pElem{"confidence"}.getStr("")
          let bdy = pElem{"body"}.getStr("")
          if prop.len > 0 and conf.len > 0:
            props.add(PropertyTag(property: prop, confidence: conf, body: bdy))
      let body = generatePbtTestBody(funcName, props)
      if body.len > 0:
        testBody.add(body)
        hasHighConfidence = true
    if not hasHighConfidence:
      continue
    # Sanitize module path for filename
    let safeName = modPath.replace("/", "_").replace("\\", "_")
    let outPath = outDir / ("auto_" & safeName & ".nim")
    var fileContent = "{.push raises: [].}\n"
    fileContent.add "## AUTO-GENERATED PBT: " & modPath & "\n"
    fileContent.add "## Generated by tools/discover_test_debt.nim — DO NOT EDIT MANUALLY\n"
    fileContent.add "## Review generators and property assertions before CI merge.\n\n"
    fileContent.add "import std/[unittest]\n"
    fileContent.add "import core/testing/pbt_engine\n"
    fileContent.add "import core/testing/generators\n\n"
    fileContent.add "suite \"PBT: auto/" & modPath & "\":\n"
    fileContent.add testBody
    fileContent.add "\n{.pop.}\n"
    writeFile(outPath, fileContent)
    totalGenerated.inc
  echo "[discover] Generated ", totalGenerated, " PBT test files in ", outDir
# ---------------------------------------------------------------------------
# Branch coverage reporting
# ---------------------------------------------------------------------------

const
  BranchCoverageTarget* = 85 ## Minimum acceptable branch coverage percentage

type
  ModuleBranchReport* = object
    filePath*: string
    moduleName*: string
    totalBranches*: int
    coveredBranches*: int  ## 0 = unknown, tracked externally
    coveragePct*: float
    branches*: seq[BranchInfo]
    status*: string        ## "PASS", "WARN", "FAIL"

proc computeBranchCoverage(modPath: string): ModuleBranchReport {.raises: [IOError].} =
  ## Analyze a single module for branch coverage debt.
  result.filePath = modPath
  result.moduleName = modPath.replace("/", ".").replace(".nim", "")
  let content = try: readFile(modPath) except CatchableError: ""
  if content.len == 0:
    result.status = "SKIP"
    return
  let allBranches = extractAllBranches(content)
  result.branches = allBranches
  result.totalBranches = allBranches.len
  if result.totalBranches == 0:
    result.coveragePct = 100.0
    result.status = "PASS"
    return
  # Heuristic: every else/unconditional arm counts as potentially untested
  var uncovered = 0
  for b in allBranches:
    if b.isUnconditional:
      inc uncovered
  result.coveredBranches = result.totalBranches - uncovered
  result.coveragePct = result.coveredBranches.float / result.totalBranches.float * 100.0
  if result.coveragePct >= BranchCoverageTarget:
    result.status = "PASS"
  elif result.coveragePct >= BranchCoverageTarget - 15:
    result.status = "WARN"
  else:
    result.status = "FAIL"

proc emitModuleBranchCoverageReport(layers: seq[seq[string]],
                               outPath: string) {.raises: [OSError, IOError].} =
  ## Emit tests/specs/branch_coverage.json with per-module branch stats.
  var reportObj = newJObject()
  var modulesArr = newJArray()
  var passCount = 0
  var warnCount = 0
  var failCount = 0
  var skipCount = 0
  var totalModules = 0

  for layer in layers:
    for modPath in layer:
      let fullPath = CoreDir / modPath & ".nim"
      let report = computeBranchCoverage(fullPath)
      inc totalModules
      if report.status == "SKIP":
        inc skipCount
        continue

      var modReport = %*{
        "module": report.moduleName,
        "path": modPath,
        "totalBranches": report.totalBranches,
        "coveredBranches": report.coveredBranches,
        "coveragePct": round(report.coveragePct, 1),
        "status": report.status,
        "branches": %[]
      }

      if report.branches.len > 0:
        var branchesArr = newJArray()
        for b in report.branches:
          branchesArr.add(%*{
            "lineNo": b.lineNo,
            "kind": b.kind,
            "condition": b.condition,
            "isUnconditional": b.isUnconditional
          })
        modReport["branches"] = branchesArr

      modulesArr.add(modReport)

      case report.status
      of "PASS": inc passCount
      of "WARN": inc warnCount
      of "FAIL": inc failCount
      else: discard

  reportObj["target"] = %BranchCoverageTarget
  reportObj["summary"] = %*{
    "totalModules": totalModules,
    "pass": passCount,
    "warn": warnCount,
    "fail": failCount,
    "skip": skipCount
  }
  reportObj["modules"] = modulesArr

  writeFile(outPath, emitSorted(reportObj))

  echo ""
  echo "=== Branch Coverage Report ==="
  echo "Target: ", BranchCoverageTarget, "%+"
  echo "Total modules analyzed: ", totalModules
  echo "  PASS (>= ", BranchCoverageTarget, "%): ", passCount
  echo "  WARN (>= ", $(BranchCoverageTarget - 15), "%): ", warnCount
  echo "  FAIL (< ", $(BranchCoverageTarget - 15), "%): ", failCount
  echo "  SKIP (no branches): ", skipCount

  if failCount > 0:
    echo ""
    echo "Modules below target:"
    for m in modulesArr:
      if m{"status"}.getStr("") == "FAIL":
        echo "  [FAIL] ", m{"module"}.getStr(""),
             " — ", m{"coveragePct"}.getFloat(0.0), "% coverage (",
             m{"totalBranches"}.getInt(0), " branches)"

  if warnCount > 0:
    echo ""
    echo "Modules approaching target:"
    for m in modulesArr:
      if m{"status"}.getStr("") == "WARN":
        echo "  [WARN] ", m{"module"}.getStr(""),
             " — ", m{"coveragePct"}.getFloat(0.0), "% coverage"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() {.raises: [OSError, IOError, ValueError].} =
  let graph = buildImportGraph(CoreDir)
  let layers = computeTopologicalLayers(graph)
  let manifestPath = "tests/auto_generated/batch_manifest.json"
  let registryPath = "tests/specs/algebraic_registry.json"
  let generatedPbtDir = "tests/pbt/generated"
  emitBatchManifest(graph, layers, manifestPath)
  emitAlgebraicRegistry(layers, registryPath)
  emitGeneratedPbtTests(registryPath, generatedPbtDir)
  let branchReportPath = "tests/specs/branch_coverage.json"
  emitModuleBranchCoverageReport(layers, branchReportPath)
  echo "[discover] Wrote batch manifest: ", manifestPath
  echo "[discover] Wrote algebraic registry: ", registryPath
  echo "[discover] Total layers: ", layers.len
  var tier1Count = 0
  var tier2Count = 0
  for i, layer in layers:
    var t1 = 0
    var t2 = 0
    for modPath in layer:
      let tier = classifyModule(CoreDir / modPath & ".nim")
      if tier == "tier1": t1.inc else: t2.inc
    tier1Count += t1
    tier2Count += t2
    echo "  Layer ", i, ": ", layer.len, " modules (Tier1=", t1, ", Tier2=", t2, ")"
  echo "[discover] Total Tier1=", tier1Count, " Tier2=", tier2Count
when isMainModule:
  main()
