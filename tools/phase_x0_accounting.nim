## Phase X0/X1.0 — Execution Accounting Tool (thin CLI)
##
## Reads a merged `bin/ax report --json` output (persisted proof state) and
## emits the X1.0 canonical execution-accounting measurement: canonical 3-axis
## accounting (docs/spec/execution_accounting_contract.md) + legacy projection
## + the existing X0 Plan/Execution/DAG/Time blocks.
##
## The canonical reducer lives in src/verification/accounting/run_accounting.nim
## (importable, unit-tested). This file is the thin CLI.
##
## X1.0 source (measurementSource):
##   - production_canonical: the merged report carries runAccounting/runOutcome
##     (canonical boundary installed — DEBT#458 closed). Direct from the report,
##     no trajectory compensation (measurementCompensated=false).
##   - trajectory_reconstruction: fallback for pre-X1 reports — skReport records
##     embed the per-wave report under `extra` (temporary measurement
##     compensation for the last-wave merge defect; measurementCompensated=true).
##
## Usage:
##   nim c -o:bin/phase_x0_accounting tools/phase_x0_accounting.nim
##   bin/phase_x0_accounting <report.json> [--output <out.json>]
##       [--state <logs/ax_proof_state.json>] [--trajectory <logs/ax_prove_trajectory.jsonl>]
##       [--run <N>]   (N = 0-based index from the END; 0 = last run, default)

import core/trusted/layer_declaration
axiomLayer "tools"

import std/[os, osproc, strutils, json, times, algorithm, tables, sequtils]
import verification/accounting/run_accounting
import verification/obligation/verification_decision_authority

const
  ToolVersion = "0.3.0"
  SchemaVersion = "2.0"
  DefaultOutputPath = "data/benchmarks/phase_x0_exec_accounting.json"
  DefaultTrajectoryPath = "logs/ax_prove_trajectory.jsonl"

type
  MeasurementSource* = enum
    ProductionCanonical = "production_canonical"
    TrajectoryReconstruction = "trajectory_reconstruction"

# ── Derivation notes ──────────────────────────────────────────────
# These explain how each X0 field is computed when the source report
# does not provide a direct value.

type
  X0Accounting* = object
    experiment*: string
    branch*: string
    head*: string
    timestamp*: string
    command*: string
    Plan*: X0Plan
    Execution*: X0Execution
    DAG*: X0DAG
    Time*: X0Time
    Case*: string
    caseRationale*: string
    derivations*: seq[string]

  X0Plan* = object
    universeCount*: int
    requiredCount*: int
    reusableCount*: int        # cacheHit among required nodes
    preSievedCount*: int       # PreSievedUnverifiable nodes
    freshCount*: int           # canonical freshExecutionCount (X1.0)

  X0Execution* = object
    invocationCount*: int      # solverInvocationCount (summed across waves)
    cacheHitCount*: int        # executionStats.cacheHitCount (summed)
    blockedCount*: int
    failedCount*: int
    timeoutCount*: int
    unresolvedCount*: int      # required − (verified + failed + timeout + blocked + preSieved + reusable)

  X0DAG* = object
    nodeCount*: int
    edgeCount*: int            # not directly in report; derived below
    criticalPath*: int         # max dependencyDepth + 1
    maxWidth*: int             # max nodes sharing a dependencyDepth
    averageWidth*: float       # mean nodes per dependencyDepth

  X0Time* = object
    planningMs*: int           # not directly available; inferred
    cacheClassificationMs*: int # not directly available; inferred
    freshExecutionMs*: int     # totalSolverTimeMs (summed across waves)
    reductionMs*: int          # serialBaselineMs − totalWallTimeMs (parallelism gain)
    totalWallMs*: int

  X0WaveStats* = object
    provided*: bool            # true when cross-wave sums replace merged-report values
    invocationCount*: int
    cacheHitCount*: int
    preSievedCount*: int
    obligationAttemptedCount*: int
    totalWallMs*: int
    totalSolverMs*: int
    serialBaselineMs*: int

# ── Helpers ───────────────────────────────────────────────────────

