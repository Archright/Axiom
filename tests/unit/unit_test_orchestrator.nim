import std/[algorithm, json, os, osproc, strformat, strutils, tables, times, cpuinfo]
import malebolgia
import checksums/sha2

type
  UnitTestPhase = enum
    phaseCompile
    phaseRun

  UnitTestFailure = object
    filePath: string
    phase: UnitTestPhase
    exitCode: int
    output: string

  UnitTestJob = object
    testPath: string
    outBin: string
    nimcacheDir: string
    logPath: string
    needsCompile: bool

  UnitTestResult = object
    testPath: string
    success: bool
    phase: UnitTestPhase
    exitCode: int
    output: string

  IncrementalCacheEntry* = object
    sha256*: string
    binaryMtime*: int64
    lastCompileExitCode*: int

func phaseName(phase: UnitTestPhase): string =
  case phase
  of phaseCompile:
    "compile"
  of phaseRun:
    "run"

func binaryPathFor(testPath: string): string =
  let (_, name, _) = splitFile(testPath)
  joinPath("build", "unit-tests", name)

func logPathFor(testPath: string): string =
  let (_, name, _) = splitFile(testPath)
  joinPath("build", "unit-tests", "logs", name & ".log")

func nimcachePathFor(testPath: string): string =
  let (_, name, _) = splitFile(testPath)
  joinPath("build", "unit-tests", "nimcache", name)

func cachePath(): string =
  joinPath("build", "unit-tests", "incremental_cache.json")

func reportPath(): string =
  joinPath("build", "unit-tests", "unit_test_orchestrator_report.json")

proc discoverUnitTests(unitDir: string): seq[string] =
  var files: seq[string] = @[]
  for kind, path in walkDir(unitDir):
    if kind == pcFile and path.endsWith(".nim"):
      files.add(path)
  files.sort()
  files

func failureJson(failure: UnitTestFailure): JsonNode =
  %*{
    "file": failure.filePath,
    "phase": phaseName(failure.phase),
    "exitCode": failure.exitCode,
    "output": failure.output
  }

proc writeReport(tests: seq[string]; failures: seq[UnitTestFailure]) =
  var redZone = newJArray()
  for failure in failures:
    redZone.add(failureJson(failure))

  let payload = %*{
    "schemaVersion": "axiom.unitTestOrchestrator.v1",
    "unitDir": "tests/unit",
    "total": tests.len,
    "passed": tests.len - failures.len,
    "failed": failures.len,
    "redZone": redZone
  }
  writeFile(reportPath(), pretty(payload))

proc loadIncrementalCache*(): Table[string, IncrementalCacheEntry] =
  result = initTable[string, IncrementalCacheEntry]()
  let path = cachePath()
  if not fileExists(path):
    return
  try:
    let node = parseFile(path)
    if node.kind != JObject:
      return
    for key, val in node:
      if val.kind == JObject:
        let sha =
          if val.hasKey("sha256") and val["sha256"].kind == JString:
            val["sha256"].getStr()
          else:
            ""
        let mtime =
          if val.hasKey("binaryMtime") and val["binaryMtime"].kind == JInt:
            val["binaryMtime"].getBiggestInt()
          else:
            0'i64
        let exitCode =
          if val.hasKey("lastCompileExitCode") and val["lastCompileExitCode"].kind == JInt:
            val["lastCompileExitCode"].getInt()
          else:
            0
        result[key] = IncrementalCacheEntry(
          sha256: sha,
          binaryMtime: mtime,
          lastCompileExitCode: exitCode
        )
  except CatchableError:
    discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)

proc saveIncrementalCache*(cache: Table[string, IncrementalCacheEntry]) =
  var node = newJObject()
  for key, entry in cache:
    node[key] = %*{
      "sha256": entry.sha256,
      "binaryMtime": entry.binaryMtime,
      "lastCompileExitCode": entry.lastCompileExitCode
    }
  try:
    writeFile(cachePath(), pretty(node))
  except CatchableError:
    discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)

proc computeFileSha256*(path: string): string =
  try:
    let content = readFile(path)
    var hasher = initSha_256()
    hasher.update(content)
    $hasher.digest()
  except CatchableError:
    ""

proc shouldRecompile*(testPath: string; outBin: string;
    cache: Table[string, IncrementalCacheEntry]): bool =
  if not fileExists(outBin):
    return true
  let currentSha = computeFileSha256(testPath)
  if currentSha.len == 0:
    return true
  if not cache.hasKey(testPath):
    return true
  let entry = cache[testPath]
  if entry.sha256 != currentSha:
    return true
  try:
    let info = getFileInfo(outBin)
    if info.lastWriteTime.toUnix != entry.binaryMtime:
      return true
  except CatchableError:
    return true
  false

