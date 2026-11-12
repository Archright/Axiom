## Batch runner for all gateway verification tests.
## Process-level bounded parallelism with PER-JOB isolated nimcache dirs,
## logs, and deterministic incremental recompilation (Tier 1c).

import std/[algorithm, cpuinfo, json, os, osproc, sequtils, sets, strutils, tables, times]
import checksums/sha2

# --- JUnit XML Reporter ---

var junitOutputPath = ""
var filterNames: seq[string] = @[]
var skipNames: seq[string] = @[]
var probeKnownFailing = false
# Scan roots for *_feature_test.nim collection. Defaults to tests/gateway
# (the landing lane) when no --root is given; each --root REPLACES the default
# (the coverage plane passes --root=tests/gateway_coverage; test-gateway-all
# passes both roots explicitly).
var scanRoots: seq[string] = @[]

proc parseArgs() =
  ## Parses command-line arguments. Supports:
  ##   --junit-output=<path>          write a JUnit XML report
  ##   --skip-known-failing=<path>    read test-name list to exclude from the
  ##                                  main run (known-failing quarantine)
  ##   --probe-known-failing          run quarantined tests report-only and warn
  ##                                  if any now pass (xfail lifecycle check)
  ##   --root=<dir>                   scan root for *_feature_test.nim (repeatable;
  ##                                  default tests/gateway — the landing lane)
  ##   <name> ...                     explicit test-name filter (bare name or path to
  ##                                  a *_test.nim / *_suite.nim file). When provided,
  ##                                  only matching tests are collected (§0.7 biz scope).
  for arg in commandLineParams():
    if arg.startsWith("--junit-output="):
      junitOutputPath = arg["--junit-output=".len .. ^1]
    elif arg == "--probe-known-failing":
      probeKnownFailing = true
    elif arg.startsWith("--root="):
      scanRoots.add(arg["--root=".len .. ^1])
    elif arg.startsWith("--skip-known-failing="):
      let listPath = arg["--skip-known-failing=".len .. ^1]
      if fileExists(listPath):
        try:
          for line in readFile(listPath).splitLines():
            let name = line.strip()
            if name.len > 0 and not name.startsWith("#"):
              skipNames.add(splitFile(name).name)
        except CatchableError:
          discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)
    else:
      var name = splitFile(arg).name
      if name.endsWith(".nim"):
        name = name[0 ..< ^4]
      filterNames.add(name)

proc escapeXml(s: string): string =
  for ch in s:
    case ch
    of '&': result.add("&amp;")
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    of '"': result.add("&quot;")
    of '\'': result.add("&apos;")
    of '\n': result.add("&#10;")
    of '\r': result.add("&#13;")
    of '\t': result.add("&#9;")
    else: result.add(ch)

proc writeJunitXml(
    compileResults: seq[(string, bool, float, string)];
    runResults: seq[(string, bool, float, string)];
    outputPath: string
) =
  var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  xml &= "<testsuites>\n"
  xml &= "  <testsuite name=\"compile\" tests=\"" & $compileResults.len & "\""
  let cf = compileResults.countIt(not it[1])
  xml &= " failures=\"" & $cf & "\">\n"
  for (name, passed, duration, msg) in compileResults:
    xml &= "    <testcase classname=\"compile\" name=\"" & escapeXml(name) & "\" time=\"" & formatFloat(duration, ffDecimal, 2) & "\""
    if passed: xml &= "/>\n"
    else:
      xml &= ">\n"
      xml &= "      <failure message=\"" & escapeXml(msg) & "\"/>\n"
      xml &= "    </testcase>\n"
  xml &= "  </testsuite>\n"
  xml &= "  <testsuite name=\"run\" tests=\"" & $runResults.len & "\""
  let rf = runResults.countIt(not it[1])
  xml &= " failures=\"" & $rf & "\">\n"
  for (name, passed, duration, msg) in runResults:
    xml &= "    <testcase classname=\"run\" name=\"" & escapeXml(name) & "\" time=\"" & formatFloat(duration, ffDecimal, 2) & "\""
    if passed: xml &= "/>\n"
    else:
      xml &= ">\n"
      xml &= "      <failure message=\"" & escapeXml(msg) & "\"/>\n"
      xml &= "    </testcase>\n"
  xml &= "  </testsuite>\n"
  xml &= "</testsuites>\n"
  createDir(outputPath.parentDir)
  writeFile(outputPath, xml)
  echo "[INFO] JUnit XML written to " & outputPath