proc isoNow(): string =
  let dt = now()
  result = $dt.year & "-" & $(dt.month.int) & "-" & $(dt.monthday.int) &
           "T" & $(dt.hour.int) & ":" & $(dt.minute.int) & ":" & $(dt.second.int)

proc gitHead(): string =
  let (stdoutResult, code) = execCmdEx("git rev-parse HEAD")
  if code == 0: stdoutResult.strip() else: "unknown"

proc gitBranch(): string =
  let (stdoutResult, code) = execCmdEx("git branch --show-current")
  if code == 0: stdoutResult.strip() else: "unknown"

proc safeGetInt(node: JsonNode, key: string, default: int = 0): int =
  if node.isNil: return default
  let v = node{key}
  if v.isNil or v.kind != JInt: default
  else: v.getInt()

proc safeGetFloat(node: JsonNode, key: string, default: float = 0.0): float =
  if node.isNil: return default
  let v = node{key}
  if v.isNil or v.kind != JFloat: default
  else: v.getFloat()

proc safeGetStr(node: JsonNode, key: string, default: string = ""): string =
  if node.isNil: return default
  let v = node{key}
  if v.isNil or v.kind != JString: default
  else: v.getStr()

proc safeGetBool(node: JsonNode, key: string, default: bool = false): bool =
  if node.isNil: return default
  let v = node{key}
  if v.isNil or v.kind != JBool: default
  else: v.getBool()

# ── Core X0 computation (legacy blocks, consumed by the evidence doc) ──

