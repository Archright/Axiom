import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import checksums/sha2
import core/trusted/axiom_pragmas_lite
import core/macros/best_effort
import core/parsers/safe_parsers
import core/results
import std/[json, os, osproc, options, strutils, times]
from core/gate/closure_manifest import genDependProfile, ManifestDirRel
from core/gate/gate_cas import computeCasKey, resolveCasBinaryPathWithHash, computeTransitiveSourceHash, writeCasBinarySidecar
from core/gate/gate_memo import computeBuildEnvHash
from core/gate/gate_resolver import resolveGateSourcePath
import core/utils/repo_root as rr
import infrastructure/provenance_probe
import generated/build_env
# axiomIoBoundary

const LockFileName = "gate_env.lock"
const LockCacheDir = ".axiom" / "cache"
const PrecompileNimcacheBase = "build" / "nimcache_precompile"
const CasDirName* = "gates"

proc logInfo(module: string, msg: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  stderr.writeLine "[INFO] " & module & ": " & msg

proc logError(module: string, msg: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  stderr.writeLine "[ERROR] " & module & ": " & msg

proc logWarn(module: string, msg: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  stderr.writeLine "[WARN] " & module & ": " & msg

proc findRepoRoot*(startDir: string = ""): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Root resolution delegates to the SSOT (core/utils/repo_root); this CLI
  ## surface additionally requires an anchor-verified hit and returns "" on
  ## miss so main() fails closed (len == 0 → quit(1)).
  let anchor = if startDir.len > 0: startDir else: getAppDir()
  let resolved = rr.findRepoRoot(anchor)
  if fileExists(resolved / rr.axiomRoot) or fileExists(resolved / rr.axiomToml):
    return resolved
  ""

type
  GateEnvLock = object
    nimVersion: string
    nimHash: string
    hostOS: string
    hostCPU: string
    kernelVersion: string
    stdlibHash: string
    configNimsHash: string
    nimbleHash: string
    gateSourceHashes: seq[(string, string)]
    createdAt: string
    gateCount: int

  PrecompileTarget = object
    gateId*: string
    entry*: string
    sourceFile*: string
    sourceHash*: string
    executionMode*: string

  CompileJob = object
    index: int
    gate: PrecompileTarget

  CompileResult = object
    index: int
    gateId: string
    cached: bool
    compiled: bool
    failed: bool
    casPath: string
    output: string

proc fileSha256(path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if path.len == 0 or not fileExists(path):
    return ""
  try:
    $secureHash(Sha_256, readFile(path))
  except CatchableError:
    ""

proc safeMoveFile(source, dest: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    moveFile(source, dest)
  except Exception:
    let e = getCurrentException()
    raise newException(CatchableError, "safeMoveFile(" & source & " → " & dest & "): " & e.msg)

proc safeFindNim(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    findExe("nim")
  except OSError:
    ""

proc safeUnameR(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let (outp, code) = execCmdEx("uname -r")
    if code == 0: outp.strip()
    else: "unknown"
  except CatchableError:
    "unknown"

proc nimVersionLine(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let nimExe = safeFindNim()
  if nimExe.len == 0:
    return "no-nim"
  try:
    let (outp, code) = execCmdEx(nimExe & " --version 2>&1 | head -1")
    if code == 0: outp.strip()
    else: "nim-version-error"
  except CatchableError:
    "nim-version-error"

proc resolveLockPath(repoRoot: string): string =
  repoRoot / LockCacheDir / LockFileName

proc buildCurrentFingerprint(repoRoot: string): GateEnvLock {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let nimExe = safeFindNim()
  let nimHash = if nimExe.len > 0: fileSha256(nimExe) else: ""
  let stdlibPath = if nimExe.len > 0: nimExe.parentDir() / "lib" / "system.nim"
                   else: ""

  result = GateEnvLock(
    nimVersion: nimVersionLine(),
    nimHash: nimHash,
    hostOS: hostOS,
    hostCPU: hostCPU,
    kernelVersion: safeUnameR(),
    stdlibHash: fileSha256(stdlibPath),
    configNimsHash: fileSha256(repoRoot / "config.nims"),
    nimbleHash: fileSha256(repoRoot / "axiom.nimble"),
    gateSourceHashes: @[],
    createdAt: "",
    gateCount: 0,
  )

proc lockToJson(lock: GateEnvLock): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var j = newJObject()
  j["nimVersion"] = %lock.nimVersion
  j["nimHash"] = %lock.nimHash
  j["hostOS"] = %lock.hostOS
  j["hostCPU"] = %lock.hostCPU
  j["kernelVersion"] = %lock.kernelVersion
  j["stdlibHash"] = %lock.stdlibHash
  j["configNimsHash"] = %lock.configNimsHash
  j["nimbleHash"] = %lock.nimbleHash
  var sourceHashes = newJObject()
  for (gateId, hash) in lock.gateSourceHashes:
    sourceHashes[gateId] = %hash
  j["gateSourceHashes"] = sourceHashes
  j["createdAt"] = %lock.createdAt
  j["gateCount"] = %lock.gateCount
  $j

proc parseLockFile(path: string): Option[GateEnvLock] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(path):
    return none(GateEnvLock)
  try:
    let content = readFile(path)
    let j = parseJson(content)
    var lock = GateEnvLock(
      nimVersion: j["nimVersion"].getStr(),
      nimHash: j["nimHash"].getStr(),
      hostOS: j["hostOS"].getStr(),
      hostCPU: j["hostCPU"].getStr(),
      kernelVersion: j["kernelVersion"].getStr(),
      stdlibHash: j["stdlibHash"].getStr(),
      configNimsHash: j["configNimsHash"].getStr(),
      nimbleHash: j["nimbleHash"].getStr(),
      createdAt: j["createdAt"].getStr(),
      gateCount: j["gateCount"].getInt(),
      gateSourceHashes: @[],
    )
    let sh = j["gateSourceHashes"]
    for key in sh.keys:
      lock.gateSourceHashes.add((key, sh[key].getStr()))
    some(lock)
  except CatchableError:
    none(GateEnvLock)

proc writeLockFileAtomic(lockPath: string; lock: GateEnvLock) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""temp file cleanup""").} =
  let tmpPath = lockPath & ".tmp"
  let content = lockToJson(lock)
  try:
    let dir = lockPath.parentDir()
    if not dirExists(dir):
      try:
        discard existsOrCreateDir(dir)
      except CatchableError as e:
        logWarn("precompile_gates", "Failed to create lock dir: " & e.msg)
    writeFile(tmpPath, content)
    safeMoveFile(tmpPath, lockPath)
  except CatchableError as e:
    logError("precompile_gates", "[precompile] WARNING: Failed to write lock file: " & e.msg)
    if fileExists(tmpPath):
      try: removeFile(tmpPath)
      except CatchableError as e:
        logWarn("precompile_gates", "Failed to clean up lock tmp: " & e.msg)

proc envFingerprintChanged(old, current: GateEnvLock): bool =
  old.nimVersion != current.nimVersion or
  old.nimHash != current.nimHash or
  old.stdlibHash != current.stdlibHash or
  old.configNimsHash != current.configNimsHash or
  old.nimbleHash != current.nimbleHash or
  old.hostOS != current.hostOS or
  old.hostCPU != current.hostCPU or
  old.kernelVersion != current.kernelVersion

proc findChangedGateIds(old, current: GateEnvLock): seq[string] =
  var oldHashMap: seq[(string, string)]
  for (id, hash) in old.gateSourceHashes:
    oldHashMap.add((id, hash))

  for (id, hash) in current.gateSourceHashes:
    var found = false
    for (oldId, oldHash) in oldHashMap:
      if oldId == id:
        if oldHash != hash:
          result.add(id)
        found = true
        break
    if not found:
      result.add(id)

proc configuredCompileWorkers(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let envWorkers = getEnv("AXIOM_PRECOMPILE_WORKERS").strip()
  let envCap = if envWorkers.len > 0:
                 let parsed = safeParseInt(envWorkers).getOrDefault(0)
                 if parsed > 0: min(parsed, 256) else: 8
               else: 8

  let cpuMax = try: readFile("/sys/fs/cgroup/cpu.max").strip() except CatchableError: ""
  var cgroupCap = if cpuMax.len > 0 and cpuMax != "max":
                    var quota = 0
                    var period = 0
                    var parts = cpuMax.splitWhitespace()
                    if parts.len >= 2:
                      let quotaRes = safeParseInt(parts[0])
                      let periodRes = safeParseInt(parts[1])
                      if quotaRes.isErr or periodRes.isErr:
                        logWarn("precompile_gates", "Cgroup CPU limit parsing failed — using default workers")
                      else:
                        quota = quotaRes.get
                        period = periodRes.get
                    if quota > 0 and period > 0: max(1, (quota + period - 1) div period)
                    else: 256
                  else: 256

  let cpuCount = osproc.countProcessors()
  result = max(1, min(min(envCap, cgroupCap), cpuCount))

type
  InFlightJob = object
    p: Process
    jobIdx: int
    startTime: float

proc buildCompileCommand(gateId, sourcePath, nimcacheDir, casTmp: string): string =
  let nimExe = findExe("nim")
  if nimExe.len == 0: return ""
  # 자식 출력은 게이트별 로그 파일로 리다이렉트 — 파이프 버퍼(64KB) 데드락 방지.
  # (poEvalCommand 사용 시 /bin/sh -c 로 실행되므로 shell 리다이렉트 사용 가능)
  let logPath = nimcacheDir / "compile.log"
  let nimCmd = "c --hints:off -d:release --skipUserCfg:on " &
    (if nimcacheDir.len > 0: "--nimcache:" & quoteShell(nimcacheDir) & " " else: "") &
    "-d:ThreadPoolSize=14 -o:" & quoteShell(casTmp) & " " & quoteShell(sourcePath) &
    " > " & quoteShell(logPath) & " 2>&1"
  nimExe & " " & nimCmd

proc runCompileJobsParallel(jobs: seq[CompileJob]; repoRoot, buildEnvHash: string): seq[CompileResult] {.
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""temp file cleanup""").} =
  result = newSeq[CompileResult](jobs.len)
  if jobs.len == 0:
    return

  let maxWorkers = configuredCompileWorkers()
  # 자식 nim c가 config.nims의 hermeticPreBuild를 재실행하지 않도록 가드 전파.
  # 미전파 시 20개 자식이 각각 bin/hermetic_build을 경쟁 실행 → 데드락/타임아웃.
  putEnv("AXIOM_HERMETIC_BUILDING", "1")
  putEnv("AXIOM_FAST_BUILD", "1")
  var inFlight: seq[InFlightJob]
  var nextJobIdx = 0
  var completed = 0

  while completed < jobs.len:
    while inFlight.len < maxWorkers and nextJobIdx < jobs.len:
      let job = jobs[nextJobIdx]
      let existing = resolveCasBinaryPathWithHash(
        job.gate.gateId, job.gate.sourceFile, repoRoot, job.gate.sourceHash, "", buildEnvHash)
      if existing.len > 0:
        result[job.index] = CompileResult(index: job.index, gateId: job.gate.gateId, cached: true, casPath: existing)
        inc completed
      else:
        let nimcacheDir = repoRoot / PrecompileNimcacheBase / job.gate.gateId
        let casKey = computeCasKey(job.gate.gateId, job.gate.sourceHash, repoRoot)
        let casTmp = repoRoot / ".axiom" / "cache" / CasDirName / casKey / "binary.tmp"

        try:
          if not dirExists(nimcacheDir):
            createDir(nimcacheDir)
        except CatchableError as e:
          logWarn("precompile_gates", "Failed to create nimcache dir for " & job.gate.gateId & ": " & e.msg)

        let cmd = buildCompileCommand(job.gate.gateId, job.gate.sourceFile, nimcacheDir, casTmp)
        if cmd.len == 0:
          result[job.index] = CompileResult(index: job.index, gateId: job.gate.gateId, failed: true)
          inc completed
        else:
          var p: Process
          var startFailed = false
          try:
            p = startProcess(command = cmd, options = {poStdErrToStdOut, poEvalCommand})
          except CatchableError as e:
            logError("precompile_gates", "Failed to start process for " & job.gate.gateId & ": " & e.msg)
            result[job.index] = CompileResult(index: job.index, gateId: job.gate.gateId, failed: true)
            inc completed
            startFailed = true
          if not startFailed:
            # 성공 경로에서만 inFlight 등록 (기존 버그: 예외 시 nil Process 등록)
            inFlight.add(InFlightJob(p: p, jobIdx: job.index, startTime: epochTime()))
      inc nextJobIdx

    for i in countdown(inFlight.len - 1, 0):
      if not running(inFlight[i].p):
        let exitCode = waitForExit(inFlight[i].p)
        let jobIdx = inFlight[i].jobIdx
        let gateId = jobs[jobIdx].gate.gateId
        let casKey = computeCasKey(gateId, jobs[jobIdx].gate.sourceHash, repoRoot)
        let casTmp = repoRoot / ".axiom" / "cache" / CasDirName / casKey / "binary.tmp"
        let casBinary = repoRoot / ".axiom" / "cache" / CasDirName / casKey / "binary"

        if exitCode == 0 and fileExists(casTmp):
          try:
            safeMoveFile(casTmp, casBinary)
            # DEBT#524: digest sidecar after the binary rename — same
            # integrity contract as gate_cas.compileGateToCas*. A store
            # without the sidecar is an incomplete entry (permanent CAS
            # MISS under resolve verification), so report it as failed.
            if writeCasBinarySidecar(casBinary).len == 0:
              logError("precompile_gates", "Digest sidecar write failed for " & gateId &
                ": entry incomplete (fail-closed, DEBT#524)")
              result[jobIdx] = CompileResult(index: jobIdx, gateId: gateId, failed: true)
            else:
              result[jobIdx] = CompileResult(index: jobIdx, gateId: gateId, compiled: true, casPath: casBinary)
          except CatchableError as e:
            logError("precompile_gates", "Atomic move failed for " & gateId & ": " & e.msg)
            result[jobIdx] = CompileResult(index: jobIdx, gateId: gateId, failed: true)
        else:
          if fileExists(casTmp):
            try: removeFile(casTmp)
            except CatchableError:
              logWarn("precompile_gates", "Failed to clean up temp file for " & gateId)
          result[jobIdx] = CompileResult(index: jobIdx, gateId: gateId, failed: true)
        close(inFlight[i].p)
        inFlight.del(i)
        inc completed

    if completed < jobs.len:
      sleep(50)

proc loadGatesFromManifest(repoRoot: string): seq[PrecompileTarget] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let indexFile = repoRoot / "src" / "gate" / "manifest.d" / "_index.json"
  if not fileExists(indexFile):
    return @[]

  let indexContent = try: readFile(indexFile) except CatchableError: ""
  if indexContent.len == 0:
    return @[]

  var gates: seq[PrecompileTarget]
  for line in indexContent.splitLines():
    let filename = line.strip()
    if filename.len == 0:
      continue

    let manifestPath = repoRoot / "src" / "gate" / "manifest.d" / filename
    if not fileExists(manifestPath):
      # _index.json lists gate IDs without extension; manifest files are <id>.json.
      let jsonPath = manifestPath & ".json"
      if not fileExists(jsonPath):
        continue
      let content = readFile(jsonPath)
      let j = parseJson(content)
      let gateId = if j.hasKey("id"): j["id"].getStr()
                   else: filename.replace(".json", "")
      let entry = if j.hasKey("entry"): j["entry"].getStr()
                  else: ""
      let executionMode = if j.hasKey("execution_mode"): j["execution_mode"].getStr()
                          elif j.hasKey("executionMode"): j["executionMode"].getStr()
                          else: "aot"
      gates.add(PrecompileTarget(
        gateId: gateId,
        entry: entry,
        sourceFile: "",
        sourceHash: "",
        executionMode: executionMode,
      ))
      continue

    try:
      let content = readFile(manifestPath)
      let j = parseJson(content)

      let gateId = if j.hasKey("id"): j["id"].getStr()
                   else: filename.replace(".json", "")
      let entry = if j.hasKey("entry"): j["entry"].getStr()
                  else: ""
      let executionMode = if j.hasKey("execution_mode"): j["execution_mode"].getStr()
                          elif j.hasKey("executionMode"): j["executionMode"].getStr()
                          else: "aot"

      gates.add(PrecompileTarget(
        gateId: gateId,
        entry: entry,
        sourceFile: "",
        sourceHash: "",
        executionMode: executionMode,
      ))
    except CatchableError:
      continue

  gates

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # B-layer cache provenance probe contract: strict self-check verdict only —
  # no manifest load, no gate precompilation, no side effects (mismatch
  # FATAL-exits 1 inside verifyProvenanceOrFatal).
  if isProvenanceSelfCheckRequest(commandLineParams()):
    verifyProvenanceOrFatal("bin" / "precompile_gates")
    logInfo("precompile_gates", "[OK] precompile_gates provenance self-check: embedded BuildSourceHash == live src tree (" & BuildSourceHash & ")")
    quit(0)

  let repoRoot = findRepoRoot()
  if repoRoot.len == 0:
    logError("precompile_gates", "[precompile] ERROR: Cannot find repo root")
    quit(1)

  setCurrentDir(repoRoot)

  let gates = loadGatesFromManifest(repoRoot)
  let totalGates = gates.len
  logInfo("precompile_gates", "[precompile] Loaded " & $totalGates & " gates from manifest")

  var currentFingerprint = buildCurrentFingerprint(repoRoot)

  var compilableGates: seq[PrecompileTarget]

  let buildEnvHash = computeBuildEnvHash(repoRoot)

  # VS-T closure manifests (docs/evidence/vst_dependency_authority_handoff_2026-11-08.md):
  # every CAS key below is computed from the compiler-truth genDepend
  # manifests — regenerate them (genDepend through the production bash
  # capture contract, tools/ci/generate_gate_closure_manifests.sh sourcing
  # pp_capture_manifest, concurrent per-call-isolated captures since
  # 2026-11-09) BEFORE any key computation. Manifests are
  # regenerated unconditionally on every run: a stale manifest cannot be
  # detected at read time when the tree gained closure members (undercount
  # again), so correctness-first mandates regeneration (no staleness
  # stamps — VS-T hard constraint). Generation failure = build failure
  # (quit 1): a gate without a valid manifest gets no CAS key and fails
  # closed at read time; it is never silently excluded (§0.9).
  block closureManifestGeneration:
    var targetLines: seq[string] = @[]
    for gate in gates:
      if gate.entry.len == 0:
        continue
      let srcFile = resolveGateSourcePath(gate.entry, repoRoot)
      if srcFile.len == 0:
        continue
      targetLines.add(gate.gateId & "\t" & (repoRoot / srcFile))
    if targetLines.len == 0:
      logInfo("precompile_gates", "[precompile] no compilable gate targets — skipping closure manifest generation")
      break closureManifestGeneration
    let script = repoRoot / "tools" / "ci" / "generate_gate_closure_manifests.sh"
    if not fileExists(script):
      logError("precompile_gates", "[precompile] FATAL: closure manifest generator missing: " & script)
      quit(1)
    let flags = closure_manifest.genDependProfile(repoRoot)
    if flags.len == 0:
      logError("precompile_gates", "[precompile] FATAL: genDepend profile unavailable (repoRoot not resolvable)")
      quit(1)
    let outDir = repoRoot / closure_manifest.ManifestDirRel
    let targetsFile = getTempDir() / ("axiom_closure_targets_" & $getCurrentProcessId() & ".tsv")
    try:
      writeFile(targetsFile, targetLines.join("\n") & "\n")
    except CatchableError as e:
      logError("precompile_gates", "[precompile] FATAL: cannot write closure targets file: " & e.msg)
      quit(1)
    let genCmd = "bash " & quoteShell(script) & " " & quoteShell(repoRoot) & " " &
      quoteShell(targetsFile) & " " & quoteShell(outDir) & " " & quoteShell(flags)
    let genStart = epochTime()
    let (genOut, genCode) = execCmdEx(genCmd)
    try:
      removeFile(targetsFile)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    if genOut.strip().len > 0:
      logInfo("precompile_gates", "[closure-manifest] " & genOut.strip())
    if genCode != 0:
      logError("precompile_gates", "[precompile] FATAL: closure manifest generation failed (exit " &
        $genCode & ") — fail-closed, no gate keys will be computed from stale manifests")
      quit(1)
    logInfo("precompile_gates", "[closure-manifest] generation done in " &
      formatFloat(epochTime() - genStart, ffDecimal, 1) & "s (genDepend)")

  for gate in gates:
    if gate.entry.len == 0:
      continue
    let executionMode = toLowerAscii(gate.executionMode)
    let srcFile = resolveGateSourcePath(gate.entry, repoRoot)
    if srcFile.len == 0:
      continue
    # verification_dag_contract.md §3: source identity = transitive import
    # closure Merkle root (DEBT#449). Unresolved ("") → no fingerprint entry
    # and no CAS identity (fail-closed, DEBT#450).
    let srcHash = computeTransitiveSourceHash(srcFile, repoRoot / "src")
    if srcHash.len == 0:
      logError("precompile_gates", "[precompile] WARNING: transitive closure unresolved for " & gate.gateId &
        " (fail-closed, DEBT#449/#450) — excluded from fingerprint")
      continue
    currentFingerprint.gateSourceHashes.add((gate.gateId, srcHash))
    compilableGates.add(PrecompileTarget(
      gateId: gate.gateId,
      entry: gate.entry,
      sourceFile: srcFile,
      sourceHash: srcHash,
      executionMode: gate.executionMode,
    ))

  currentFingerprint.gateCount = totalGates

  logInfo("precompile_gates", "[precompile] " & $compilableGates.len & " gates have compilable source entries")

  let lockPath = resolveLockPath(repoRoot)
  let existingLock = parseLockFile(lockPath)

  var gatesToCompile: seq[PrecompileTarget]
  var forceAll = false

  if existingLock.isSome:
    let old = existingLock.get

    if envFingerprintChanged(old, currentFingerprint):
      logInfo("precompile_gates", "[precompile] Environment changed -- recompiling all gates")
      forceAll = true
    else:
      let changedIds = findChangedGateIds(old, currentFingerprint)
      if changedIds.len == 0:
        logInfo("precompile_gates", "[precompile] All gate binaries up to date (" & $totalGates & " gates)")
        for cg in compilableGates:
          let casPath = resolveCasBinaryPathWithHash(
            cg.gateId, cg.sourceFile, repoRoot, cg.sourceHash, "", buildEnvHash)
          if casPath.len == 0:
            logWarn("precompile_gates", "[precompile] CAS binary missing for " & cg.gateId &
              " -- rebuilding from source hash")
            gatesToCompile.add(cg)
      else:
        logInfo("precompile_gates", "[precompile] " & $changedIds.len & " gate(s) changed source -- selective recompile")
        var changedSet: seq[string] = changedIds
        for cg in compilableGates:
          var isChanged = false
          for cid in changedSet:
            if cid == cg.gateId:
              isChanged = true
              break
          if isChanged:
            gatesToCompile.add(cg)
  else:
    logInfo("precompile_gates", "[precompile] No lock file found -- compiling all gates")
    forceAll = true

  if forceAll:
    gatesToCompile = compilableGates

  if gatesToCompile.len == 0:
    logInfo("precompile_gates", "[precompile] Nothing to compile")
    currentFingerprint.createdAt = $now().utc
    writeLockFileAtomic(lockPath, currentFingerprint)
    quit(0)

  var compiled = 0
  var cached = 0
  var failed = 0
  var failedGateIds: seq[string]
  let startTime = epochTime()

  var jobs = newSeq[CompileJob](gatesToCompile.len)
  for i, cg in gatesToCompile:
    jobs[i] = CompileJob(index: i, gate: cg)

  let compileResults = runCompileJobsParallel(jobs, repoRoot, buildEnvHash)

  for res in compileResults:
    let idx = res.index + 1
    let progress = "[" & $idx & "/" & $gatesToCompile.len & "] "

    if res.cached:
      cached += 1
      logInfo("precompile_gates", progress & res.gateId & "... cached")
      continue

    if res.compiled:
      compiled += 1
      logInfo("precompile_gates", progress & res.gateId & "... OK")
      continue

    failed += 1
    failedGateIds.add(res.gateId)
    logError("precompile_gates", progress & res.gateId & "... FAILED" &
             (if res.output.len > 0: " (" & res.output.strip() & ")" else: ""))

  let elapsed = epochTime() - startTime

  logError("precompile_gates", "[precompile] Done in " & formatFloat(elapsed, ffDecimal, 1) &
                   "s: " & $compiled & " compiled, " & $cached & " cached, " &
                   $failed & " failed")

  currentFingerprint.createdAt = $now().utc
  writeLockFileAtomic(lockPath, currentFingerprint)

  if failed > 0:
    logError("precompile_gates", "[precompile] FATAL: " & $failed & " gate(s) failed to compile")
    logError("precompile_gates", "  failing gate IDs: " & failedGateIds.join(", "))
    quit(1)

when isMainModule:
  main()

{.pop.}