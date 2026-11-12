import core/trusted/layer_declaration
axiomLayer "tools"

import std/[json, os, times, sequtils, options, strutils, streams]
import osproc
import core/ir/ir_types
import core/verifier/verifier_types
import core/verifier/lean_repl_bridge

type
  TierStats* = object
    replCacheHitRate*: float
    z3AverageLatencyMs*: float
    tier1ShortCircuitRatio*: float
    totalExecutionMs*: float

proc collectTierStats*(metrics: seq[TierExecutionMetric]): TierStats =
  ## 메트릭 시퀀스에서 성능 통계 수집
  var cacheHits = 0
  var z3Latencies: seq[float] = @[]
  var shortCircuits = 0
  var totalExecutionMs = 0.0
  
  for m in metrics:
    totalExecutionMs = totalExecutionMs + m.durationMs
    if m.cacheHit: inc cacheHits
    if m.resolvedTier == tkTier3_Z3:
      z3Latencies.add(m.durationMs)
    if m.resolvedTier == tkTier1_Fast:
      inc shortCircuits
  
  var z3LatencySum = 0.0
  for latency in z3Latencies:
    z3LatencySum = z3LatencySum + latency
  
  result.replCacheHitRate = if metrics.len == 0: 0.0 else: cacheHits.float / metrics.len.float
  result.z3AverageLatencyMs = if z3Latencies.len == 0: 0.0 else: z3LatencySum / z3Latencies.len.float
  result.tier1ShortCircuitRatio = if metrics.len == 0: 0.0 else: shortCircuits.float / metrics.len.float
  result.totalExecutionMs = totalExecutionMs

proc verifyPerformanceBudget*(stats: TierStats): bool =
  ## SLA Threshold Assertion
  let budget = %*{
    "replCacheHitRate": 0.85,
    "z3AverageLatencyMs": 50.0,
    "tier1ShortCircuitRatio": 0.70
  }
  
  if stats.replCacheHitRate < budget["replCacheHitRate"].getFloat():
    echo "[PERF GATE] FAIL: REPL cache hit rate too low: ", stats.replCacheHitRate
    return false
  
  if stats.z3AverageLatencyMs > budget["z3AverageLatencyMs"].getFloat():
    echo "[PERF GATE] FAIL: Z3 average latency too high: ", stats.z3AverageLatencyMs
    return false
  
  if stats.tier1ShortCircuitRatio < budget["tier1ShortCircuitRatio"].getFloat():
    echo "[PERF GATE] FAIL: Tier 1 short-circuit ratio too low: ", stats.tier1ShortCircuitRatio
    return false
  
  echo "[PERF GATE] PASS: Performance budget verified"
  return true

proc nimTypeToLean*(nimType: string): string =
  let t = nimType.strip()
  if t == "int":
    return "Int"
  if t.startsWith("seq["):
    return "List Int"
  return t

proc parseAxiomString*(line: string): seq[string] =
  var rest = line
  while true:
    let marker = rest.find("axiom:")
    if marker < 0:
      break

    let afterMarker = rest[marker + "axiom:".len .. ^1]
    let quoteIdx = afterMarker.find('"')
    if quoteIdx < 0:
      break

    let valueStart = quoteIdx + 1
    let valueEnd = afterMarker.find('"', valueStart)
    if valueEnd < 0:
      break

    result.add(afterMarker[valueStart ..< valueEnd].strip())
    if valueEnd + 1 < afterMarker.len:
      rest = afterMarker[valueEnd + 1 .. ^1]
    else:
      break

proc parseAtomSpec*(atom: string): IRExpr =
  let s = atom.strip()
  if s.len == 0:
    return IRExpr(kind: ieConst, val: "true")

  let openIdx = s.find('(')
  if openIdx > 0:
    var args: seq[IRExpr] = @[]
    var argStart = openIdx + 1
    var depth = 0
    for i in openIdx ..< s.len:
      if s[i] == '(':
        if depth == 0:
          argStart = i + 1
        inc depth
      elif s[i] == ')':
        dec depth
        if depth == 0 and argStart < i:
          args.add(parseAtomSpec(s[argStart ..< i]))
          argStart = i + 1
      elif s[i] == ',':
        if depth == 0:
          args.add(parseAtomSpec(s[argStart ..< i]))
          argStart = i + 1
    if argStart < s.len:
      args.add(parseAtomSpec(s[argStart .. s.len - 1]))
    return IRExpr(kind: ieApp, fnName: s[0 ..< openIdx].strip(), args: args)

  result = IRExpr(kind: ieVar, varName: s)