proc computeX0*(report: JsonNode; stateJson: JsonNode;
                waveStats: X0WaveStats = X0WaveStats();
                canonicalFreshCount: int = -1;
                nodeReportsOverride: JsonNode = nil): X0Accounting =
  ## Compute the X0 Plan/Execution/DAG/Time blocks. Where the last-wave merge
  ## defect (DEBT#458) distorts executionStats-derived numbers, the caller may
  ## pass cross-wave sums via `waveStats` and the merged per-wave nodeReports
  ## via `nodeReportsOverride`; deviations are noted under "derivations".
  var derivations = newSeq[string]()

  # ── Plan ──────────────────────────────────────────────────────
  let closure = report{"closure"}
  let summary = report{"summary"}
  let execStats = report{"executionStats"}
  let nodeReports = if nodeReportsOverride.isNil: report{"nodeReports"}
                    else: nodeReportsOverride

  let universeCount = if closure.isNil: summary.safeGetInt("symbolCount")
                     else: closure.safeGetInt("universeCount")
  let requiredCount = if closure.isNil: 0 else: closure.safeGetInt("requiredCount")

  # reusableCount: cache hits among required nodes.
  var reusableCount = 0
  if nodeReports.kind == JArray:
    for nr in nodeReports.elems:
      if nr.safeGetBool("cacheHit"): inc reusableCount

  # preSievedCount: X0 semantics = PreSievedUnverifiable nodes. When waves are
  # provided, summed across waves (the merged report carries only the last wave).
  let preSievedCount = if waveStats.provided: waveStats.preSievedCount
                       else: summary.safeGetInt("preSieved")
  # freshCount (X0) = genuine proof attempts. X1.0: canonical freshExecutionCount
  # (|FreshExecutionSet|) replaces the defective obligationAttemptedCount
  # (obligation-weighted + never incremented on the parallel path — DEBT#458).
  let freshCount = if canonicalFreshCount >= 0: canonicalFreshCount
                   else: execStats.safeGetInt("obligationAttemptedCount")

  if closure.isNil:
    derivations.add("universeCount derived from summary.symbolCount (closure field absent)")
  if nodeReports.kind != JArray:
    derivations.add("reusableCount=0 (nodeReports absent or not an array)")
  if waveStats.provided:
    derivations.add("X0 preSievedCount summed across waves (" & $preSievedCount &
      ") — merged report carries only the last wave (DEBT#458)")
  derivations.add("X0 freshCount = canonical freshExecutionCount (" & $freshCount &
    ") — |FreshExecutionSet|, NOT obligationAttemptedCount (defective: obligation-weighted, " &
    "parallel path never increments — DEBT#458)")

  # ── Execution ─────────────────────────────────────────────────
  let invocationCount = if waveStats.provided: waveStats.invocationCount
                        else: execStats.safeGetInt("solverInvocationCount")
  let cacheHitCount = if waveStats.provided: waveStats.cacheHitCount
                      else: execStats.safeGetInt("cacheHitCount")
  let blockedCount = summary.safeGetInt("blockedCount")
  let failedCount = summary.safeGetInt("failedCount")
  let timeoutCount = summary.safeGetInt("timeoutCount")
  let verified = summary.safeGetInt("verified")

  # unresolvedCount: required nodes that reached no terminal state.
  # Terminal states: verified, failed, timedOut, blocked, preSieved, cacheHit (reusable).
  let resolvedCount = verified + failedCount + timeoutCount + blockedCount + preSievedCount + reusableCount
  let unresolvedCount = max(0, requiredCount - resolvedCount)

  # ── DAG ─────────────────────────────────────────────────
  let nodeCount = if nodeReports.kind == JArray: nodeReports.len else: 0

  # edgeCount: count nodes with dependencyDepth > 0 as a lower bound
  # on actual DAG edges (each such node has at least one parent edge).
  var edgeCount = 0
  if nodeReports.kind == JArray:
    for nr in nodeReports.elems:
      let d = nr.safeGetInt("dependencyDepth")
      if d > 0: inc edgeCount
  if edgeCount == 0 and nodeCount > 0:
    derivations.add("edgeCount=0 (all nodes at depth 0 or no nodeReports)")

  # criticalPath: max dependencyDepth + 1 across nodeReports
  var maxDepth = 0
  if nodeReports.kind == JArray:
    for nr in nodeReports.elems:
      let d = nr.safeGetInt("dependencyDepth")
      if d > maxDepth: maxDepth = d
  let criticalPath = maxDepth + 1

  # maxWidth / averageWidth from nodeReports grouped by dependencyDepth.
  var depthNodeCounts: Table[int, int] = initTable[int, int]()
  if nodeReports.kind == JArray:
    for nr in nodeReports.elems:
      let d = nr.safeGetInt("dependencyDepth")
      depthNodeCounts[d] = depthNodeCounts.getOrDefault(d) + 1

  var maxWidth = 0
  var totalWidth = 0
  var depthCount = 0
  for d, cnt in depthNodeCounts.pairs:
    if cnt > maxWidth: maxWidth = cnt
    totalWidth += cnt
    inc depthCount
  let averageWidth = if depthCount > 0: float(totalWidth) / float(depthCount) else: 0.0

  if nodeReports.kind != JArray:
    derivations.add("maxWidth/averageWidth fallback to 0 (nodeReports absent or not an array)")
  if not nodeReportsOverride.isNil:
    derivations.add("DAG computed over merged per-wave nodeReports (" & $nodeCount &
      " distinct units) — last-wave merge defect compensated (DEBT#458)")

  # ── Time ──────────────────────────────────────────────────────
  let totalWallMs = if waveStats.provided: waveStats.totalWallMs
                    else: execStats.safeGetInt("totalWallTimeMs")
  let totalSolverMs = if waveStats.provided: waveStats.totalSolverMs
                      else: execStats.safeGetInt("totalSolverTimeMs")
  let serialBaselineMs = if waveStats.provided: waveStats.serialBaselineMs
                         else: execStats.safeGetInt("serialBaselineMs")

  # planningMs and cacheClassificationMs are not directly available.
  let planningMs = totalWallMs - totalSolverMs
  let cacheClassificationMs = 0  # not instrumented in the report
  let freshExecutionMs = totalSolverMs
  let reductionMs = serialBaselineMs - totalWallMs  # positive = parallelism saved time

  # ── Assemble ──────────────────────────────────────────────────
  result.experiment = "phase_x0_execution_accounting"
  result.branch = gitBranch()
  result.head = gitHead()
  result.timestamp = isoNow()
  result.command = "AXIOM_CI=1 bin/ax prove --limit 25 (full-frontier, clean state)"
  result.Plan = X0Plan(
    universeCount: universeCount,
    requiredCount: requiredCount,
    reusableCount: reusableCount,
    preSievedCount: preSievedCount,
    freshCount: freshCount
  )
  result.Execution = X0Execution(
    invocationCount: invocationCount,
    cacheHitCount: cacheHitCount,
    blockedCount: blockedCount,
    failedCount: failedCount,
    timeoutCount: timeoutCount,
    unresolvedCount: unresolvedCount
  )
  result.DAG = X0DAG(
    nodeCount: nodeCount,
    edgeCount: edgeCount,
    criticalPath: criticalPath,
    maxWidth: maxWidth,
    averageWidth: averageWidth
  )
  result.Time = X0Time(
    planningMs: planningMs,
    cacheClassificationMs: cacheClassificationMs,
    freshExecutionMs: freshExecutionMs,
    reductionMs: reductionMs,
    totalWallMs: totalWallMs
  )
  result.derivations = derivations

