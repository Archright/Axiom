import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## gate_run_logger.nim — Zero-Jitter Telemetry Pipeline
##
## In-memory gate execution telemetry with batch flush at pipeline end.
## No file I/O during pipeline execution — all records accumulate in
## a value-type seq, flushed atomically on completion.
##
## Design Principles:
##   1. Zero-Jitter: seq[GateRunRecord] memory-only during execution
##   2. Immutable Context: RunContext created once at boot (git info frozen)
##   3. Zero-allocation serialization: fieldPairs + appendEscapedJson streaming
##
## See: docs/spec/precommit_pipeline_optimization.md

import core/interfaces/git_operations
import core/trusted/axiom_pragmas_lite
import std/[os, strutils, strformat, times, algorithm]

let gitExe = git_operations.findRealGit()

# ─── Value Types ────────────────────────────────────────────────────────────

type
  RunContext* = object
    ## Immutable execution context — created once at boot.
    stage*: string        ## "pre-commit" | "pre-push"
    commit*: string       ## "742649592" (short SHA)
    branch*: string       ## "core"
    stagedFiles*: int     ## number of staged files
    epoch*: int           ## gate memo epoch
    ts*: string           ## ISO8601 execution start timestamp

  GateRunRecord* = object
    ## Per-gate execution record — value type, accumulated in seq.
    gateId*: string
    result*: string       ## "pass" | "fail" | "skip" | "timeout" | "cached"
    durationNs*: int64    ## nanoseconds (monotimes)
    cached*: bool
    tier*: int
    dagLayer*: int
    outputFile*: string   ## .axiom/cache/gate_output/{gateId}.log (fail only)
    skipReason*: string   ## Why the gate was cached/skipped: "cache_hit", "inputFiles_changed", "toolchain_mismatch", "no_memo", etc.
    exitCode*: int        ## Process/native exit code, separate from `result` (diagnostic, not verdict).
                          ## `result` is the canonical verdict ("pass"/"fail"/...); exitCode is the raw
                          ## subprocess termination code behind it (0 on pass, signal number or 1 on
                          ## crash/fail). Kept separate so a failed gate's exit code is not conflated
                          ## with a timeout/skip. Zero = unset/unknown.
    terminationReason*: string ## How the gate ended, independent of verdict: "", "timeout", "signal", "error", "success".
    argv*: string         ## Canonicalized command vector (space-joined, repr). Diagnostic only — never input to identity.
    cwd*: string          ## Working directory of the gate execution (relative to repo root when possible).
    executionFingerprint*: string ## sha256 over the allowlisted execution env + argv (see §P3c audit).
                                 ## Diagnostic trace only — MUST NOT feed evidence/identity computation.
    allowlistedEnvJson*: string  ## Compact JSON of an explicit allowlist of env vars (never raw full env;
                                 ## no secrets). Diagnostic only.

  RunSummary* = object
    ## Aggregated pipeline run summary — written to gate_runs/.
    ts*: string
    stage*: string
    commit*: string
    branch*: string
    stagedFiles*: int
    epoch*: int
    totalDurationNs*: int64
    gatesTotal*: int
    gatesPassed*: int
    gatesFailed*: int
    gatesSkipped*: int
    dagLayers*: int
    topBottleneck*: string
    topBottleneckNs*: int64
    cacheHitRate*: float
    gates*: seq[GateRunRecord]

  TelemetryBuffer* = object
    ## Pipeline-scoped telemetry buffer. Collects records in memory,
    ## flushed to disk once at pipeline end.
    ctx*: RunContext
    records*: seq[GateRunRecord]
    totalDurationNs*: int64
    bottleneck*: string
    bottleneckNs*: int64

# ─── Initialization ─────────────────────────────────────────────────────────

proc getCurrentCommit*(): string =
  ## Get short git SHA (7 chars). Called once at boot.
  try:
    let (output, exitCode) = git_operations.runGitEx(gitExe, "rev-parse --short=7 HEAD")
    if exitCode == 0:
      return output.strip()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return "unknown"

