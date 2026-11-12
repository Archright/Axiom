import core/trusted/layer_declaration


axiomLayer "gate"
{.push raises: [CatchableError].}

## Delegation Enforcer — L2 Wire-Log Loop Detector
##
## Scans Kimi Code CLI session wire logs to detect repeated no-op or
## repeated Bash commands that indicate an agent stuck in a loop.
##
## Checks:
##   1. Empty/whitespace-only Bash commands
##   2. Known no-op commands (`:`, `true`, `false`, `echo`, `printf`)
##   3. Identical consecutive Bash commands (repetition)
##
## If any session has >= ConsecutiveThreshold such calls in a row,
## the gate FAILs (exit 1).
##
## Usage:
##   delegation-enforcer                    — scan sessions from last 24h
##   delegation-enforcer --max-age 48       — scan sessions from last 48h
##   delegation-enforcer --self-test        — run built-in self-test

import std/[os, strutils, times]
import core/axiom_pragmas
import infrastructure/logging_facade
import core/parsers/safe_parsers
import core/results
import gate/gate_types
import gate/utils/gate_safety_macro
# axiomIoBoundary

const
  GateName = "delegation-enforcer"
  ConsecutiveThreshold = 3
  DefaultMaxAgeHours = 24
  KnownNoOps = [":", "true", "false", "echo", "printf"]

type
  LoopReport = object
    sessionId: string
    commands: seq[string]

func isNoOp(cmd: string): bool {.raises: [].} =
  if cmd.len == 0: return true
  let trimmed = cmd.strip()
  if trimmed.len == 0: return true
  for noop in KnownNoOps:
    if trimmed == noop or trimmed.startsWith(noop & " "):
      return true
  false

func sessionIdFromPath(path: string): string {.raises: [].} =
  let (_, name, _) = splitFile(path)
  name

const NotABashCall = "\x00"

func extractCommand(line: string): string {.raises: [].} =
  let trimmed = line.strip()
  if trimmed.len == 0: return NotABashCall
  let cmdIdx = trimmed.find("\"command\":")
  if cmdIdx >= 0:
    let start = trimmed.find('"', cmdIdx + 10)
    if start >= 0:
      let endQuote = trimmed.find('"', start + 1)
      if endQuote > start:
        return trimmed[start + 1 .. endQuote - 1]
  let bashIdx = trimmed.find("\"tool\":\"Bash\"")
  if bashIdx >= 0:
    let argIdx = trimmed.find("\"arguments\":")
    if argIdx >= 0:
      let start = trimmed.find('"', argIdx + 12)
      if start >= 0:
        let endQuote = trimmed.find('"', start + 1)
        if endQuote > start:
          return trimmed[start + 1 .. endQuote - 1]
  NotABashCall

proc scanWireLogFallback(path: string): LoopReport {.raises: [].} =
  var consecutive = 0
  var sessionCommands: seq[string] = @[]
  let content = try: readFile(path) except IOError: ""
  for line in content.splitLines():
    let cmd = extractCommand(line)
    if cmd == NotABashCall:
      consecutive = 0
      continue
    sessionCommands.add(cmd)
    if isNoOp(cmd):
      consecutive.inc
    else:
      consecutive = 0
    if consecutive >= ConsecutiveThreshold:
      return LoopReport(sessionId: sessionIdFromPath(path), commands: sessionCommands)
  LoopReport(sessionId: sessionIdFromPath(path), commands: @[])

proc scanWireLog(path: string): LoopReport {.raises: [].} =
  try:
    let content = readFile(path)
    scanWireLogFallback(path)
  except CatchableError:
    LoopReport(sessionId: sessionIdFromPath(path), commands: @[])

proc collectSessionLogs(maxAgeHours: int = DefaultMaxAgeHours): seq[string] {.raises: [CatchableError].} =
  var logs: seq[string] = @[]
  let dataDir = "data"
  if not dirExists(dataDir): return logs
  let cutoff = getTime() - initDuration(hours = maxAgeHours)
  for f in walkDirRec(dataDir):
    if f.endsWith(".log") or f.endsWith(".json"):
      try:
        let info = getFileInfo(f)
        if info.lastWriteTime >= cutoff:
          logs.add(f)
      except CatchableError:
        logs.add(f)
  logs