# ── Case classification ──────────────────────────────────────────

proc classifyCase*(x0: var X0Accounting) =
  ## Classify the execution-accounting case (A–E/unclassified)
  ## using the measured numbers and the Phase X brief rules.
  let p = x0.Plan
  let e = x0.Execution
  let d = x0.DAG
  let t = x0.Time

  # Guard: zero genuine obligations attempted → the run reached no prover work,
  # so no Phase X cost-decomposition case (A–E) is classifiable. This is a
  # non-representative clean-state signature (all candidates no_obligation),
  # not evidence of a cache/planner/scheduler/prover bottleneck.
  if p.freshCount <= 0 and t.freshExecutionMs == 0:
    x0.Case = "unclassified"
    x0.caseRationale = "freshCount=" & $p.freshCount &
      " (canonical freshExecutionCount) and freshExecutionMs=" & $t.freshExecutionMs &
      " (totalSolverTimeMs) — the run reached no genuine proof obligation (all reachable candidates " &
      "classified no_obligation/pre-sieved). Phase X cases A–E decompose an actual " &
      "solver-cost run; with zero attempted obligations (~5 frontier candidates, " &
      "clean state) there is no prover work to decompose. Not a planner/cache/" &
      "scheduler/prover bottleneck. See derivations + report doc for the " &
      "measurement-availability limitation."
    return

  # Rule D: fresh ≥ 20 (reusable far too low) → cache admission problem
  if p.freshCount >= 20:
    x0.Case = "D"
    x0.caseRationale = "freshCount=" & $p.freshCount & " ≥ 20; reusableCount=" & $p.reusableCount &
      " is far too low relative to requiredCount=" & $p.requiredCount &
      ". Cache admission or validity window is the bottleneck."
    return

  # Rule E: planning time dominant (planningMs > totalWallMs * 0.5)
  if t.totalWallMs > 0 and float(t.planningMs) > 0.5 * float(t.totalWallMs):
    x0.Case = "E"
    x0.caseRationale = "planningMs=" & $t.planningMs & " exceeds 50% of totalWallMs=" & $t.totalWallMs &
      ". The planner is the bottleneck."
    return

  # Rule A: fresh≈required AND criticalPath≈fresh → parallelism bottleneck
  let freshRatio = if p.requiredCount > 0: float(p.freshCount) / float(p.requiredCount) else: 0.0
  let criticalPathRatio = if p.freshCount > 0: float(d.criticalPath) / float(p.freshCount) else: 0.0
  if p.freshCount > 0 and freshRatio > 0.7 and criticalPathRatio > 0.5:
    x0.Case = "A"
    x0.caseRationale = "freshCount=" & $p.freshCount & " ≈ requiredCount=" & $p.requiredCount &
      " (freshRatio=" & formatFloat(freshRatio * 100.0, ffDecimal, 0) & "%) and criticalPath=" & $d.criticalPath &
      " ≈ freshCount. Parallelism is the bottleneck."
    return

  # Rule B: fresh=12, criticalPath small, wall-clock near serial → scheduler problem
  if p.freshCount == 12 and d.criticalPath <= 3 and t.totalWallMs > 0 and
     float(t.freshExecutionMs) > 0.8 * float(t.totalWallMs):
    x0.Case = "B"
    x0.caseRationale = "freshCount=12, criticalPath=" & $d.criticalPath & " (small), and solver time " &
      $t.freshExecutionMs & "ms is " & formatFloat(float(t.freshExecutionMs)/float(t.totalWallMs)*100.0, ffDecimal, 0) &
      "% of wall time " & $t.totalWallMs & "ms → near-serial execution suggests scheduler problem."
    return

  # Rule C: fresh=12, criticalPath small, parallel utilization high, per-invocation slow → prover/engine problem
  if p.freshCount == 12 and d.criticalPath <= 3 and t.totalWallMs > 0 and
     float(t.freshExecutionMs) > 0 and float(t.freshExecutionMs) / float(t.totalWallMs) < 0.5:
    x0.Case = "C"
    x0.caseRationale = "freshCount=12, criticalPath=" & $d.criticalPath & " (small), parallel utilization " &
      "high (solver time " & $t.freshExecutionMs & "ms is only " &
      formatFloat(float(t.freshExecutionMs)/float(t.totalWallMs)*100.0, ffDecimal, 0) & "% of wall " & $t.totalWallMs &
      "ms), but per-invocation slow → prover/engine problem."
    return

  # Unclassified
  x0.Case = "unclassified"
  x0.caseRationale = "No case rule matched. freshCount=" & $p.freshCount &
    ", criticalPath=" & $d.criticalPath &
    ", totalWallMs=" & $t.totalWallMs &
    ", totalSolverMs=" & $t.freshExecutionMs &
    ". Data is ambiguous; further analysis needed."