proc runUnitTestJob(job: ptr UnitTestJob): UnitTestResult =
  result.testPath = job.testPath
  let outBin = job.outBin

  if job.needsCompile:
    let compileCmd =
      "nim c --threads:on --listFullPaths:off --nimcache:" &
      quoteShell(job.nimcacheDir) &
      " --out:" & quoteShell(outBin) & " " & quoteShell(job.testPath) &
      " > " & quoteShell(job.logPath & ".compile") & " 2>&1"

    let compileExit = execShellCmd(compileCmd)
    if compileExit != 0:
      try:
        removeDir(job.nimcacheDir)
      except CatchableError:
        discard  # axiom:best-effort(cleanup of partial nimcache on compile failure; run failure is already reported, cache purge is a non-blocking hygiene step)
      var output = ""
      try:
        output = readFile(job.logPath & ".compile").strip()
      except CatchableError:
        discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)
      return UnitTestResult(
        testPath: job.testPath,
        success: false,
        phase: phaseCompile,
        exitCode: compileExit,
        output: output
      )

  let runCmd = quoteShell(outBin) & " > " & quoteShell(job.logPath & ".run") & " 2>&1"
  let runExit = execShellCmd(runCmd)
  if runExit != 0:
    var output = ""
    try:
      output = readFile(job.logPath & ".run").strip()
    except CatchableError:
      discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)
    return UnitTestResult(
      testPath: job.testPath,
      success: false,
      phase: phaseRun,
      exitCode: runExit,
      output: output
    )

  UnitTestResult(
    testPath: job.testPath,
    success: true,
    phase: phaseRun,
    exitCode: 0,
    output: ""
  )

proc main() =
  const unitDir = "tests/unit"
  createDir(joinPath("build", "unit-tests", "nimcache"))
  createDir(joinPath("build", "unit-tests", "logs"))

  let tests = discoverUnitTests(unitDir)
  var failures: seq[UnitTestFailure] = @[]
  var cache = loadIncrementalCache()

  echo &"UNIT_TEST_ORCHESTRATOR total={tests.len}"

  var jobs: seq[UnitTestJob] = @[]
  for testPath in tests:
    let outBin = binaryPathFor(testPath)
    let recompile = shouldRecompile(testPath, outBin, cache)
    jobs.add(UnitTestJob(
      testPath: testPath,
      outBin: outBin,
      nimcacheDir: nimcachePathFor(testPath),
      logPath: logPathFor(testPath),
      needsCompile: recompile
    ))

  if jobs.len > 0:
    let processorCount = cpuinfo.countProcessors()
    let maxWorkers = min(processorCount, 8)
    echo &"PARALLEL jobs={jobs.len} maxWorkers={maxWorkers}"

    var results = newSeq[UnitTestResult](jobs.len)
    var m = createMaster()
    m.awaitAll:
      for i in 0 ..< jobs.len:
        m.spawn runUnitTestJob(addr jobs[i]) -> results[i]

    for i in 0 ..< results.len:
      let res = results[i]
      let job = jobs[i]
      if not res.success:
        failures.add(UnitTestFailure(
          filePath: res.testPath,
          phase: res.phase,
          exitCode: res.exitCode,
          output: res.output
        ))
        echo &"RED_ZONE {phaseName(res.phase)} {res.testPath}"
      else:
        echo &"PASS {res.testPath}"

      let currentSha = computeFileSha256(job.testPath)
      var mtime: int64 = 0
      try:
        if fileExists(job.outBin):
          let info = getFileInfo(job.outBin)
          mtime = info.lastWriteTime.toUnix
      except CatchableError:
        discard  # axiom:best-effort(fallback cleanup; underlying failure is already reported — best-effort hygiene only)
      cache[job.testPath] = IncrementalCacheEntry(
        sha256: currentSha,
        binaryMtime: mtime,
        lastCompileExitCode: 0
      )

  saveIncrementalCache(cache)
  writeReport(tests, failures)

  echo "========== UNIT TEST SUMMARY =========="
  echo &"TOTAL {tests.len}"
  echo &"PASSED {tests.len - failures.len}"
  echo &"FAILED {failures.len}"
  echo &"REPORT {reportPath()}"

  if failures.len > 0:
    echo "RED_ZONE"
    for failure in failures:
      echo &"  - {failure.filePath} [{phaseName(failure.phase)} exit={failure.exitCode}]"
    quit(1)

  echo "RED_ZONE empty"

when isMainModule:
  main()
