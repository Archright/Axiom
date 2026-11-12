## analyzer.nim — Error classification, telemetry for orchestrator hook.
## (domain: analyzer)

import core/trusted/layer_declaration
axiomLayer "gate"
import core/axiom_pragmas
import gate/orchestrator_types
import gate/gate_contract  # for GateConfig, GateSeverity
import core/trusted/stdlib_shield  # for safeRemoveFile
import std/osproc  # for Process
import std/strutils  # for alignLeft, contains
import core/parsers/safe_parsers
import core/results
import infrastructure/logging_facade  # for logInfo, logError
import std/os
import std/times
import std/algorithm  # for sorted

when defined(posix):
  import std/posix  # for waitpid, WNOHANG

# ---------------------------------------------------------------------------
# Wait status classification
# ---------------------------------------------------------------------------
when defined(posix):
  func classifyWaitStatus*(status: cint): tuple[kind: WaitStatusKind, code: int] {.raises: [].} =
    let lowBits = status and 0x7F
    if lowBits == 0:
      let exitCode = (status shr 8) and 0xFF
      return (wskExited, exitCode.int)
    elif lowBits != 0x7F:
      return (wskSignalKilled, lowBits.int)
    else:
      return (wskRunning, -1)

  proc peekWaitStatus*(p: Process): tuple[kind: WaitStatusKind, code: int] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    let pid = p.processID()
    if pid <= 0:
      return (wskExited, 0)
    var status: cint = 0
    let ret = waitpid(Pid(pid), status, WNOHANG)
    if ret == 0:
      return (wskRunning, -1)
    elif ret == -1:
      return (wskExited, -1)
    else:
      return classifyWaitStatus(status)

# ---------------------------------------------------------------------------
# Symlink integrity
# ---------------------------------------------------------------------------
proc validateRunnerSymlinks*() {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for entry in walkDir("src/gate/runners/"):
    if entry.kind == pcLinkToFile or entry.kind == pcLinkToDir:
      if not symlinkExists(entry.path) or not fileExists(entry.path):
        logInfo("orchestrator_analyzer", "axiom: removing dangling symlink: " & entry.path)
        safeRemoveFile(entry.path)

# ---------------------------------------------------------------------------
# Signal name helper
# ---------------------------------------------------------------------------
func signalName*(sig: int): string {.raises: [].} =
  case sig
  of 1: "SIGHUP"
  of 2: "SIGINT"
  of 3: "SIGQUIT"
  of 4: "SIGILL"
  of 5: "SIGTRAP"
  of 6: "SIGABRT"
  of 7: "SIGBUS"
  of 8: "SIGFPE"
  of 9: "SIGKILL"
  of 10: "SIGUSR1"
  of 11: "SIGSEGV"
  of 12: "SIGUSR2"
  of 13: "SIGPIPE"
  of 14: "SIGALRM"
  of 15: "SIGTERM"
  else: "SIG(" & $sig & ")"

# ---------------------------------------------------------------------------
# Grace Period Resolution — Advisory→Strict migration with shock absorber
# ---------------------------------------------------------------------------
import std/parseutils

func parseISODate(dateStr: string): (int, int, int) =
  if dateStr.len < 10: return (0, 0, 0)
  let yearRes = safeParseInt(dateStr[0..3])
  let monthRes = safeParseInt(dateStr[5..6])
  let dayRes = safeParseInt(dateStr[8..9])
  if yearRes.isErr or monthRes.isErr or dayRes.isErr:
    return (0, 0, 0)
  (yearRes.get, monthRes.get, dayRes.get)

proc resolveEffectiveSeverity*(gate: GateConfig): GateSeverity {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if gate.severity == gsWarn:
    return gsWarn
  if gate.gracePeriodUntil.len == 0:
    return gate.severity
  let (gy, gm, gd) = parseISODate(gate.gracePeriodUntil)
  if gy == 0:
    return gate.severity
  let now = getTime()
  let nowParts = now.utc()
  let currentYear = nowParts.year
  let currentMonth = ord(nowParts.month)
  let currentDay = nowParts.monthday.int
  if (currentYear, currentMonth, currentDay) < (gy, gm, gd):
    return gsWarn
  gate.severity

# ---------------------------------------------------------------------------
# Diagnostic reporting
# ---------------------------------------------------------------------------
type GateReport* = object
  id*: string
  ok*: bool
  exitCode*: int
  category*: string   # "PASS", "FAIL", "PASS_CACHED", "FAIL_CACHED", "SKIPPED"
  reason*: string
  elapsedMs*: int
  failureCategory*: FailureCategory

type OrchestratorLog* = object
  entries*: seq[string]
  warnCount*: int
  errorCount*: int

proc initOrchestratorLog*(): OrchestratorLog {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  OrchestratorLog(entries: @[], warnCount: 0, errorCount: 0)

proc log*(self: var OrchestratorLog; msg: string) {.raises: [].} =
  self.entries.add(msg)
  if "WARN" in msg: inc self.warnCount
  if "ERROR" in msg or "FAIL" in msg: inc self.errorCount

proc flushSummary*(self: var OrchestratorLog) {.raises: [system.IOError], axiomEffect: IOEffect.} =
  for line in self.entries:
    let isEssential = "FAIL" in line or "ERROR" in line or "WARN" in line or
                      "[GATE-DAG]" in line or "[GATE]" in line or
                      "RESULT:" in line or "═══" in line or
                      "DEFERRED" in line or "SKIP" in line or
                      "aborted" in line or "Aborting" in line
    if isEssential:
      logInfo("", line)
  stderr.flushFile()

proc printDiagnosticMatrix*(reports: seq[GateReport]) {.axiomEffect: IOEffect.} =
  let sorted = reports.sorted(proc(a, b: GateReport): int = cmp(a.id, b.id))
  let sep = "═══════════════════════════════════════════════════════"
  logInfo("", sep)
  logInfo("", "[AXIOM GATE EXECUTION REPORT]")
  logInfo("", sep)
  var passCount, failCount, skipCount = 0
  for r in sorted:
    let icon = if r.ok: "✅" elif r.category == "SKIPPED": "➖" else: "[FAIL]"
    let cat = if r.category.len > 0: r.category
              elif r.ok: "PASS"
              else: "FAIL"
    let timeStr = if r.elapsedMs > 0: "  (" & $r.elapsedMs & "ms)" else: ""
    let reasonStr = if r.reason.len > 0: "  " & r.reason else: ""
    logInfo("", icon & " " & r.id.alignLeft(36) & cat.alignLeft(12) & timeStr & reasonStr)
    if r.ok: inc passCount
    elif r.category == "SKIPPED": inc skipCount
    else: inc failCount
  logInfo("", sep)
  logError("", "RESULT: " & $failCount & " FAILED, " & $passCount & " PASSED, " & $skipCount & " SKIPPED")
  logInfo("", sep)
  stderr.flushFile()