proc parseExprSpec*(spec: string): IRExpr =
  let s = spec.strip()
  if s.len == 0:
    return IRExpr(kind: ieConst, val: "true")

  for op in [">=", "<=", "==", ">", "<", "+", "-"]:
    let opIdx = s.find(op)
    if opIdx > 0 and opIdx + op.len < s.len:
      return IRExpr(
        kind: ieBinaryOp,
        left: parseAtomSpec(s[0 ..< opIdx]),
        right: parseAtomSpec(s[opIdx + op.len .. ^1]),
        op: op
      )

  result = parseAtomSpec(s)

proc splitAxiomSpec*(spec: string): tuple[preConditions: seq[string]; postCondition: Option[string]] =
  let parts = spec.split("==>")
  if parts.len == 1:
    result.postCondition = some(parts[0].strip())
  else:
    result.preConditions.add(parts[0].strip())
    result.postCondition = some(parts[1 .. ^1].join("==>").strip())

proc parseFixtureProc*(name: string; params: seq[AxiomParam]; axiomSpecs: seq[string]): AxiomIRNode =
  var preConditions: seq[IRExpr] = @[]
  var postCondition: Option[IRExpr] = none(IRExpr)

  for spec in axiomSpecs:
    let splitSpec = splitAxiomSpec(spec)
    for pre in splitSpec.preConditions:
      preConditions.add(parseExprSpec(pre))
    if splitSpec.postCondition.isSome:
      postCondition = some(parseExprSpec(splitSpec.postCondition.get))

  result = AxiomIRNode(
    kind: irCall,
    name: name,
    params: params,
    returnType: "Int",
    preConditions: preConditions,
    postCondition: postCondition,
    children: @[],
    body: nil
  )

proc parseProcName*(line: string): string =
  let procIdx = line.find("proc")
  var start = procIdx + "proc".len
  while start < line.len and line[start] in {' ', '\t', '\n', '\r'}:
    inc start

  var endIdx = start
  while endIdx < line.len and line[endIdx] notin {' ', '\t', '\n', '\r', '('}:
    inc endIdx

  result = line[start ..< endIdx]
  if result.len > 0 and result[^1] == '*':
    result = result[0 ..< result.len - 1]

proc parseProcParams*(line: string): seq[AxiomParam] =
  let openIdx = line.find('(')
  let closeIdx = line.find(')', openIdx)
  if openIdx < 0 or closeIdx < 0:
    return

  let body = line[openIdx + 1 ..< closeIdx].strip()
  if body.len == 0:
    return

  for rawParam in body.split(','):
    let param = rawParam.strip()
    if param.len == 0:
      continue

    let colonIdx = param.find(':')
    let name = param[0 ..< colonIdx].strip()
    let typeName = param[colonIdx + 1 .. ^1].strip()
    result.add(AxiomParam(
      name: name,
      typeStr: nimTypeToLean(typeName),
      refinement: none(IRExpr),
      isInductive: typeName.startsWith("seq[")
    ))

proc parseFixture*(fixturePath: string): seq[AxiomIRNode] =
  let lines = readFile(fixturePath).splitLines()
  var currentName = ""
  var currentParams: seq[AxiomParam] = @[]
  var currentAxioms: seq[string] = @[]
  var inProc = false

  for rawLine in lines:
    let line = rawLine.strip()
    if line.startsWith("proc "):
      if inProc:
        result.add(parseFixtureProc(currentName, currentParams, currentAxioms))
      currentName = parseProcName(line)
      currentParams = parseProcParams(line)
      currentAxioms = parseAxiomString(line)
      inProc = true
    elif inProc:
      continue

  if inProc:
    result.add(parseFixtureProc(currentName, currentParams, currentAxioms))