proc getCurrentBranch*(): string =
  ## Get current branch name. Called once at boot.
  try:
    let (output, exitCode) = git_operations.runGitEx(gitExe, "rev-parse --abbrev-ref HEAD")
    if exitCode == 0:
      return output.strip()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return "unknown"

proc initContext*(stage: string; stagedFiles: int; epoch: int): RunContext =
  ## Create immutable RunContext. Git info queried once here.
  RunContext(
    stage: stage,
    commit: getCurrentCommit(),
    branch: getCurrentBranch(),
    stagedFiles: stagedFiles,
    epoch: epoch,
    ts: $now()
  )

proc initTelemetry*(ctx: RunContext): TelemetryBuffer =
  ## Create TelemetryBuffer with pre-allocated capacity.
  TelemetryBuffer(
    ctx: ctx,
    records: newSeqOfCap[GateRunRecord](30),
    totalDurationNs: 0,
    bottleneck: "",
    bottleneckNs: 0
  )

# ─── Record Collection (Memory-Only) ────────────────────────────────────────

proc logGate*(
  buf: var TelemetryBuffer;
  gateId: string;
  result: string;
  durationNs: int64;
  cached: bool = false;
  tier: int = 1;
  dagLayer: int = 0;
  outputFile: string = "";
  skipReason: string = "";
  exitCode: int = 0;
  terminationReason: string = "";
  argv: string = "";
  cwd: string = "";
  executionFingerprint: string = "";
  allowlistedEnvJson: string = ""
) =
  ## Append a gate execution record. Memory-only — no file I/O.
  ## `exitCode`/`terminationReason`/`argv`/`cwd`/`executionFingerprint`/`allowlistedEnvJson`
  ## are diagnostic trace fields, deliberately absent by default so existing
  ## callers that carry no subprocess detail keep working unchanged. They must
  ## never feed evidence/identity computation (see §P3c audit note).
  let record = GateRunRecord(
    gateId: gateId,
    result: result,
    durationNs: durationNs,
    cached: cached,
    tier: tier,
    dagLayer: dagLayer,
    outputFile: outputFile,
    skipReason: skipReason,
    exitCode: exitCode,
    terminationReason: terminationReason,
    argv: argv,
    cwd: cwd,
    executionFingerprint: executionFingerprint,
    allowlistedEnvJson: allowlistedEnvJson
  )
  buf.records.add(record)
  buf.totalDurationNs += durationNs
  # Track bottleneck
  if durationNs > buf.bottleneckNs:
    buf.bottleneckNs = durationNs
    buf.bottleneck = gateId

# ─── JSON Serialization (Zero-allocation streaming) ─────────────────────────

proc appendEscapedJson*(target: var string; s: string) =
  ## Append a JSON-escaped string directly to target buffer.
  ## No intermediate heap allocation.
  target.add('"')
  for c in s:
    case c
    of '"': target.add("\\\"")
    of '\\': target.add("\\\\")
    of '\n': target.add("\\n")
    of '\r': target.add("\\r")
    of '\t': target.add("\\t")
    else:
      if c < ' ':
        target.add("\\u00")
        target.add(toHex(cast[byte](c), 2))
      else:
        target.add(c)
  target.add('"')

proc appendJsonInt*(target: var string; name: string; val: int64) =
  ## Append a JSON integer field.
  target.add('"')
  target.add(name)
  target.add("\":")
  target.add($val)

proc appendJsonBool*(target: var string; name: string; val: bool) =
  ## Append a JSON boolean field.
  target.add('"')
  target.add(name)
  target.add("\":")
  target.add(if val: "true" else: "false")

proc appendJsonString*(target: var string; name: string; val: string) =
  ## Append a JSON string field.
  target.add('"')
  target.add(name)
  target.add("\":")
  appendEscapedJson(target, val)