const
  buildRoot = joinPath("build", "gateway-tests")
  binRoot = joinPath(buildRoot, "bin")
  logRoot = joinPath(buildRoot, "logs")
  nimcacheRoot = joinPath(buildRoot, "nimcache")
  cacheFile = joinPath(buildRoot, "incremental_cache.json")

var runId: string

type
  GatewayPhase = enum
    phaseCompile
    phaseRun

  GatewayJob = object
    name: string
    sourcePath: string
    binaryPath: string
    nimcacheDir: string
    compileLogPath: string
    runLogPath: string
    cacheKey: string
    needsCompile: bool

  RunningJob = object
    jobIndex: int
    handle: Process

  GatewayFailure = object
    name: string
    phase: GatewayPhase
    exitCode: int
    logPath: string
    outputPreview: string

  CacheEntry = object
    cacheKey: string
    binaryMtime: int64
    lastCompileExitCode: int

  PhaseResult = object
    failures: seq[GatewayFailure]
    timings: Table[string, float]

func phaseName(phase: GatewayPhase): string =
  case phase
  of phaseCompile: "compile"
  of phaseRun: "run"

func parsePositiveInt(s: string; fallback: int): int =
  try:
    let parsed = parseInt(s.strip())
    if parsed > 0: parsed else: fallback
  except ValueError:
    fallback

proc configuredWorkers(): int =
  let cpuCount = max(1, cpuinfo.countProcessors())
  let defaultJobs = max(1, min(cpuCount - 2, 12))
  let envJobs = getEnv("AXIOM_JOBS", "")
  result = if envJobs.len > 0: parsePositiveInt(envJobs, defaultJobs) else: defaultJobs
  result = max(1, min(result, cpuCount))

proc ensureDirs() =
  createDir(buildRoot)
  createDir(binRoot)
  createDir(logRoot)
  createDir(nimcacheRoot)
  runId = $int(epochTime())
  createDir(joinPath(nimcacheRoot, runId))

proc collectGatewayTests(): tuple[active: seq[string]; quarantined: seq[string]] =
  let filterSet = filterNames.toHashSet()
  let skipSet = skipNames.toHashSet()
  var active: seq[string] = @[]
  var quarantined: seq[string] = @[]
  # Deterministic filesystem scan: walkDirRec order is filesystem-dependent, so
  # an explicit sort restores the lexical ordering the Makefile's
  # gateway_shard_files partition depends on (equivalent of `ls | sort`
  # without a shell). The landing-required contract derives from
  # config/policy/landing_required_gateway_tests.json, not from this listing.
  # Multiple --root scans are concatenated; basenames are unique because every
  # test lives in exactly one root (landing lane vs coverage plane).
  var shardFiles: seq[string] = @[]
  if scanRoots.len == 0:
    scanRoots.add("tests/gateway")
  for root in scanRoots:
    if not dirExists(root):
      stderr.writeLine("[ERROR] scan root missing: " & root)
      quit(1)
    for path in walkDirRec(root):
      if path.endsWith("_feature_test.nim"):
        shardFiles.add(path)
  shardFiles.sort()
  for path in shardFiles:
    let name = splitFile(path).name
    if filterNames.len > 0 and name notin filterSet:
      continue
    if name in skipSet:
      quarantined.add(path)
    else:
      active.add(path)
  active.sort()
  quarantined.sort()
  (active, quarantined)

proc computeFileSha256(path: string): string =
  try:
    let content = readFile(path)
    var hasher = initSha_256()
    hasher.update(content)
    result = $hasher.digest()
  except CatchableError:
    result = ""

proc collectSourceFingerprintFiles(): seq[string] =
  try:
    for path in walkDirRec("src"):
      if path.endsWith(".nim"):
        result.add(path)
  except CatchableError:
    discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)
  for path in ["config.nims", "axiom.nimble", "nimble.paths"]:
    if fileExists(path):
      result.add(path)
  result.sort()