# ── Legacy projection (STRUCTURAL ISOLATION) ─────────────────────

proc parseLegacyClosure*(report: JsonNode): JsonNode {.raises: [CatchableError].} =
  ## Legacy projection — reads ONLY the merged report's closure block.
  ##
  ## STRUCTURAL ISOLATION: the canonical reducer never receives these fields;
  ## this is a separate parse path for the legacy projection only.
  ##
  ## Limitations (documented, not canonical):
  ##  - completedCount is a MIXED aggregate (Verified+NoObligation+InductiveValid —
  ##    closure_evaluation.nim:66-68), not a canonical satisfaction count.
  ##  - The merged report carries only the LAST wave's nodeReports+executionStats
  ##    (last-wave merge defect — axiom_engine.nim:1049-1059), so these numbers
  ##    are not a run-wide accounting.
  let closure = report{"closure"}
  let completedCount = if closure.isNil: 0 else: closure.safeGetInt("completedCount")
  let requiredCount = if closure.isNil: 0 else: closure.safeGetInt("requiredCount")
  var uncompleted: seq[string] = @[]
  if not closure.isNil:
    let u = closure{"uncompletedRequired"}
    if not u.isNil and u.kind == JArray:
      for x in u.elems:
        if x.kind == JString: uncompleted.add(x.getStr())
  let closureComplete = if closure.isNil: false else: closure.safeGetBool("closureComplete")
  result = %*{
    "legacyCompletedCount": completedCount,
    "legacyUncompletedRequiredCount": uncompleted.len,
    "legacyClosureComplete": closureComplete,
    "note": "LEGACY projection only — completedCount is a mixed aggregate " &
      "(Verified+NoObligation+InductiveValid, closure_evaluation.nim:66-68) and the merged " &
      "report carries only the last wave's nodeReports+executionStats (last-wave merge " &
      "defect, axiom_engine.nim:1049-1059). Not canonical; see the canonical block."
  }

# ── Trajectory source (temporary measurement compensation) ────────

proc loadTrajectory*(path: string): seq[JsonNode] {.raises: [CatchableError].} =
  ## Parse the trajectory JSONL into records.
  result = @[]
  if not fileExists(path): return
  for line in readFile(path).splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0: continue
    try:
      result.add(parseJson(trimmed))
    except CatchableError:
      discard  # skip malformed lines

proc recordTsMs(rec: JsonNode): int64 =
  ## Record timestamp → epoch milliseconds (0 when unparseable).
  let ts = rec.safeGetStr("ts")
  if ts.len == 0: return 0
  try:
    let dt = parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
    result = dt.toTime().toUnix() * 1000 + dt.nanosecond div 1_000_000
  except CatchableError:
    result = 0