proc hasPreconditions*(ir: AxiomIRNode): bool {.raises: [].} =
  ir.preConditions.len > 0

proc classifyResolvedTier*(ir: AxiomIRNode): TierKind {.raises: [].} =
  if ir.params.anyIt(it.isInductive):
    return tkTier1_5_Inductive

  if hasPreconditions(ir):
    return tkTier3_Z3

  if not ir.postCondition.isNone:
    return tkTier1_Fast

  if ir.params.len > 0:
    return tkTier2_LLM

  tkTier3_Z3

proc runVerificationPipelineWithMetric*(ir: AxiomIRNode): TierExecutionMetric =
  let tier = classifyResolvedTier(ir)
  let start = cpuTime()
  try:
    let child = startProcess(
      getAppFilename(),
      args = @["--benchmark-child", ir.name],
      options = {poUsePath, poStdErrToStdOut}
    )
    defer: child.close()

    let waitMs = if declared(terminate): 120000 else: 0
    let exitCode = if waitMs > 0: child.waitForExit(waitMs) else: child.waitForExit()
    if waitMs > 0 and exitCode == -1:
      when declared(terminate):
        child.terminate()
        discard child.waitForExit()

    let output = streams.readAll(child.outputStream)
    discard output
    let durationMs = (cpuTime() - start) * 1000.0
    return TierExecutionMetric(
      functionName: ir.name,
      resolvedTier: tier,
      durationMs: durationMs,
      cacheHit: false
    )
  except CatchableError:
    return TierExecutionMetric(
      functionName: ir.name,
      resolvedTier: tkFailed,
      durationMs: (cpuTime() - start) * 1000.0,
      cacheHit: false
    )

proc run4TierBenchmark*(testCases: seq[AxiomIRNode]): JsonNode =
  var metrics: seq[TierExecutionMetric] = @[]
  var counts = [0, 0, 0, 0, 0]

  for ir in testCases:
    let metric = runVerificationPipelineWithMetric(ir)
    counts[ord(metric.resolvedTier)] += 1
    metrics.add(metric)

  let total = testCases.len
  let tier1Ratio = if total == 0: 0.0 else: counts[0].float / total.float
  let tier1_5Ratio = if total == 0: 0.0 else: counts[1].float / total.float
  let tier2Ratio = if total == 0: 0.0 else: counts[2].float / total.float
  let tier3Ratio = if total == 0: 0.0 else: counts[3].float / total.float
  let failedRatio = if total == 0: 0.0 else: counts[4].float / total.float

  let stats = %*{
    "fixturePath": "tests/fixtures/std_math_fixture.nim",
    "totalCases": total,
    "tierCounts": %*{
      "tier1": counts[0],
      "tier1_5": counts[1],
      "tier2": counts[2],
      "tier3": counts[3],
      "failed": counts[4]
    },
    "tier1Ratio": tier1Ratio,
    "tier1_5Ratio": tier1_5Ratio,
    "tier2Ratio": tier2Ratio,
    "tier3Ratio": tier3Ratio,
    "failedRatio": failedRatio,
    "metrics": metrics.mapIt(it.toJson())
  }

  let benchDir = "benchmarks"
  if not dirExists(benchDir):
    createDir(benchDir)
  writeFile(benchDir / "tier_stats.json", stats.pretty())

  return stats

when isMainModule:
  if commandLineParams().contains("--benchmark-child"):
    let fixturePath = getCurrentDir() / "tests" / "fixtures" / "std_math_fixture.nim"
    let targetName = commandLineParams()[0]
    for ir in parseFixture(fixturePath):
      if ir.name == targetName:
        discard runVerificationPipeline(ir)
        quit(0)
    quit(2)

  let fixturePath = getCurrentDir() / "tests" / "fixtures" / "std_math_fixture.nim"
  let testCases = parseFixture(fixturePath)
  let stats = run4TierBenchmark(testCases)
  echo stats.pretty()