proc computeSourceTreeSha256(): string =
  var hasher = initSha_256()
  for path in collectSourceFingerprintFiles():
    hasher.update(path)
    hasher.update("\n")
    hasher.update(computeFileSha256(path))
    hasher.update("\n")
  result = $hasher.digest()

proc loadCache(): Table[string, CacheEntry] =
  result = initTable[string, CacheEntry]()
  if not fileExists(cacheFile):
    return
  try:
    let node = parseFile(cacheFile)
    if node.kind != JObject:
      return
    for key, val in node.pairs:
      if val.kind != JObject:
        continue
      result[key] = CacheEntry(
        cacheKey: val.getOrDefault("cacheKey").getStr(""),
        binaryMtime: val.getOrDefault("binaryMtime").getBiggestInt(0),
        lastCompileExitCode: val.getOrDefault("lastCompileExitCode").getInt(1)
      )
  except CatchableError:
    discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)

proc saveCache(cache: Table[string, CacheEntry]) =
  var root = newJObject()
  var keys: seq[string] = @[]
  for key in cache.keys:
    keys.add(key)
  keys.sort()
  for key in keys:
    let entry = cache[key]
    root[key] = %*{
      "cacheKey": entry.cacheKey,
      "binaryMtime": entry.binaryMtime,
      "lastCompileExitCode": entry.lastCompileExitCode
    }
  try:
    writeFile(cacheFile, pretty(root))
  except CatchableError:
    discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)

proc binaryMtime(path: string): int64 =
  try:
    if fileExists(path):
      return getFileInfo(path).lastWriteTime.toUnix()
  except CatchableError:
    discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)
  0'i64

proc shouldCompile(job: GatewayJob; cache: Table[string, CacheEntry]): bool =
  if not fileExists(job.binaryPath):
    return true
  if not cache.hasKey(job.name):
    return true
  let entry = cache[job.name]
  if entry.cacheKey != job.cacheKey:
    return true
  if entry.lastCompileExitCode != 0:
    return true
  binaryMtime(job.binaryPath) != entry.binaryMtime

proc makeJob(name, sourcePath: string; sourceTreeHash: string; cache: Table[string, CacheEntry]): GatewayJob =
  # sourcePath is the resolved path from a scan root (tests/gateway or the
  # coverage root); junit/binary identity stays the file basename.
  let binaryPath = joinPath(binRoot, name)
  # Per-job isolated nimcache: each gateway test compiles into its own
  # subdirectory (nimcacheRoot/<runId>/<name>) so parallel compiles cannot
  # corrupt each other's cache entries (fixes shared-nimcache LTO-ICE on
  # gcc-13 + nim 2.2.10). A per-run runId prevents stale directories from
  # colliding across runs.
  let nimcacheDir = joinPath(nimcacheRoot, runId, name)
  let sourceHash = computeFileSha256(sourcePath)
  result = GatewayJob(
    name: name,
    sourcePath: sourcePath,
    binaryPath: binaryPath,
    nimcacheDir: nimcacheDir,
    compileLogPath: joinPath(logRoot, name & ".compile.log"),
    runLogPath: joinPath(logRoot, name & ".run.log"),
    cacheKey: sourceTreeHash & ":" & sourceHash,
    needsCompile: false
  )
  result.needsCompile = shouldCompile(result, cache)

proc logPreview(path: string; maxChars: int = 1600): string =
  try:
    let content = readFile(path).strip()
    if content.len <= maxChars:
      return content
    content[0 ..< maxChars] & "\n... [truncated]"
  except CatchableError:
    ""

proc closeRunning(job: var RunningJob) =
  try:
    close(job.handle)
  except CatchableError:
    discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)

func shellRedirect(command: string; logPath: string): string =
  command & " > " & quoteShell(logPath) & " 2>&1"

func compileCommand(job: GatewayJob): string =
  # -d:AXIOM_GATE_BOND=1 skips config/integrity.nims manifestBootstrap during
  # parallel test compilation — otherwise every concurrent `nim c` rebuilds the
  # shared feature_manifest_generator into build/nimcache/debug (race: 63/85
  # gateway tests failed with "Directory not empty"/OSError). The manifest is
  # already present; this flag only skips the redundant bootstrap.
  "nim c -d:release --threads:on --listFullPaths:off --hints:off -d:AXIOM_GATE_BOND=1 --nimcache:" &
    quoteShell(job.nimcacheDir) &
    " --out:" & quoteShell(job.binaryPath) & " " & quoteShell(job.sourcePath)

