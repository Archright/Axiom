## bypass_audit.nim — Emergency bypass audit logging and reliability scoring
##
## Every AXIOM_EMERGENCY_NO_VERIFY usage is logged to data/bypass_audit.jsonl.
## Reliability score starts at 100, decreases by 5 per bypass.
## When score < 80, even emergency bypass is BLOCKED.
##
## Module is an I/O boundary — all procs perform disk reads/writes.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import core/interfaces/git_operations
import core/interfaces/logging_hub
import std/[json, os, times, strutils]
import core/axiom_pragmas
import core/macros/best_effort

axiomIoBoundary()

type
  BypassEvent* = object
    timestamp*: string      ## ISO 8601
    gate*: string           ## which gate was bypassed
    reason*: string         ## why
    commitHash*: string     ## git HEAD (if available)
    callerPid*: int         ## OS PID

  ReliabilityReport* = object
    score*: int             ## max(0, 100 - bypassCount * 5)
    totalBypasses*: int
    recentBypasses*: seq[BypassEvent]  ## last N bypass events

const
  HardGateThreshold* = 80   ## Below this, emergency bypass is BLOCKED
  ScorePerBypass* = 5       ## Points lost per bypass event
  MaxScore* = 100
  AuditLogPath* = "data/bypass_audit.jsonl"

proc getCommitHash*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""git not available — safe fallback to "unknown", audit record still written""").} =
  ## Get short git HEAD hash, or "unknown" if not in git repo
  try:
    let (outp, code) = git_operations.runGit("rev-parse --short HEAD 2>/dev/null")
    if code == 0 and outp.len > 0:
      return outp.strip()
  except CatchableError as e:
    logError("bypass_audit: git rev-parse failed: " & e.msg)
  return "unknown"

proc logBypass*(gate, reason: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append bypass event to data/bypass_audit.jsonl
  let commitHash = getCommitHash()
  let event = %*{
    "timestamp": now().format("yyyy-MM-dd'T'HH:mm:ss'.'fff"),
    "gate": gate,
    "reason": reason,
    "commitHash": commitHash,
    "callerPid": getCurrentProcessId()
  }

  # Ensure parent directory exists
  let dir = AuditLogPath.parentDir()
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)

  let f = open(AuditLogPath, fmAppend)
  try:
    f.writeLine($event)
  except CatchableError as e:
    logError("bypass_audit: failed to write audit record: " & e.msg)
  finally:
    f.close()

proc computeReliabilityScore*(): ReliabilityReport {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read audit log, compute reliability score.
  ## Score = max(0, 100 - totalBypasses * 5)
  result.score = MaxScore
  result.totalBypasses = 0
  result.recentBypasses = @[]

  if not fileExists(AuditLogPath):
    return

  let content = readFile(AuditLogPath)
  for line in content.splitLines():
    if line.strip().len == 0:
      continue
    try:
      let j = parseJson(line)
      inc result.totalBypasses
      let evt = BypassEvent(
        timestamp: j{"timestamp"}.getStr(""),
        gate: j{"gate"}.getStr(""),
        reason: j{"reason"}.getStr(""),
        commitHash: j{"commitHash"}.getStr(""),
        callerPid: j{"callerPid"}.getInt(0)
      )
      result.recentBypasses.add(evt)
    except CatchableError:
      discard  # Skip malformed entries — audit record still valid  # axiom:best-effort(ioboundary catch)

  result.score = max(0, MaxScore - result.totalBypasses * ScorePerBypass)