proc segmentRuns*(records: seq[JsonNode]): seq[seq[JsonNode]] {.raises: [].} =
  ## Group skReport records that embed a per-wave report (`extra`) into runs.
  ## A run is a maximal cluster of consecutive wave records whose timestamps are
  ## < 60s apart (the wave loop re-logs skCliEntry per wave, so CLI-entry
  ## segmentation is not usable; wave records of one invocation are seconds apart,
  ## distinct invocations are minutes apart).
  var waveRecords: seq[JsonNode] = @[]
  for rec in records:
    if rec.safeGetStr("phase") != "skReport": continue
    let extra = rec{"extra"}
    if extra.isNil or extra.kind != JObject: continue
    waveRecords.add(rec)
  result = @[]
  var cur: seq[JsonNode] = @[]
  var prevTs = 0'i64
  for w in waveRecords:
    let t = recordTsMs(w)
    if cur.len > 0 and (prevTs == 0 or t - prevTs >= 60_000):
      result.add(cur)
      cur = @[]
    cur.add(w)
    prevTs = t
  if cur.len > 0: result.add(cur)

proc waveExtras(run: seq[JsonNode]): seq[JsonNode] {.raises: [].} =
  ## Extract the per-wave report objects (`extra`) from a run's records.
  result = @[]
  for rec in run:
    let extra = rec{"extra"}
    if not extra.isNil and extra.kind == JObject:
      result.add(extra)

proc sumWaveStats*(waves: seq[JsonNode]): X0WaveStats {.raises: [].} =
  ## Cross-wave sums of executionStats/summary numbers (last-wave defect
  ## compensation — DEBT#458).
  result.provided = true
  for w in waves:
    let es = w{"executionStats"}
    if not es.isNil:
      result.invocationCount += es.safeGetInt("solverInvocationCount")
      result.cacheHitCount += es.safeGetInt("cacheHitCount")
      result.obligationAttemptedCount += es.safeGetInt("obligationAttemptedCount")
      result.totalWallMs += es.safeGetInt("totalWallTimeMs")
      result.totalSolverMs += es.safeGetInt("totalSolverTimeMs")
      result.serialBaselineMs += es.safeGetInt("serialBaselineMs")
    let s = w{"summary"}
    if not s.isNil:
      result.preSievedCount += s.safeGetInt("preSieved")

proc mergeNodeReports*(waves: seq[JsonNode]): JsonNode {.raises: [].} =
  ## Merge per-wave nodeReports into a deduped (by nodeId) array — the merged
  ## report carries only the last wave (DEBT#458).
  var seen: Table[string, bool] = initTable[string, bool]()
  result = newJArray()
  for w in waves:
    let nr = w{"nodeReports"}
    if nr.isNil or nr.kind != JArray: continue
    for n in nr.elems:
      if n.isNil or n.kind != JObject: continue
      let uid = n.safeGetStr("nodeId")
      if uid.len == 0 or seen.hasKey(uid): continue
      seen[uid] = true
      result.add(n)

# ── I/O ───────────────────────────────────────────────────────────

proc loadReport*(path: string): JsonNode =
  if not fileExists(path):
    quit("ERROR: report file not found: " & path, 1)
  let content = readFile(path)
  try:
    parseJson(content)
  except CatchableError as e:
    quit("ERROR: failed to parse report JSON: " & e.msg, 1)

proc loadState*(path: string): JsonNode =
  if fileExists(path):
    let content = readFile(path)
    try: parseJson(content)
    except CatchableError: newJObject()
  else:
    newJObject()

