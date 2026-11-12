## debug_mode.nim — Debug Mode Toggle CLI
##
## Phase 0 safety infrastructure for the Axiom project.
## Enables/disables a debug mode that sets all gates to warning mode
## (exit 0 with detailed diagnostics on stderr) instead of hard-failing.
##
## Usage:
##   bin/debug-mode --on      Enable debug mode (write marker, log state change)
##   bin/debug-mode --off     Disable debug mode (remove marker, log state change)
##   bin/debug-mode --self-test  Verify on/off transitions and marker/log files
##
## Exit codes:
##   0  success
##   1  error or self-test failure

import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import std/os
import std/strutils
import std/times
import core/trusted/env_access
import core/trusted/stdlib_shield
import std/json
import core/utils/repo_root as rr
import gate/debug_mode_state
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc nowIso(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Current UTC time in ISO-8601 format.
  let t = now().utc()
  result = t.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc logStateChange(projectRoot, action: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append a JSONL entry to logs/debug_mode.jsonl.
  let logsDir = projectRoot / "logs"
  if not dirExists(logsDir):
    createDir(logsDir)

  let logPath = logsDir / "debug_mode.jsonl"
  let entry = %*{
    "ts": nowIso(),
    "action": action,
    "user": getAxiomEnv(evUser, "unknown"),
  }
  let fh = open(logPath, fmAppend)
  try:
    fh.writeLine($entry)
  finally:
    fh.close()

proc ensureMarkerDir(projectRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Ensure the .axiom directory exists for the marker file.
  let axiomDir = projectRoot / ".axiom"
  if not dirExists(axiomDir):
    createDir(axiomDir)

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

proc cmdOn(projectRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Enable debug mode: write marker file, log state change.
  ensureMarkerDir(projectRoot)
  let marker = debugMarkerPath(projectRoot)
  if fileExists(marker):
    logDebug("debug_mode", "[debug-mode] Already enabled (marker exists: " & marker & ")")
    logStateChange(projectRoot, "on:already-active")
    quit(0)

  writeFile(marker, "debug mode enabled\n")
  logStateChange(projectRoot, "on")
  logError("debug_mode", "[debug-mode] Enabled. All gates will emit warnings instead of failing.")
  logDebug("debug_mode", "[debug-mode] Marker: " & marker)

proc cmdOff(projectRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Disable debug mode: remove marker file, log state change.
  let marker = debugMarkerPath(projectRoot)
  if not fileExists(marker):
    logDebug("debug_mode", "[debug-mode] Already disabled (no marker found)")
    logStateChange(projectRoot, "off:already-inactive")
    quit(0)

  safeRemoveFile(marker)
  logStateChange(projectRoot, "off")
  logDebug("debug_mode", "[debug-mode] Disabled. Gates restored to normal behavior.")

proc cmdSelfTest(projectRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify on/off transitions and marker/log files.
  var failures = 0

  proc check(condition: bool; desc: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    if not condition:
      logError("debug_mode", "[self-test] FAIL: " & desc)
      inc failures
    else:
      logInfo("debug_mode", "[self-test] PASS: " & desc)

  logDebug("debug_mode", "[self-test] Running debug-mode self-test …")

  # Clean state first
  let marker = debugMarkerPath(projectRoot)
  if fileExists(marker):
    safeRemoveFile(marker)

  # Test 1: marker should not exist after cleanup
  check(not fileExists(marker),
        "marker absent after cleanup")

  # Test 2: turn on
  cmdOn(projectRoot)
  check(fileExists(marker),
        "marker exists after --on")

  # Test 3: marker content
  let content = readFile(marker)
  check(content.strip().len > 0,
        "marker file has content")

  # Test 4: log file was created
  let logPath = projectRoot / "logs" / "debug_mode.jsonl"
  check(fileExists(logPath),
        "log file created")
  if fileExists(logPath):
    let logContent = readFile(logPath)
    check(logContent.contains("\"action\":\"on\""),
          "log contains 'on' entry")

  # Test 5: turn off
  cmdOff(projectRoot)
  check(not fileExists(marker),
        "marker removed after --off")

  # Test 6: idempotent on (already on scenario)
  cmdOn(projectRoot)
  cmdOn(projectRoot)  # should not crash
  check(fileExists(marker),
        "idempotent --on does not break marker")
  cmdOff(projectRoot)

  # Test 7: idempotent off (already off scenario)
  cmdOff(projectRoot)  # should not crash

  # Summary
  logInfo("debug_mode", "[self-test] ────────────────────────────────────")
  if failures > 0:
    logError("debug_mode", "[self-test] " & $failures & " check(s) FAILED")
    quit(1)
  else:
    logInfo("debug_mode", "[self-test] All checks passed.")

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

when isMainModule:
  let projectRoot = rr.findRepoRoot()
  let args = commandLineParams()

  if args.len == 0:
    logDebug("debug_mode", "usage: debug-mode --on | --off | --self-test")
    quit(1)

  let flag = args[0]

  case flag
  of "--on":
    cmdOn(projectRoot)
  of "--off":
    cmdOff(projectRoot)
  of "--self-test":
    cmdSelfTest(projectRoot)
  else:
    logInfo("debug_mode", "Unknown flag: " & flag)
    logDebug("debug_mode", "usage: debug-mode --on | --off | --self-test")
    quit(1)

{.pop.}