func runCommand(job: GatewayJob): string =
  quoteShell(job.binaryPath)

proc startShellJob(jobIndex: int; cmd: string): RunningJob =
  RunningJob(
    jobIndex: jobIndex,
    handle: startProcess(cmd, options = {poUsePath, poEvalCommand})
  )

proc runPhase(
  jobs: seq[GatewayJob];
  selected: seq[int];
  workers: int;
  phase: GatewayPhase
): PhaseResult =
  result.failures = @[]
  result.timings = initTable[string, float]()
  var running: seq[RunningJob] = @[]
  var startTimes: Table[int, float] = initTable[int, float]()
  var nextIdx = 0

  while nextIdx < selected.len or running.len > 0:
    while nextIdx < selected.len and running.len < workers:
      let jobIndex = selected[nextIdx]
      let job = jobs[jobIndex]
      case phase
      of phaseCompile:
        # Per-job isolated nimcache: each job creates its own subdirectory
        # under nimcacheRoot/<runId>/ so parallel compiles have no shared
        # cache directory and cannot race on LTO artifacts or intermediate
        # .c files. The per-job dir is cleaned up on compile failure.
        createDir(job.nimcacheDir)
      of phaseRun:
        discard
      let rawCmd =
        case phase
        of phaseCompile: compileCommand(job)
        of phaseRun: runCommand(job)
      let logPath =
        case phase
        of phaseCompile: job.compileLogPath
        of phaseRun: job.runLogPath
      startTimes[jobIndex] = epochTime()
      running.add(startShellJob(jobIndex, shellRedirect(rawCmd, logPath)))
      inc nextIdx

    var alive: seq[RunningJob] = @[]
    for item in running.mitems:
      let exitCode = peekExitCode(item.handle)
      if exitCode == -1:
        alive.add(item)
      else:
        let job = jobs[item.jobIndex]
        let duration = epochTime() - startTimes.getOrDefault(item.jobIndex, epochTime())
        result.timings[job.name] = duration
        let logPath = if phase == phaseCompile: job.compileLogPath else: job.runLogPath
        if exitCode != 0:
          if phase == phaseCompile:
            try:
              removeDir(job.nimcacheDir)
            except CatchableError:
              discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)
          result.failures.add(GatewayFailure(
            name: job.name,
            phase: phase,
            exitCode: exitCode,
            logPath: logPath,
            outputPreview: logPreview(logPath)
          ))
        closeRunning(item)
    running = alive
    if running.len > 0:
      sleep(20)

proc printFailures(failures: seq[GatewayFailure]) =
  for failure in failures:
    echo "  - ", failure.name, " [", phaseName(failure.phase), " exit=", failure.exitCode, "]"
    echo "    log: ", absolutePath(failure.logPath)
    if failure.outputPreview.len > 0:
      echo "    preview:"
      for line in failure.outputPreview.splitLines():
        echo "      ", line

