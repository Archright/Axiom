## Coverage Floor Gate — Phase 3 CI Coverage Enforcement
##
## Enforces a minimum coverage threshold (default 45%).
## Reads from data/coverage_report.json (produced by measure_coverage).
## Fails CI if coverage falls below the configured floor.
##
## Usage:
##   coverage_floor_gate [--threshold <pct>] [--measure]
##
## Options:
##   --threshold <pct>  Minimum coverage percentage (default: 45.0)
##   --measure          Run measure_coverage before checking (default: true)
##   --help, -h         Show this help
##
## Exit codes:
##   0  PASS — coverage meets or exceeds threshold
##   1  FAIL — coverage below threshold
##   2  ERROR — invalid arguments or missing files

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, strutils, json, math, times]

const
  GateTag = "[coverage-floor-gate]"
  DefaultThreshold = 45.0
  CoverageReportPath = "data/coverage_report.json"
  MeasureCoverageBin = "bin/measure_coverage"
  MeasureCoverageSrc = "tools/measure_coverage.nim"
  AuditLogRelPath = ".axiom/bypass_audit.jsonl"

# ─── Helpers ─────────────────────────────────────────────────────────────────

proc findRepoRoot(): string =
  ## Walk up from CWD to find .axiom_root marker.
  var dir = getCurrentDir()
  for i in 0 ..< 20:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  # Fallback: assume CWD is repo root
  return getCurrentDir()

proc getUtcNowIso(): string =
  let now = now().utc()
  result = now.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc measureCoverage(repoRoot: string): float =
  ## Run measure_coverage if available, then read the report.
  let binPath = repoRoot / MeasureCoverageBin
  let reportPath = repoRoot / CoverageReportPath

  # Try to build and run measure_coverage if binary doesn't exist
  if not fileExists(binPath):
    let srcPath = repoRoot / MeasureCoverageSrc
    if fileExists(srcPath):
      echo $GateTag & " Building measure_coverage from source..."
      let buildCmd = "nim c -d:release -o:" & binPath & " " & srcPath
      let (output, exitCode) = execCmdEx(buildCmd, workingDir = repoRoot)
      if exitCode != 0:
        echo $GateTag & " WARNING: Failed to build measure_coverage: " & output
        return -1.0
    else:
      echo $GateTag & " ERROR: measure_coverage source not found at " & MeasureCoverageSrc
      return -1.0

  # Run measure_coverage
  echo $GateTag & " Running measure_coverage..."
  let (output, exitCode) = execCmdEx("./" & MeasureCoverageBin, workingDir = repoRoot)
  if exitCode != 0:
    echo $GateTag & " WARNING: measure_coverage exited with code " & $exitCode
    echo $GateTag & " Output: " & output

  # Read the report
  if not fileExists(reportPath):
    echo $GateTag & " ERROR: Coverage report not found at " & CoverageReportPath
    return -1.0

  try:
    let data = parseJson(readFile(reportPath))
    if data.hasKey("coverage_pct"):
      return data{"coverage_pct"}.getFloat(0.0)
    else:
      echo $GateTag & " ERROR: coverage_pct field missing from report"
      return -1.0
  except CatchableError as e:
    echo $GateTag & " ERROR: Failed to parse coverage report: " & e.msg
    return -1.0

proc readExistingCoverage(repoRoot: string): float =
  ## Read coverage from existing report without running measure_coverage.
  let reportPath = repoRoot / CoverageReportPath
  if not fileExists(reportPath):
    echo $GateTag & " ERROR: Coverage report not found at " & CoverageReportPath
    return -1.0

  try:
    let data = parseJson(readFile(reportPath))
    if data.hasKey("coverage_pct"):
      return data{"coverage_pct"}.getFloat(0.0)
    else:
      echo $GateTag & " ERROR: coverage_pct field missing from report"
      return -1.0
  except CatchableError as e:
    echo $GateTag & " ERROR: Failed to parse coverage report: " & e.msg
    return -1.0

# ─── Audit Logging ───────────────────────────────────────────────────────────

proc appendAuditLog(repoRoot: string; coverage, threshold: float;
                    passed: bool) =
  let auditPath = repoRoot / AuditLogRelPath
  let auditDir = auditPath.parentDir()
  if not dirExists(auditDir):
    createDir(auditDir)

  let entry = %*{
    "tool": "coverage-floor-gate",
    "action": "floor_check",
    "coverage_pct": coverage,
    "threshold_pct": threshold,
    "passed": passed,
    "timestamp": getUtcNowIso()
  }

  try:
    var f = open(auditPath, fmAppend)
    defer: f.close()
    f.write($entry & "\n")
  except CatchableError:
    discard  # axiom:best-effort(audit log write failure)

# ─── Core Gate Logic ─────────────────────────────────────────────────────────

proc runFloorGate(threshold: float; doMeasure: bool): int =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Coverage Floor Gate — Minimum Threshold Enforcement"
  echo "  Policy: AGENTS.md §0.8 — No Stub Files, Real Test Coverage"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # Measure or read coverage
  let coverage = if doMeasure:
    measureCoverage(repoRoot)
  else:
    readExistingCoverage(repoRoot)

  if coverage < 0.0:
    echo $GateTag & " ERROR: Could not determine coverage."
    echo $GateTag & " Ensure data/coverage_report.json exists or run with --measure."
    appendAuditLog(repoRoot, 0.0, threshold, false)
    return 1

  echo $GateTag & " Current coverage:  " & $coverage & "%"
  echo $GateTag & " Floor threshold:  " & $threshold & "%"
  echo ""

  if coverage >= threshold:
    echo "✅ PASS: Coverage " & $coverage & "% meets floor " & $threshold & "%"
    appendAuditLog(repoRoot, coverage, threshold, true)
    return 0
  else:
    let deficit = threshold - coverage
    echo "❌ FAIL: Coverage " & $coverage & "% is below floor " & $threshold & "%"
    echo "   Deficit: " & $deficit & " percentage points"
    echo ""
    echo "   To fix:"
    echo "   1. Add tests for untested modules (see data/coverage_report_untested.json)"
    echo "   2. Run: nim c -r tools/measure_coverage.nim"
    echo "   3. Verify: coverage_floor_gate --threshold " & $threshold
    echo ""
    echo "   To adjust threshold:"
    echo "   coverage_floor_gate --threshold <new_value>"
    appendAuditLog(repoRoot, coverage, threshold, false)
    return 1

# ─── Entry Point ─────────────────────────────────────────────────────────────

proc main() =
  let params = commandLineParams()
  var threshold = DefaultThreshold
  var doMeasure = true

  var i = 0
  while i < params.len:
    case params[i]
    of "--threshold":
      if i + 1 < params.len:
        try:
          threshold = parseFloat(params[i + 1])
        except ValueError:
          echo "ERROR: Invalid threshold value: " & params[i + 1]
          quit(2)
        inc i
      else:
        echo "ERROR: --threshold requires a value"
        quit(2)
    of "--no-measure":
      doMeasure = false
    of "--help", "-h":
      echo "Usage: coverage_floor_gate [options]"
      echo "  --threshold <pct>  Minimum coverage percentage (default: 45.0)"
      echo "  --no-measure       Skip running measure_coverage, use existing report"
      echo "  --help, -h         Show this help"
      quit(0)
    else:
      echo "Unknown option: " & params[i]
      quit(2)
    inc i

  let exitCode = runFloorGate(threshold, doMeasure)
  quit(exitCode)

when isMainModule:
  main()

{.pop.}
