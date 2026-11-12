## Coverage Regression Guard — Issue 2 (Part 2)
##
## Blocks PRs when coverage regresses compared to main branch.
##
## Logic:
##   PR Coverage < Main Coverage → BLOCK (exit 1)
##   PR Coverage >= Main Coverage → PASS (exit 0)
##
## Usage:
##   coverage_guard [--tolerance <pct>] [--no-fetch] [--help]
##
## Options:
##   --tolerance <pct>  Allowable regression in percentage points (default: 0.0)
##   --no-fetch         Skip fetching baseline from main, use cached only
##   --help, -h         Show this help
##
## Exit codes:
##   0  PASS — PR coverage meets or exceeds main (within tolerance)
##   1  FAIL — PR coverage regressed below main (beyond tolerance)
##   2  ERROR — invalid arguments or missing files

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, strutils, json, math, times]

const
  GateTag = "[coverage-guard]"
  DefaultTolerance = 0.0
  BranchCoveragePath = "build/branch_coverage.json"
  ModuleCoveragePath = "data/coverage_report.json"
  CachedBaselinePath = "data/.coverage_baseline_main.json"

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
  return getCurrentDir()

proc extractBranchCoveragePct(jsonPath: string): float =
  ## Extract coveragePercent from build/branch_coverage.json metrics.
  try:
    let data = parseJson(readFile(jsonPath))
    if data.hasKey("metrics") and data["metrics"].hasKey("coveragePercent"):
      return data["metrics"]["coveragePercent"].getFloat(0.0)
    else:
      return -1.0
  except CatchableError:
    return -1.0

proc extractModuleCoveragePct(jsonPath: string): float =
  ## Extract coverage_pct from data/coverage_report.json.
  try:
    let data = parseJson(readFile(jsonPath))
    if data.hasKey("coverage_pct"):
      return data["coverage_pct"].getFloat(0.0)
    else:
      return -1.0
  except CatchableError:
    return -1.0

proc fetchFromGit(mainRef: string; branchPath: string; modulePath: string): tuple[success: bool, pct: float] =
  ## Try to fetch coverage from main branch via git show.
  ## Tries branch_coverage.json first, then falls back to coverage_report.json.
  var resultPct = -1.0

  # Try branch coverage path first
  let branchCmd = "git show " & mainRef & ":" & branchPath
  let (branchOutput, branchExit) = execCmdEx(branchCmd)
  if branchExit == 0 and branchOutput.len > 0:
    # Write to temp file to parse
    let tmpPath = getTempDir() / "axiom_pr_baseline_branch.json"
    writeFile(tmpPath, branchOutput)
    resultPct = extractBranchCoveragePct(tmpPath)
    try: removeFile(tmpPath)
    except: discard
    if resultPct >= 0.0:
      return (true, resultPct)

  # Fallback to module coverage path
  let moduleCmd = "git show " & mainRef & ":" & modulePath
  let (moduleOutput, moduleExit) = execCmdEx(moduleCmd)
  if moduleExit == 0 and moduleOutput.len > 0:
    let tmpPath = getTempDir() / "axiom_pr_baseline_module.json"
    writeFile(tmpPath, moduleOutput)
    resultPct = extractModuleCoveragePct(tmpPath)
    try: removeFile(tmpPath)
    except: discard
    if resultPct >= 0.0:
      return (true, resultPct)

  return (false, -1.0)

proc readCachedBaseline(): tuple[success: bool, pct: float] =
  ## Read cached baseline from data/.coverage_baseline_main.json.
  if not fileExists(CachedBaselinePath):
    return (false, -1.0)
  try:
    let data = parseJson(readFile(CachedBaselinePath))
    if data.hasKey("coverage_pct"):
      return (true, data["coverage_pct"].getFloat(-1.0))
  except CatchableError:
    discard  # axiom:best-effort(unreadable-baseline: treat as no prior baseline, compute fresh)
  return (false, -1.0)

proc cacheBaseline(pct: float) =
  ## Cache the current coverage as baseline for main branch.
  let report = %*{
    "coverage_pct": pct,
    "cached_at": now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "source": "coverage_guard"
  }
  let dir = parentDir(CachedBaselinePath)
  if not dirExists(dir):
    createDir(dir)
  writeFile(CachedBaselinePath, pretty(report, indent = 2))

proc resolveMainRef(): string =
  ## Determine the main branch reference name.
  ## Checks common names: origin/main, origin/master, main, master.
  const candidates = ["origin/main", "origin/master", "main", "master"]
  for candidate in candidates:
    let (_, exitCode) = execCmdEx("git rev-parse --verify " & candidate & " 2>/dev/null")
    if exitCode == 0:
      return candidate
  return ""

# ─── Core Guard Logic ────────────────────────────────────────────────────────