proc runScan(logs: seq[string]): bool =
  for log in logs:
    let report = scanWireLog(log)
    if report.commands.len >= ConsecutiveThreshold:
      return false
  true

proc selfTest() =
  doAssert isNoOp("")
  doAssert isNoOp("   ")
  doAssert isNoOp(":")
  doAssert isNoOp("true")
  doAssert not isNoOp("nim c src/main.nim")
  # splitFile().name excludes the extension (latent assert bug — unreachable
  # while main() was never invoked; surfaced by the DEBT#497 real-main wiring).
  doAssert sessionIdFromPath("data/session_abc.json") == "session_abc"
  doAssert extractCommand("\"command\": \"ls\"") == "ls"
  echo "self-test PASS"

func parseMaxAge(args: seq[string]): int =
  var i = 0
  while i < args.len:
    if args[i] == "--max-age" and i + 1 < args.len:
      let ageRes = safeParseInt(args[i + 1])
      return (if ageRes.isOk: ageRes.get else: DefaultMaxAgeHours)
    i.inc
  DefaultMaxAgeHours

# ─── Judgment SSOT (DEBT#497 follow-up) ───────────────────────────────────

proc judgeWireLogs*(dataDir: string, maxAgeHours: int): GateResult {.raises: [CatchableError].} =
  ## The single judgment: scan dataDir for recent session wire logs and fail on
  ## repeated no-op command loops. main() and the in-process adapter both
  ## delegate here — one verdict SSOT, no duplicated scan semantics.
  let logs = collectSessionLogs(maxAgeHours)
  if logs.len == 0:
    return GateResult(
      ok: true, name: GateName,
      stdout: "No session logs found in " & dataDir & " — infrastructure absent, fail-open.",
      skipCiRequested: false)
  if runScan(logs):
    return GateResult(
      ok: true, name: GateName,
      stdout: "PASS — no repeated no-op commands detected",
      skipCiRequested: false)
  # "FAIL" marker line: the orchestrator's classifyFailure extracts reason
  # lines by the "FAIL" substring — without it the memo layer records this
  # verdict as moNotEvaluated and a FAIL would never replay as FAIL_CACHED
  # (DEBT#471 verdict-axis durability lesson).
  return GateResult(
    ok: false, name: GateName,
    stdout: "FAIL delegation-enforcer: repeated no-op commands detected in wire logs",
    failureCategory: fcValidation,
    failureReason: "repeated no-op commands detected in wire logs",
    skipCiRequested: false)

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let args = commandLineParams()
  if args.len > 0 and args[0] == "--self-test":
    selfTest()
    quit(0)
  let res = judgeWireLogs("data", parseMaxAge(args))
  if res.ok:
    logInfo(GateName, res.stdout)
  else:
    logError(GateName, res.stdout)
  quit(if res.ok: 0 else: 1)

# ─── In-Process Adapter (DEBT#497 follow-up) ──────────────────────────────

proc runInProcess*(ctx: InProcessGateContext): GateResult {.gcsafe, raises: [].} =
  ## InProcessGateProc-shaped adapter over judgeWireLogs (DEBT#497 follow-up).
  ## main() was never invoked at top level, so any standalone AOT link of this
  ## module produced an empty 32,192-byte exit-0 binary — the subprocess CAS
  ## path ran nothing and reported PASS. The allowlisted in-process path is
  ## the enforcement path. The subprocess contract scans <cwd>/data with
  ## workingDir=repoRoot (executor.nim startProcess), so ctx.repoRoot/"data"
  ## is the SAME judgment input.
  try:
    result = judgeWireLogs(ctx.repoRoot / "data", DefaultMaxAgeHours)
  except CatchableError as e:
    result = GateResult(
      ok: false, name: GateName,
      stdout: "FAIL delegation-enforcer: in-process execution failed — " & e.msg,
      failureCategory: fcValidation,
      failureReason: "in-process execution error: " & e.msg,
      skipCiRequested: false)

when isMainModule:
  ## Real standalone entry (DEBT#497 follow-up): every AOT link of this module
  ## now carries the actual judgment — the hollow empty-shell binary is no
  ## longer producible from this source.
  main()

{.pop.}