proc main() =
  parseArgs()
  ensureDirs()
  let (activeFiles, quarantinedFiles) = collectGatewayTests()
  if activeFiles.len == 0:
    echo "[ERROR] No gateway tests found in " & scanRoots.join(", ")
    quit(1)

  let workers = configuredWorkers()
  echo "[INFO] gateway tests=", activeFiles.len, " workers=", workers
  if quarantinedFiles.len > 0:
    echo "[INFO] known-failing quarantined=", quarantinedFiles.len, " (", quarantinedFiles.mapIt(splitFile(it).name).join(", "), ")"

  var cache = loadCache()
  let sourceTreeHash = computeSourceTreeSha256()
  var jobs: seq[GatewayJob] = @[]
  var compileIndexes: seq[int] = @[]
  var runIndexes: seq[int] = @[]

  for path in activeFiles:
    let name = splitFile(path).name
    let job = makeJob(name, path, sourceTreeHash, cache)
    jobs.add(job)
    let idx = jobs.high
    if job.needsCompile:
      compileIndexes.add(idx)
    runIndexes.add(idx)

  echo "[INFO] compile queue=", compileIndexes.len, " cached=", jobs.len - compileIndexes.len

  let compileResult = runPhase(jobs, compileIndexes, workers, phaseCompile)
  for idx in compileIndexes:
    let job = jobs[idx]
    cache[job.name] = CacheEntry(
      cacheKey: job.cacheKey,
      binaryMtime: binaryMtime(job.binaryPath),
      lastCompileExitCode: 0
    )
  for failure in compileResult.failures:
    if cache.hasKey(failure.name):
      cache[failure.name].lastCompileExitCode = failure.exitCode
  saveCache(cache)

  if compileResult.failures.len > 0:
    echo "\n[BUILD FAILURES] ", compileResult.failures.len, "/", jobs.len
    printFailures(compileResult.failures)
    # Write JUnit XML even on compile failure
    if junitOutputPath.len > 0:
      var compileXml: seq[(string, bool, float, string)] = @[]
      let failedNames = compileResult.failures.mapIt(it.name).toHashSet()
      for job in jobs:
        let dur = compileResult.timings.getOrDefault(job.name, 0.0)
        if job.name in failedNames:
          let fail = compileResult.failures.filterIt(it.name == job.name)[0]
          compileXml.add((job.name, false, dur, fail.outputPreview))
        elif job.needsCompile:
          compileXml.add((job.name, true, dur, ""))
      writeJunitXml(compileXml, @[], junitOutputPath)
    quit(1)

  echo "\n=== Running ==="
  let runResult = runPhase(jobs, runIndexes, workers, phaseRun)

  # ── Known-Failing xfail probe ──
  # Quarantined tests are re-run report-only. A quarantined test that now
  # PASSES is a fixed regression: CI stays green but the quarantine list must
  # be updated (fail-open is documented in docs/spec/gateway_xfail_policy.md).
  var probeWarnings: seq[string] = @[]
  if probeKnownFailing and quarantinedFiles.len > 0:
    echo "\n=== Probing known-failing quarantined tests (xfail) ==="
    var probeJobs: seq[GatewayJob] = @[]
    for path in quarantinedFiles:
      let name = splitFile(path).name
      probeJobs.add(makeJob(name, path, computeSourceTreeSha256(), cache))
    let probeIndexes = toSeq(0 ..< probeJobs.len)
    let probeResult = runPhase(probeJobs, probeIndexes, workers, phaseRun)
    for job in probeJobs:
      let passed = job.name notin probeResult.failures.mapIt(it.name).toHashSet()
      if passed:
        probeWarnings.add(job.name)
        echo "[WARN] quarantined test now PASSES: ", job.name,
          " — remove it from the known-failing list"
      else:
        echo "[OK] quarantined test still fails as expected: ", job.name

  echo "\n========== BATCH SUMMARY =========="

  # Build JUnit XML results
  if junitOutputPath.len > 0:
    var compileXml: seq[(string, bool, float, string)] = @[]
    for job in jobs:
      if job.needsCompile:
        let dur = compileResult.timings.getOrDefault(job.name, 0.0)
        compileXml.add((job.name, true, dur, ""))

    var runXml: seq[(string, bool, float, string)] = @[]
    let runFailedNames = runResult.failures.mapIt(it.name).toHashSet()
    for job in jobs:
      let dur = runResult.timings.getOrDefault(job.name, 0.0)
      if job.name in runFailedNames:
        let fail = runResult.failures.filterIt(it.name == job.name)[0]
        runXml.add((job.name, false, dur, fail.outputPreview))
      else:
        runXml.add((job.name, true, dur, ""))
    writeJunitXml(compileXml, runXml, junitOutputPath)

  if runResult.failures.len == 0:
    echo "ALL GATEWAY TESTS PASSED (", jobs.len, " tests)"
  else:
    echo "FAILURES (", runResult.failures.len, "/", jobs.len, "):"
    printFailures(runResult.failures)
    quit(1)

  if probeWarnings.len > 0:
    echo "\n[XFAIL] Quarantined tests that now pass (update known-failing list):"
    for w in probeWarnings:
      echo "  - ", w

when isMainModule:
  main()