proc writeOutput*(x0: X0Accounting; canonical: JsonNode; legacy: JsonNode;
                  measurementSource: MeasurementSource; path: string) =
  let dir = path.parentDir()
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  # measurementCompensated is DERIVED from the measurement source: only
  # trajectory reconstruction compensates for a missing canonical boundary.
  let measurementCompensated = measurementSource == TrajectoryReconstruction
  let compensationSource = $measurementSource
  let j = %*{
    "schemaVersion": SchemaVersion,
    "toolVersion": ToolVersion,
    "experiment": x0.experiment,
    "measurementSource": $measurementSource,
    "measurementCompensated": measurementCompensated,
    "compensationSource": compensationSource,
    "branch": x0.branch,
    "head": x0.head,
    "timestamp": x0.timestamp,
    "command": x0.command,
    "canonical": canonical,
    "legacy": legacy,
    "Plan": %*{
      "universeCount": x0.Plan.universeCount,
      "requiredCount": x0.Plan.requiredCount,
      "reusableCount": x0.Plan.reusableCount,
      "preSievedCount": x0.Plan.preSievedCount,
      "freshCount": x0.Plan.freshCount
    },
    "Execution": %*{
      "invocationCount": x0.Execution.invocationCount,
      "cacheHitCount": x0.Execution.cacheHitCount,
      "blockedCount": x0.Execution.blockedCount,
      "failedCount": x0.Execution.failedCount,
      "timeoutCount": x0.Execution.timeoutCount,
      "unresolvedCount": x0.Execution.unresolvedCount
    },
    "DAG": %*{
      "nodeCount": x0.DAG.nodeCount,
      "edgeCount": x0.DAG.edgeCount,
      "criticalPath": x0.DAG.criticalPath,
      "maxWidth": x0.DAG.maxWidth,
      "averageWidth": x0.DAG.averageWidth
    },
    "Time": %*{
      "planningMs": x0.Time.planningMs,
      "cacheClassificationMs": x0.Time.cacheClassificationMs,
      "freshExecutionMs": x0.Time.freshExecutionMs,
      "reductionMs": x0.Time.reductionMs,
      "totalWallMs": x0.Time.totalWallMs
    },
    "Case": x0.Case,
    "caseRationale": x0.caseRationale,
    "derivations": x0.derivations
  }
  writeFile(path, j.pretty())

# ── Main ──────────────────────────────────────────────────────────