proc toJsonl*(r: GateRunRecord; ctx: RunContext): string =
  ## Serialize a GateRunRecord + RunContext to a single JSONL line.
  ## Uses streaming append — no std/json, no intermediate allocations.
  result = newStringOfCap(256)
  result.add('{')
  appendJsonString(result, "ts", ctx.ts)
  result.add(',')
  appendJsonString(result, "stage", ctx.stage)
  result.add(',')
  appendJsonString(result, "commit", ctx.commit)
  result.add(',')
  appendJsonString(result, "branch", ctx.branch)
  result.add(',')
  appendJsonInt(result, "stagedFiles", ctx.stagedFiles.int64)
  result.add(',')
  appendJsonInt(result, "epoch", ctx.epoch.int64)
  result.add(',')
  appendJsonString(result, "gateId", r.gateId)
  result.add(',')
  appendJsonString(result, "result", r.result)
  result.add(',')
  appendJsonInt(result, "durationNs", r.durationNs)
  result.add(',')
  appendJsonBool(result, "cached", r.cached)
  result.add(',')
  appendJsonInt(result, "tier", r.tier.int64)
  result.add(',')
  appendJsonInt(result, "dagLayer", r.dagLayer.int64)
  # Diagnostic trace fields (emitted only when populated — zero-latency for
  # the common case that carries no subprocess detail). Never identity inputs.
  if r.exitCode != 0:
    result.add(',')
    appendJsonInt(result, "exitCode", r.exitCode.int64)
  if r.terminationReason.len > 0:
    result.add(',')
    appendJsonString(result, "terminationReason", r.terminationReason)
  if r.argv.len > 0:
    result.add(',')
    appendJsonString(result, "argv", r.argv)
  if r.cwd.len > 0:
    result.add(',')
    appendJsonString(result, "cwd", r.cwd)
  if r.executionFingerprint.len > 0:
    result.add(',')
    appendJsonString(result, "executionFingerprint", r.executionFingerprint)
  if r.allowlistedEnvJson.len > 0:
    result.add(',')
    appendJsonString(result, "allowlistedEnvJson", r.allowlistedEnvJson)
  if r.outputFile.len > 0:
    result.add(',')
    appendJsonString(result, "outputFile", r.outputFile)
  if r.skipReason.len > 0:
    result.add(',')
    appendJsonString(result, "skipReason", r.skipReason)
  result.add('}')

proc computeSummaryJson*(buf: TelemetryBuffer): string =
  ## Compute and serialize the run summary as a JSON string.
  var passed, failed, skipped = 0
  var layers = 0
  for r in buf.records:
    case r.result
    of "pass": inc passed
    of "fail", "timeout": inc failed
    of "skip": inc skipped
    else: discard
    if r.dagLayer > layers:
      layers = r.dagLayer
  let total = buf.records.len
  let cacheHits = block:
    var n = 0
    for r in buf.records:
      if r.cached: inc n
    n
  let hitRate = if total > 0: cacheHits.float / total.float else: 0.0

  result = newStringOfCap(512)
  result.add('{')
  appendJsonString(result, "ts", buf.ctx.ts)
  result.add(',')
  appendJsonString(result, "stage", buf.ctx.stage)
  result.add(',')
  appendJsonString(result, "commit", buf.ctx.commit)
  result.add(',')
  appendJsonString(result, "branch", buf.ctx.branch)
  result.add(',')
  appendJsonInt(result, "stagedFiles", buf.ctx.stagedFiles.int64)
  result.add(',')
  appendJsonInt(result, "epoch", buf.ctx.epoch.int64)
  result.add(',')
  appendJsonInt(result, "totalDurationNs", buf.totalDurationNs)
  result.add(',')
  appendJsonInt(result, "gatesTotal", total.int64)
  result.add(',')
  appendJsonInt(result, "gatesPassed", passed.int64)
  result.add(',')
  appendJsonInt(result, "gatesFailed", failed.int64)
  result.add(',')
  appendJsonInt(result, "gatesSkipped", skipped.int64)
  result.add(',')
  appendJsonInt(result, "dagLayers", (layers + 1).int64)
  result.add(',')
  appendJsonString(result, "topBottleneck", buf.bottleneck)
  result.add(',')
  appendJsonInt(result, "topBottleneckNs", buf.bottleneckNs)
  result.add(',')
  # cacheHitRate as float with 3 decimal places
  result.add("\"cacheHitRate\":")
  result.add(&"{hitRate:.3f}")
  result.add(',')

  # gates array (compact — gateId + result + durationNs only)
  result.add("\"gates\":[")
  for i, r in buf.records:
    if i > 0: result.add(',')
    result.add('{')
    appendJsonString(result, "gateId", r.gateId)
    result.add(',')
    appendJsonString(result, "result", r.result)
    result.add(',')
    appendJsonInt(result, "durationNs", r.durationNs)
    if r.cached:
      result.add(',')
      appendJsonBool(result, "cached", true)
    if r.skipReason.len > 0:
      result.add(',')
      appendJsonString(result, "skipReason", r.skipReason)
    result.add('}')
  result.add("]}")

