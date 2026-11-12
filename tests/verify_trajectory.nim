## Axiom Telemetry Verification Script (Pure Nim)
## Verifies that the Deterministic Lifecycle Supervisor Pattern
## correctly records all pipeline stages to the trajectory JSONL.
import std/[json, strutils, tables, os]
import infrastructure/logging_facade

proc verifyTelemetry() =
  let logPath = "logs/ax_prove_trajectory.jsonl"
  if not fileExists(logPath):
    echo "[ERROR] Trajectory log file missing!"
    quit(1)

  var phases = initCountTable[string]()
  var stageTraceFound = false
  var totalEvents = 0
  var discardedEvents = 0

  for line in lines(logPath):
    if line.strip().len == 0: continue
    inc totalEvents
    try:
      let e = parseJson(line)
      let phase = e{"phase"}.getStr()
      if phase.len > 0:
        phases.inc(phase)
      # defer 이벤트의 stageTrace 주입 여부 확인
      if e.hasKey("extra") and e["extra"].hasKey("stageTrace"):
        stageTraceFound = true
        echo "  stageTrace: ", e["extra"]["stageTrace"]
    except CatchableError as err:
      inc discardedEvents
      logWarn("verify_trajectory", "Discarded event #" & $totalEvents & ": JSON parse error — " & err.msg)

  echo "--- [Axiom Telemetry Verification] ---"
  echo "Total events: ", totalEvents
  echo "Discarded events: ", discardedEvents
  echo "Phases found: ", phases
  echo "stageTrace present: ", stageTraceFound
  echo ""

  # doAssert: Nim 표준 assertion (항상 활성화, -d:release에서도 동작)
  doAssert phases.hasKey("skSwat"), "FAIL: skSwat MUST appear — gap 1 not fixed"
  doAssert phases.hasKey("skReport"), "FAIL: skReport MUST appear"
  doAssert stageTraceFound, "FAIL: stageTrace MUST be present in defer event"
  doAssert totalEvents > 5, "FAIL: expected more than 5 trajectory events"

  # Double src/ prefix regression guard: empty sourceCode detection
  var emptySourceCount = 0
  for line in lines(logPath):
    if line.strip().len == 0: continue
    try:
      let e = parseJson(line)
      if e.hasKey("detail") and "cannot be empty" in e["detail"].getStr():
        inc emptySourceCount
    except CatchableError as err:
      inc discardedEvents
      logWarn("verify_trajectory", "Discarded event #" & $totalEvents & ": JSON parse error — " & err.msg)
  doAssert emptySourceCount == 0,
    "CRITICAL: Double src/ prefix regression — " & $emptySourceCount & " nodes had empty sourceCode"

  echo "PASS: Pure Nim Deterministic Lifecycle Confirmed."

verifyTelemetry()