when isMainModule:
  let args = commandLineParams()
  if args.len < 1:
    stderr.writeLine("Usage: phase_x0_accounting <report.json> [--output <out.json>] " &
      "[--state <ax_proof_state.json>] [--trajectory <ax_prove_trajectory.jsonl>] [--run <N>]")
    quit(1)

  var reportPath = args[0]
  var outputPath = DefaultOutputPath
  var statePath = "logs/ax_proof_state.json"
  var trajectoryPath = DefaultTrajectoryPath
  var runIndex = 0

  var i = 1
  while i < args.len:
    case args[i]
    of "--output":
      if i + 1 < args.len: inc i; outputPath = args[i]
    of "--state":
      if i + 1 < args.len: inc i; statePath = args[i]
    of "--trajectory":
      if i + 1 < args.len: inc i; trajectoryPath = args[i]
    of "--run":
      if i + 1 < args.len:
        inc i
        try: runIndex = parseInt(args[i])
        except ValueError: runIndex = 0
    else:
      reportPath = args[i]
    inc i

  let report = loadReport(reportPath)
  let state = loadState(statePath)

  # ── X1 canonical source: production report (measurementSource=production_canonical) ──
  # The merged report now carries runAccounting/runOutcome — the canonical
  # boundary is installed (DEBT#458 closed), so the accounting is read directly
  # from the report with NO trajectory compensation.
  let productionCanonical = report{"runAccounting"}
  if productionCanonical != nil and productionCanonical.kind == JObject:
    let canonical = productionCanonical
    let canonicalJson = canonical
    let freshCount = canonical.safeGetInt("freshExecutionCount", -1)
    let mergedNodeReports = report{"nodeReports"}
    # X0 blocks read the merged report directly (waveStats not provided): the
    # report's nodeReports/executionStats are now the cross-wave canonical
    # aggregate, not the last-wave snapshot.
    var x0 = computeX0(report, state, X0WaveStats(), freshCount, mergedNodeReports)
    classifyCase(x0)
    let legacy = parseLegacyClosure(report)
    writeOutput(x0, canonicalJson, legacy, ProductionCanonical, outputPath)
    stdout.writeLine("[phase_x0] production-canonical source: report runAccounting " &
      "(measurementSource=production_canonical, measurementCompensated=false)")
    stdout.writeLine("[phase_x0] canonical: required=" & $canonical.safeGetInt("requiredCount") &
      " contested=" & $canonical.safeGetInt("contestedCount") &
      " unsatisfied=" & $canonical.safeGetInt("unsatisfiedCount") &
      " unresolved=" & $canonical.safeGetInt("unresolvedDecisionCount") &
      " freshExecution=" & $canonical.safeGetInt("freshExecutionCount") &
      " verdict=" & report{"runOutcome"}.safeGetStr("verdict", "") &
      " basis=" & report{"runOutcome"}.safeGetStr("basis", "") &
      " GateVerdict=" & report{"runOutcome"}.safeGetStr("gateVerdict", "") &
      " verificationComplete=" & $report{"runOutcome"}.safeGetBool("verificationComplete"))
    stdout.writeLine("[phase_x0] Wrote X1.0 accounting to: " & outputPath)
    quit(0)

  # ── X1.0 canonical source fallback: trajectory (measurementSource=trajectory_reconstruction) ──
  let records = loadTrajectory(trajectoryPath)
  let runs = segmentRuns(records)
  if runs.len == 0:
    stderr.writeLine("ERROR: report carries no runAccounting (pre-X1 document) and no per-wave " &
      "reports found in trajectory: " & trajectoryPath &
      " — cannot produce a canonical X1.0 accounting (last-wave merge defect needs " &
      "per-wave compensation). If the trajectory is unusable, regenerate from the merged " &
      "report alone (/tmp/x0_real_full_report.json) with measurementCompensated=false.")
    quit(1)
  let idx = min(runIndex, runs.len - 1)
  let run = runs[runs.len - 1 - idx]
  let waves = waveExtras(run)
  stdout.writeLine("[phase_x0] trajectory run #" & $idx & " (from end): " & $waves.len &
    " wave(s) — " & run[0].safeGetStr("ts"))

  let eligibility = report{"eligibility"}
  let canonical = reduceRunAccounting(waves, eligibility)
  let canonicalJson = canonical.toJson()
  let legacy = parseLegacyClosure(report)
  let waveStats = sumWaveStats(waves)
  let mergedNodeReports = mergeNodeReports(waves)

  var x0 = computeX0(report, state, waveStats, canonical.freshExecutionCount, mergedNodeReports)
  classifyCase(x0)

  # Plan 1 — INV-X1 inversion: the trajectory-reconstruction path (pre-X1
  # measurement compensation) applies the VDA run-level verdict to the
  # reconstructed raw state; the reconstruction runs with the fail-closed
  # default reuse context (cache-hit rows without a verifiable reuse record
  # are PENDING) — the verdict is decided here, never in the reducer.
  let noObligation = NoObligationProvenance(
    universeEnumerated: not eligibility.isNil and eligibility.kind == JObject and
                        eligibility.len > 0,
    source: "trajectory_ogr_eligibility")
  let factGateActive = (report{"blockedNodes"} != nil and
                        report{"blockedNodes"}.kind == JArray and
                        report{"blockedNodes"}.len > 0)
  let runOutcome = evaluateRunOutcome(canonical, noObligation, factGateActive)

  writeOutput(x0, canonicalJson, legacy, TrajectoryReconstruction, path = outputPath)
  stdout.writeLine("[phase_x0] trajectory-reconstruction source (measurementCompensated=true): " & outputPath)
  stdout.writeLine("[phase_x0] Wrote X1.0 accounting to: " & outputPath)
  stdout.writeLine("[phase_x0] canonical: required=" & $canonical.requiredCount &
    " contested=" & $canonical.contestedCount &
    " unsatisfied=" & $canonical.unsatisfiedCount &
    " unresolved=" & $canonical.unresolvedDecisionCount &
    " freshExecution=" & $canonical.freshExecutionCount &
    " verdict=" & $runOutcome.verdict &
    " basis=" & $runOutcome.basis &
    " GateVerdict=" & $gateVerdictProjection(runOutcome) &
    " verificationComplete=" & $runOutcome.verificationComplete)
  quit(0)