proc runCoverageGuard(tol: float; noFetch: bool): int =
  echo ""
  echo "=============================================================="
  echo "  Coverage Regression Guard"
  echo "  Policy: Block PRs that reduce test coverage below main"
  echo "=============================================================="
  echo ""

  # Step 1: Read PR coverage
  echo $GateTag & " Reading PR coverage..."

  var prCoverage = -1.0
  var coverageSource = ""

  # Try branch coverage first (AST-level)
  if fileExists(BranchCoveragePath):
    prCoverage = extractBranchCoveragePct(BranchCoveragePath)
    if prCoverage >= 0.0:
      coverageSource = BranchCoveragePath
      echo $GateTag & " Found branch coverage at " & BranchCoveragePath

  # Fallback to module coverage
  if prCoverage < 0.0 and fileExists(ModuleCoveragePath):
    prCoverage = extractModuleCoveragePct(ModuleCoveragePath)
    if prCoverage >= 0.0:
      coverageSource = ModuleCoveragePath
      echo $GateTag & " Using module coverage from " & ModuleCoveragePath

  if prCoverage < 0.0:
    echo $GateTag & " ERROR: No coverage data found."
    echo $GateTag & " Expected either " & BranchCoveragePath & " or " & ModuleCoveragePath
    echo $GateTag & " Run measure_coverage before checking."
    return 2

  echo $GateTag & " PR coverage: " & $prCoverage & "% (" & coverageSource & ")"
  echo ""

  # Step 2: Get baseline
  echo $GateTag & " Resolving main branch reference..."

  let mainRef = resolveMainRef()
  if mainRef.len == 0:
    echo $GateTag & " WARNING: Could not detect main branch reference."
    echo $GateTag & " Falling back to cached baseline."

  var baselinePct: float = -1.0
  var baselineSource = ""

  if mainRef.len > 0 and not noFetch:
    echo $GateTag & " Fetching baseline from " & mainRef & "..."
    let (fetched, pct) = fetchFromGit(mainRef, BranchCoveragePath, ModuleCoveragePath)
    if fetched:
      baselinePct = pct
      baselineSource = mainRef & " (fetched)"
      echo $GateTag & " Baseline fetched from " & mainRef & ": " & $baselinePct & "%"

  # Fallback to cached baseline
  if baselinePct < 0.0:
    echo $GateTag & " No fetched baseline, trying cached..."
    let (cached, pct) = readCachedBaseline()
    if cached:
      baselinePct = pct
      baselineSource = "cached"
      echo $GateTag & " Baseline from cache: " & $baselinePct & "%"

  # If still no baseline, save PR coverage as initial baseline and pass
  if baselinePct < 0.0:
    echo ""
    echo $GateTag & " No baseline available (first run or new repo)."
    echo $GateTag & " Saving PR coverage as initial baseline."
    cacheBaseline(prCoverage)
    echo ""
    echo "OK: No baseline exists yet — saving " & $prCoverage & "% as initial baseline."
    echo "   Next PR will be compared against this value."
    return 0

  echo ""

  # Step 3: Compare with tolerance
  echo $GateTag & " Main coverage: " & $baselinePct & "%"
  echo $GateTag & " Tolerance:     " & $tol & "pp"
  echo ""

  if prCoverage >= baselinePct - tol:
    let delta = if prCoverage >= baselinePct:
      "+" & $round(prCoverage - baselinePct, 1) & "pp"
    else:
      "-" & $round(baselinePct - prCoverage, 1) & "pp"

    echo "PASS: PR coverage " & $prCoverage & "% >= main " & $baselinePct & "% (delta: " & delta & ")"
    echo ""
    echo "   Baseline source: " & baselineSource
    return 0
  else:
    let regression = baselinePct - prCoverage
    echo "FAIL: PR coverage " & $prCoverage & "% < main " & $baselinePct & "%"
    echo "   Regression: " & $regression & " percentage points (tolerance: " & $tol & "pp)"
    echo ""
    echo "   Baseline source: " & baselineSource
    echo ""
    echo "   This PR reduces test coverage below the main branch."
    echo "   To fix:"
    echo "   1. Add tests for the affected modules"
    echo "   2. Run: nim c -r tools/measure_coverage.nim"
    echo "   3. Check untested modules: data/coverage_report_untested.json"
    echo ""
    echo "   If this regression is intentional, increase tolerance:"
    echo "   coverage_guard --tolerance " & $int(regression + 0.1)
    return 1

# ─── Entry Point ─────────────────────────────────────────────────────────────

proc main() =
  let params = commandLineParams()
  var tolerance = DefaultTolerance
  var noFetch = false

  var i = 0
  while i < params.len:
    case params[i]
    of "--tolerance":
      if i + 1 < params.len:
        try:
          tolerance = parseFloat(params[i + 1])
        except ValueError:
          echo "ERROR: Invalid tolerance value: " & params[i + 1]
          quit(2)
        inc i
      else:
        echo "ERROR: --tolerance requires a value"
        quit(2)
    of "--no-fetch":
      noFetch = true
    of "--help", "-h":
      echo "Usage: coverage_guard [options]"
      echo "  --tolerance <pct>  Allowable regression in percentage points (default: 0.0)"
      echo "  --no-fetch         Skip fetching baseline from main, use cached only"
      echo "  --help, -h         Show this help"
      echo ""
      echo "Exit codes:"
      echo "  0  PASS — PR coverage meets or exceeds main (within tolerance)"
      echo "  1  FAIL — PR coverage regressed below main (beyond tolerance)"
      echo "  2  ERROR — invalid arguments or missing files"
      quit(0)
    else:
      echo "Unknown option: " & params[i]
      quit(2)
    inc i

  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  let exitCode = runCoverageGuard(tolerance, noFetch)
  quit(exitCode)

when isMainModule:
  main()

{.pop.}