# ─── Disk Flush (Atomic, crash-safe) ────────────────────────────────────────

proc gcOldRuns*(dir: string; maxAge: int = 30; maxCount: int = 100) {.axiomEffect: IOEffect.} =
  ## GC old run summary files. Keep at most maxCount files or maxAge days.
  try:
    let runsDir = dir / "gate_runs"
    if not dirExists(runsDir):
      return
    var files: seq[string] = @[]
    for kind, path in walkDir(runsDir):
      if kind == pcFile and path.endsWith(".json"):
        files.add(path)
    files.sort() # lexicographic = chronological (ISO8601 prefix)
    # Remove by count
    if files.len > maxCount:
      for i in 0..<(files.len - maxCount):
        try: removeFile(files[i])
        except CatchableError: discard  # axiom:best-effort(ioboundary catch)
    # Remove by age
    let cutoff = getTime() - initDuration(days = maxAge)
    for f in files:
      try:
        let modTime = getFileInfo(f).lastWriteTime
        if modTime < cutoff:
          removeFile(f)
      except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc rotateHistoryJsonl*(path: string; maxSize: int64 = 1_048_576) {.axiomEffect: IOEffect.} =
  ## Rotate gate_history.jsonl if it exceeds maxSize (default 1MB).
  try:
    if not fileExists(path):
      return
    if getFileSize(path) > maxSize:
      let rotated = path & ".1"
      if fileExists(rotated):
        removeFile(rotated)
      copyFile(path, rotated)
      removeFile(path)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc flushToDisk*(buf: TelemetryBuffer) {.axiomEffect: IOEffect.} =
  ## Flush all collected records to disk. Called once at pipeline end.
  ## 1. Append to gate_history.jsonl (append mode)
  ## 2. Write run summary to gate_runs/ (temp+rename atomic)
  ## 3. GC old runs
  if buf.records.len == 0:
    return

  let dir = ".axiom"
  try:
    createDir(dir)
    createDir(dir / "gate_runs")
  except CatchableError:
    return

  # 1. Append records to gate_history.jsonl
  let historyPath = dir / "gate_history.jsonl"
  try:
    var f = open(historyPath, fmAppend)
    defer: close(f)
    for r in buf.records:
      f.writeLine(toJsonl(r, buf.ctx))
    f.flushFile()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  # 2. Write run summary (temp+rename for atomicity)
  let commitShort = if buf.ctx.commit.len > 7: buf.ctx.commit[0..6] else: buf.ctx.commit
  let summaryFilename = &"{buf.ctx.ts}_{buf.ctx.stage}_{commitShort}.json"
  let summaryPath = dir / "gate_runs" / summaryFilename
  let tmpPath = summaryPath & ".tmp"
  try:
    var f = open(tmpPath, fmWrite)
    defer: close(f)
    f.writeLine(computeSummaryJson(buf))
    f.flushFile()
    copyFile(tmpPath, summaryPath)
    removeFile(tmpPath)
  except CatchableError:
    # Clean up temp file on failure
    try: removeFile(tmpPath)
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)

  # 3. GC old runs + rotate history
  gcOldRuns(dir)
  rotateHistoryJsonl(historyPath)

{.pop.}

