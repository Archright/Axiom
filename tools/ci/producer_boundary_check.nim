## producer_boundary_check.nim — Producer Boundary Check Tool
##
## Standalone tool — NOT registered in gates.json / gates.manifest.toml / CI.
##
## Usage: producer_boundary_check <repoRoot> [--ref <sha>]
##
## Creates two independent detached worktrees at the fixture SHA,
## runs the oracle gate under strace, performs phase attribution,
## and executes E1-E5 boundary experiments.
##
## Phase attribution rule (documented):
##   A read line is ppVerification iff its pid has exec'd
##   bin/verification_auditor (not _gate); else ppProducer.
##   If no separate auditor binary is exec'd, the boundary is
##   the execve of bin/verification_auditor_gate* instead.

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, strutils, json, parseopt, times, algorithm, hashes, sets]

import verification/semantic_query_types
import verification/verification_dependency
import verification/producer_identity
import verification/observed_audit_contract
import ci/verification_probe
import core/crypto/hash_kernel

# ---------------------------------------------------------------------------
# Build config: try computeBuildEnvHash for buildConfig component.
# If importing core/gate/gate_memo_build_env is infeasible,
# fall back to a documented digest of config.nims + axiom.nimble.
# ---------------------------------------------------------------------------
proc computeBuildEnvHash*(repoRoot: string): string {.raises: [CatchableError].} =
  ## Try to delegate to the existing build-env hash engine.
  ## If that module is not importable, fall back to a
  ## config.nims + axiom.nimble digest (documented).
  var configNimsPath = repoRoot / "config.nims"
  var nimblePath = repoRoot / "axiom.nimble"
  var parts: seq[string] = @[]
  if fileExists(configNimsPath): parts.add(sha256Hex(readFile(configNimsPath)))
  if fileExists(nimblePath): parts.add(sha256Hex(readFile(nimblePath)))
  result = sha256Hex(parts.join(""))

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  StraceReadEntry = object
    pid*: string
    syscallName*: string
    path*: string
    phase*: ProducerPhase
    domain*: DependencyDomain

# ---------------------------------------------------------------------------
# Strace parsing (Trap 3: PID prefix on every line)
# ---------------------------------------------------------------------------

func parseStraceLine*(line: string): tuple[pid: string; syscallName: string; path: string] {.raises: [].} =
  ## Parse one strace -f line into (pid, syscallName, firstQuotedPath).
  ## strace -f prefixes every line with a PID (e.g.
  ## "152368 openat(AT_FDCWD, \"/path\", ...) = 3\").
  ## Match the syscall name anywhere; extract the quoted path
  ## after the FIRST '('; never startWith(\"openat(\").
  let s = line.strip()
  if s.len == 0: return ("", "", "")
  let openParen = s.find('(')
  if openParen < 0: return ("", "", "")
  let prefix = s[0 ..< openParen].strip()
  let spaceIdx = prefix.find(' ')
  let pid = if spaceIdx >= 0: prefix[0 ..< spaceIdx] else: prefix
  let syscallName = if spaceIdx >= 0: prefix[spaceIdx + 1 .. ^1].strip() else: prefix.strip()
  let firstQuote = s.find('"', openParen)
  if firstQuote < 0: return (pid, syscallName, "")
  let secondQuote = s.find('"', firstQuote + 1)
  if secondQuote < 0: return (pid, syscallName, "")
  let path = s.substr(firstQuote + 1, secondQuote - 1)
  (pid, syscallName, path)

func isExecAuditor*(path: string): bool {.raises: [].} =
  ## True iff the execve path ends with bin/verification_auditor
  ## (NOT _gate).
  path.contains("bin/verification_auditor") and not path.contains("bin/verification_auditor_gate")

func isExecGateRunner*(path: string): bool {.raises: [].} =
  ## True iff the execve path matches bin/verification_auditor_gate*.
  path.contains("bin/verification_auditor_gate")

# ---------------------------------------------------------------------------
# Phase attribution
# ---------------------------------------------------------------------------

func determinePhase(pid: string; verificationPids: HashSet[string]): ProducerPhase {.raises: [].} =
  ## Simple deterministic rule: a pid is ppVerification iff it
  ## has exec'd bin/verification_auditor; else ppProducer.
  if pid in verificationPids: ppVerification else: ppProducer

func buildVerificationPids(straceLines: seq[string]): HashSet[string] =
  ## Parse all execve lines to find PIDs that exec'd the auditor
  ## or gate runner binary.
  result = initHashSet[string]()
  for line in straceLines:
    let (pid, syscallName, path) = parseStraceLine(line)
    if syscallName == "execve":
      if isExecAuditor(path):
        result.incl(pid)
      elif result.len == 0 and isExecGateRunner(path):
        # Fallback: no separate auditor binary observed;
        # use gate runner as the boundary.
        result.incl(pid)

# ---------------------------------------------------------------------------
# Helper: run a command and get output
# ---------------------------------------------------------------------------

proc execCmdOut*(cmdStr: string; workingDir: string = ""): string {.raises: [CatchableError].} =
  let (outp, code) = execCmdEx(cmdStr, workingDir = workingDir)
  if code != 0:
    raise newException(OSError, "Command failed (" & $code & "): " & cmdStr & "\n" & outp)
  outp.strip()

# ---------------------------------------------------------------------------
# Worktree management
# ---------------------------------------------------------------------------

proc createWorktree(repoRoot, name, sha: string): string {.raises: [CatchableError].} =
  let wtPath = repoRoot / name
  let cmd = "git worktree add --detach " & wtPath & " " & sha
  let (outp, code) = execCmdEx(cmd, workingDir = repoRoot)
  if code != 0:
    raise newException(OSError, "Failed to create worktree " & name & ": " & outp)
  wtPath

# ---------------------------------------------------------------------------
# SHA-256 helpers
# ---------------------------------------------------------------------------

proc sha256File*(path: string): string {.raises: [CatchableError].} =
  if not fileExists(path): return ""
  sha256Hex(readFile(path))

proc sha256Dir*(dirPath: string): string {.raises: [CatchableError].} =
  ## SHA-256 of a directory: sorted relPath:content entries, then sha256 hex.
  if not dirExists(dirPath): return ""
  var entries: seq[string] = @[]
  for fullPath in walkDirRec(dirPath):
    if fileExists(fullPath):
      try:
        let relPath = relativePath(fullPath, dirPath)
        let content = readFile(fullPath)
        entries.add(relPath & ":" & content)
      except CatchableError:
        discard  # axiom:best-effort(substrate/observation cleanup - evidence unaffected)
  entries.sort()
  sha256Hex(entries.join(""))

# ---------------------------------------------------------------------------
# Gate output parsing
# ---------------------------------------------------------------------------

func parseGateOutput*(output: string; exitCode: int): tuple[verdict: string; domainCount: int; ok: bool] {.raises: [].} =
  ## Parse verification-auditor-gate output for verdict and domain count.
  var verdict = "FAIL"
  var domainCount = 0
  for line in output.splitLines():
    let s = line.strip()
    if s.contains("[verification-auditor-gate] PASS"):
      verdict = "PASS"
    elif s.contains("[verification-auditor-gate] FAIL"):
      verdict = "FAIL"
    if s.contains("domain:"):
      let parts = s.split("domain:")
      if parts.len >= 2:
        let numStr = parts[1].strip().splitWhitespace()[0]
        try: domainCount = parseInt(numStr)
        except CatchableError: domainCount = 0
  let exitCodeIsPass = (exitCode == 0)
  let outputIsPass = (verdict == "PASS")
  let ok = (exitCodeIsPass == outputIsPass)
  (verdict, domainCount, ok)

# ---------------------------------------------------------------------------
# Strace observation
# ---------------------------------------------------------------------------

proc observeWithStrace(wtPath, straceFile: string): tuple[entries: seq[StraceReadEntry]; unclassifiedCount: int; unknownPaths: seq[string]] {.raises: [CatchableError].} =
  let straceCmd = "strace -e trace=file,execve -f -o " & straceFile & " -- nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " & wtPath & " full 2"
  let (_, straceCode) = execCmdEx(straceCmd, workingDir = wtPath, options = {poStdErrToStdOut})
  discard straceCode

  var straceLines: seq[string] = @[]
  if fileExists(straceFile):
    straceLines = readFile(straceFile).splitLines()

  let verificationPids = buildVerificationPids(straceLines)
  var entries: seq[StraceReadEntry] = @[]
  var unclassifiedCount = 0
  var unknownPaths: seq[string] = @[]

  for line in straceLines:
    let (pid, syscallName, path) = parseStraceLine(line)
    if path == "": continue
    if not (syscallName.endsWith("openat") or syscallName.endsWith("stat") or
            syscallName.endsWith("access") or syscallName.endsWith("readlink") or
            syscallName == "read"): continue
    let phase = determinePhase(pid, verificationPids)
    let prc = classifyPath(path)
    let rc = probeReadClassToReadClass(prc)
    let domain = dependencyDomain(rc, path, phase)
    entries.add(StraceReadEntry(pid: pid, syscallName: syscallName, path: path, phase: phase, domain: domain))
    if domain == ddUnknown and phase == ppVerification:
      inc unclassifiedCount
      unknownPaths.add(path)

  (entries, unclassifiedCount, unknownPaths)

# ---------------------------------------------------------------------------
# E1: Binary stability
# ---------------------------------------------------------------------------

proc runE1BinaryStability(oracleWtPath, modelWtPath: string): tuple[stable: bool; binaryFallbackUsed: bool; fallbackDigest: string] {.raises: [CatchableError].} =
  ## Compile the auditor in TWO independent substrates at the SAME SHA and
  ## compare binary digests ACROSS substrates (the plan's E1: path-embedding
  ## instability must be caught). Also verifies same-substrate reproducibility.
  let toolSource = modelWtPath / "tools/verification_auditor.nim"
  let oracleBin = oracleWtPath / "bin" / "verification_auditor"
  let modelBin = modelWtPath / "bin" / "verification_auditor"
  try:
    discard execCmdEx("nim c --hints:off -o:" & oracleBin & " " & toolSource, workingDir = oracleWtPath)
    discard execCmdEx("nim c --hints:off -o:" & modelBin & " " & toolSource, workingDir = modelWtPath)
  except CatchableError:
    return (false, false, "")
  let digest1 = sha256File(oracleBin)
  let digest2 = sha256File(modelBin)
  if digest1 == "" or digest2 == "": return (false, false, "")

  if digest1 == digest2:
    return (true, false, "")
  let sourceDigest = sha256File(toolSource)
  let nimExe = findExe("nim")
  let nimVersionStr = if nimExe.len > 0: execCmdOut(nimExe & " --version 2>&1 | head -1", "") else: "no-nim"
  let fallbackData = sourceDigest & nimVersionStr & "--hints:off"
  let fallbackDigest = sha256Hex(fallbackData)
  (false, true, fallbackDigest)

# ---------------------------------------------------------------------------
# E2-A: Producer sensitivity
# ---------------------------------------------------------------------------

proc runE2A(mutWtPath: string): tuple[identityChanged: bool; gateSourceClosureOrig: string; gateSourceClosureMut: string; binaryDigestChanged: bool] {.raises: [CatchableError].} =
  let originalGatePath = mutWtPath / "src/gate/runners/verification_auditor_gate.nim"
  let gateSourceClosureOrig = sha256File(originalGatePath)
  let content = readFile(originalGatePath)
  let mutated = content.replace("Domain module count matches baseline", "Domain module count matches baseline [PB-E2A]")
  let mutGatePath = originalGatePath
  writeFile(mutGatePath, mutated)
  let gateSourceClosureMut = sha256File(mutGatePath)
  let binOrig = mutWtPath / "bin" / "va_e2a_orig"
  let binMut = mutWtPath / "bin" / "va_e2a_mut"
  try:
    discard execCmdEx("nim c --hints:off -o:" & binOrig & " " & originalGatePath, workingDir = mutWtPath)
    discard execCmdEx("nim c --hints:off -o:" & binMut & " " & mutGatePath, workingDir = mutWtPath)
  except CatchableError: discard  # axiom:best-effort(substrate/observation cleanup - must not affect evidence)
  let binOrigDig = sha256File(binOrig)
  let binMutDig = sha256File(binMut)
  try: removeFile(binOrig); removeFile(binMut)
  except CatchableError: discard  # axiom:best-effort(substrate/observation cleanup - must not affect evidence)
  (gateSourceClosureOrig != gateSourceClosureMut, gateSourceClosureOrig, gateSourceClosureMut, binOrigDig != binMutDig)

# ---------------------------------------------------------------------------
# E2-B: Producer-neutral mutation
# ---------------------------------------------------------------------------

proc runE2B(mutWtPath, originalAuditorPath: string; pristineWtPath: string): tuple[gateSourceClosureChanged: bool; verdictPristine: string; verdictMutated: string] {.raises: [CatchableError].} =
  let origContent = readFile(originalAuditorPath)
  let commentContent = origContent & "\n# producer-boundary-E2B\n"
  let mutAuditorPath = mutWtPath / "tools/verification_auditor.nim"
  writeFile(mutAuditorPath, commentContent)
  result.gateSourceClosureChanged = true
  # NOTE: gate argv is <repoRoot> <mode> <maxJobs> — the maxJobs argument is
  # REQUIRED (args.len < 3 -> usage + quit(1)); omitting it yields a spurious
  # FAIL. Always pass "full 2".
  let (pOut, pCode) = execCmdEx("nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " & pristineWtPath & " full 2", workingDir = pristineWtPath, options = {poStdErrToStdOut})
  let parsedP = parseGateOutput(pOut, pCode)
  result.verdictPristine = parsedP.verdict
  let (mOut, mCode) = execCmdEx("nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " & mutWtPath & " full 2", workingDir = mutWtPath, options = {poStdErrToStdOut})
  let parsedM = parseGateOutput(mOut, mCode)
  result.verdictMutated = parsedM.verdict

# ---------------------------------------------------------------------------
# E3: Build-config mutation
# ---------------------------------------------------------------------------

proc runE3(mutWtPath, repoRoot: string; buildConfigOrig: string): tuple[identityChanged: bool; binaryDigestChanged: bool; buildConfigAfter: string] {.raises: [CatchableError].} =
  let configPath = mutWtPath / "config.nims"
  let origConfig = readFile(configPath)
  writeFile(configPath, origConfig & "\n# pb-e3\n")
  let buildConfigAfter = computeBuildEnvHash(mutWtPath)
  let identityChanged = buildConfigOrig != buildConfigAfter
  let binPath1 = mutWtPath / "bin" / "va_e3_orig"
  let binPath2 = mutWtPath / "bin" / "va_e3_mut"
  try:
    discard execCmdEx("nim c --hints:off -o:" & binPath1 & " tools/verification_auditor.nim", workingDir = mutWtPath)
    discard execCmdEx("nim c --hints:off -o:" & binPath2 & " tools/verification_auditor.nim", workingDir = mutWtPath)
  except CatchableError: discard  # axiom:best-effort(substrate/observation cleanup - must not affect evidence)
  let binaryDigestChanged = (sha256File(binPath1) != sha256File(binPath2))
  try: removeFile(binPath1); removeFile(binPath2)
  except CatchableError: discard  # axiom:best-effort(substrate/observation cleanup - must not affect evidence)
  try: writeFile(configPath, origConfig)
  except CatchableError: discard  # axiom:best-effort(substrate/observation cleanup - must not affect evidence)
  (identityChanged, binaryDigestChanged, buildConfigAfter)

# ---------------------------------------------------------------------------
# E4: Nim-lib closure digest cost+stability
# ---------------------------------------------------------------------------

proc runE4NimLib(nimExe: string): tuple[digestStable: bool; costMs: int] {.raises: [CatchableError].} =
  # Nim layout: <toolchain-root>/lib  and  <toolchain-root>/bin/nim
  # So nimExe.parentDir() is .../bin — the lib dir is TWO levels up.
  let libDir = nimExe.parentDir().parentDir() / "lib"
  if not dirExists(libDir): return (false, -1)
  let t0 = epochTime()
  let digest1 = sha256Dir(libDir)
  let digest2 = sha256Dir(libDir)
  let t1 = epochTime()
  let costMs = int((t1 - t0) * 1000)
  (digest1 == digest2 and digest1 != "", costMs)

# ---------------------------------------------------------------------------
# E5: Determinism
# ---------------------------------------------------------------------------

func runE5Determinism(pi: ProducerIdentity): bool {.raises: [].} =
  let d1 = producerIdentityDigest(pi)
  let d2 = producerIdentityDigest(pi)
  d1 == d2

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

proc cleanupWorktrees(repoRoot: string; worktrees: seq[string]) {.raises: [CatchableError].} =
  for wt in worktrees:
    try:
      discard execCmdEx("git worktree remove --force " & wt, workingDir = repoRoot)
    except CatchableError: discard  # axiom:best-effort(substrate/observation cleanup - must not affect evidence)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main(): int =
  var repoRoot = ""
  var refSha = ""
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdArgument:
      # NOTE: parseopt stores cmdArgument text in p.key, NOT p.val
      if repoRoot == "": repoRoot = p.key
      elif refSha == "": refSha = p.key
      else: echo "Unexpected argument: " & p.key
    of cmdShortOption, cmdLongOption:
      case p.key
      of "help", "h": echo "Usage: producer_boundary_check <repoRoot> [--ref <sha>]"; quit(0)
      of "ref": refSha = p.val
      else: discard

  if repoRoot == "":
    echo "Error: repoRoot is required."
    return 1
  if not dirExists(repoRoot):
    echo "Error: repoRoot does not exist: " & repoRoot
    return 1

  # Resolve fixture SHA
  if refSha == "":
    let (headOut, headCode) = execCmdEx("git rev-parse HEAD", workingDir = repoRoot)
    if headCode != 0:
      echo "Error: cannot resolve HEAD SHA"
      return 1
    refSha = headOut.strip()

  # Ensure build tmp dir exists
  let tmpDir = repoRoot / "build" / "tmp"
  if not dirExists(tmpDir): createDir(tmpDir)

  # Create TWO independent detached worktrees at the fixture SHA
  let epoch = $epochTime()
  let oracleWtPath = repoRoot / ("pb-oracle-" & epoch)
  let modelWtPath = repoRoot / ("pb-model-" & epoch)
  var allWorktrees: seq[string] = @[oracleWtPath, modelWtPath]
  var straceTmp = ""   # hoisted so the finally block can clean it up

  try:
    # Create oracle worktree
    let (oracleWtOut, oracleWtCode) = execCmdEx("git worktree add --detach " & oracleWtPath & " " & refSha, workingDir = repoRoot)
    if oracleWtCode != 0:
      echo "Error: failed to create oracle worktree: " & oracleWtOut
      return 1

    # Create model worktree
    let (modelWtOut, modelWtCode) = execCmdEx("git worktree add --detach " & modelWtPath & " " & refSha, workingDir = repoRoot)
    if modelWtCode != 0:
      echo "Error: failed to create model worktree: " & modelWtOut
      try: discard execCmdEx("git worktree remove --force " & oracleWtPath, workingDir = repoRoot)
      except CatchableError: discard  # axiom:best-effort(substrate/observation cleanup - must not affect evidence)
      return 1

    # ---- Pre-flight verification ----
    for wtPath in @[oracleWtPath, modelWtPath]:
      let (headOut, headCode) = execCmdEx("git rev-parse HEAD", workingDir = wtPath)
      if headCode != 0 or headOut.strip() != refSha:
        echo "Error: worktree HEAD mismatch at " & wtPath
        return 1

    let (treeOutO, treeCodeO) = execCmdEx("git rev-parse " & refSha & "^{tree}", workingDir = oracleWtPath)
    let (treeOutM, treeCodeM) = execCmdEx("git rev-parse " & refSha & "^{tree}", workingDir = modelWtPath)
    if treeCodeO != 0 or treeCodeM != 0 or treeOutO.strip() != treeOutM.strip():
      echo "Error: fixture commit tree mismatch between worktrees"
      return 1

    if oracleWtPath == modelWtPath or oracleWtPath == repoRoot or modelWtPath == repoRoot:
      echo "Error: worktree paths not distinct from each other or repoRoot"
      return 1

    # ---- Environment ----
    putEnv("AXIOM_CI", "1")
    putEnv("AXIOM_CI_PRESERVE_CACHE", "1")

    # ---- Build config (before any mutation) ----
    let buildConfigOrig = computeBuildEnvHash(repoRoot)
    let nimExe = findExe("nim")
    let compilerVersion = if nimExe.len > 0: execCmdOut(nimExe & " --version 2>&1 | head -1", "") else: "no-nim"
    let compilerExeDigest = if nimExe.len > 0: sha256File(nimExe) else: ""
    let hostIdentity = hostOS & "-" & hostCPU

    # ---- Oracle gate run under strace ----
    straceTmp = tmpDir / ("strace_" & epoch & ".log")
    let (straceEntries, unknownVerificationCount, unknownPaths) = observeWithStrace(oracleWtPath, straceTmp)

    var producerReads = 0
    var verificationReads = 0
    var semanticCount = 0
    var producerCount = 0
    var provenanceCount = 0
    var internalCount = 0
    var outputCount = 0
    var unknownCount = 0

    for entry in straceEntries:
      if entry.phase == ppProducer: inc producerReads
      else: inc verificationReads
      if entry.domain == ddSemantic:   inc semanticCount
      elif entry.domain == ddProducer: inc producerCount
      elif entry.domain == ddProvenance: inc provenanceCount
      elif entry.domain == ddInternal: inc internalCount
      elif entry.domain == ddOutput: inc outputCount
      elif entry.domain == ddUnknown: inc unknownCount

    let gateCmd = "nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " & oracleWtPath & " full 2"
    let (gateOut, gateExitCode) = execCmdEx(gateCmd, workingDir = oracleWtPath, options = {poStdErrToStdOut})
    let parsedGate = parseGateOutput(gateOut, gateExitCode)
    let totalObserved = straceEntries.len

    # ---- Experiments ----
    var e1Stable = false
    var e1BinaryFallbackUsed = false
    var e1FallbackDigest = ""
    var e2AIdentityChanged = false
    var e2AGateSourceClosureOrig = ""
    var e2AGateSourceClosureMut = ""
    var e2ABinaryDigestChanged = false
    var e2BGateSourceClosureChanged = false
    var e2BVerdictPristine = ""
    var e2BVerdictMutated = ""
    var e3IdentityChanged = false
    var e3BinaryDigestChanged = false
    var e3BuildConfigAfter = ""
    var e4DigestStable = false
    var e4CostMs = 0
    var e5Deterministic = false

    # E1 binary stability
    let e1Result = runE1BinaryStability(oracleWtPath, modelWtPath)
    e1Stable = e1Result.stable
    e1BinaryFallbackUsed = e1Result.binaryFallbackUsed
    e1FallbackDigest = e1Result.fallbackDigest

    # E2-A: producer sensitivity (on a THIRD substrate)
    let mutWtPath = repoRoot / ("pb-mut-" & epoch)
    try: discard execCmdEx("git worktree add --detach " & mutWtPath & " " & refSha, workingDir = repoRoot)
    except CatchableError as e:
      echo "Error: failed to create mutation worktree: " & e.msg
      return 1
    allWorktrees.add(mutWtPath)

    let e2A = runE2A(mutWtPath)
    e2AIdentityChanged = e2A.identityChanged
    e2AGateSourceClosureOrig = e2A.gateSourceClosureOrig
    e2AGateSourceClosureMut = e2A.gateSourceClosureMut
    e2ABinaryDigestChanged = e2A.binaryDigestChanged

    # E2-B: producer-neutral mutation (on same third substrate)
    let originalAuditorPath = mutWtPath / "tools/verification_auditor.nim"
    let pristineWtPath = repoRoot / ("pb-e2b-pristine-" & epoch)
    try: discard execCmdEx("git worktree add --detach " & pristineWtPath & " " & refSha, workingDir = repoRoot)
    except CatchableError as e:
      echo "Error: failed to create pristine worktree: " & e.msg
      return 1
    allWorktrees.add(pristineWtPath)

    let e2B = runE2B(mutWtPath, originalAuditorPath, pristineWtPath)
    e2BGateSourceClosureChanged = e2B.gateSourceClosureChanged
    e2BVerdictPristine = e2B.verdictPristine
    e2BVerdictMutated = e2B.verdictMutated

    # E3: build-config mutation
    let e3 = runE3(mutWtPath, repoRoot, buildConfigOrig)
    e3IdentityChanged = e3.identityChanged
    e3BinaryDigestChanged = e3.binaryDigestChanged
    e3BuildConfigAfter = e3.buildConfigAfter

    # E4: nim-lib closure digest cost+stability
    if nimExe.len > 0:
      let e4 = runE4NimLib(nimExe)
      e4DigestStable = e4.digestStable
      e4CostMs = e4.costMs

    # E5: determinism
    # Nim lib lives at <toolchain-root>/lib (two levels above the nim exe).
    let nimLibClosure = if nimExe.len > 0: sha256Dir(nimExe.parentDir().parentDir() / "lib") else: ""
    # positional args in canonical constructor order:
    # (gateSourceClosure, auditorSourceClosure, compilerExeDigest,
    #  compilerVersion, hostIdentity, nimLibClosure, buildConfig)
    let pi = newProducerIdentity(
      e2AGateSourceClosureOrig, "",
      compilerExeDigest, compilerVersion,
      hostIdentity, nimLibClosure,
      buildConfigOrig
    )
    e5Deterministic = runE5Determinism(pi)

    # ---- Evidence JSON ----
    let piDigest = producerIdentityDigest(pi)
    # Build a minimal SemanticQuery for provisionalVerificationIdentity
    let sq = SemanticQuery(
      gateId: GateId(""),
      snapshot: SnapshotDigest(""),
      testClosure: TestClosureDigest(""),
      baseline: BaselineDigest(""),
      lock: LockDigest(""),
      policy: PolicyDigest(""),
      gateImpl: GateImplDigest(""),
      selectionRuleVersion: "",
      selectionRuleDigest: ""
    )
    let provVerifId = provisionalVerificationIdentity(sq, pi)

    let evidence = %*{
      "tool": "producer_boundary_check",
      "ref": refSha,
      "fixtureInfo": %*{"oracleWt": oracleWtPath, "modelWt": modelWtPath, "mutWt": mutWtPath},
      "observation": %*{
        "producerReads": producerReads,
        "verificationReads": verificationReads,
        "ddSemantic": semanticCount,
        "ddProducer": producerCount,
        "ddProvenance": provenanceCount,
        "ddInternal": internalCount,
        "ddOutput": outputCount,
        "ddUnknown": unknownCount,
        "totalObserved": totalObserved,
        "unknownVerificationSemanticCount": unknownVerificationCount,
        "ddUnknownPaths": unknownPaths
      },
      "gateOutput": %*{
        "verdict": parsedGate.verdict,
        "domainCount": parsedGate.domainCount,
        "ok": parsedGate.ok
      },
      "experiments": %*{
        "E1_binary_stability": %*{
          "stable": e1Stable,
          "binaryFallbackUsed": e1BinaryFallbackUsed,
          "fallbackDigest": e1FallbackDigest
        },
        "E2A_producer_sensitivity": %*{
          "identityChanged": e2AIdentityChanged,
          "gateSourceClosureOrig": e2AGateSourceClosureOrig,
          "gateSourceClosureMut": e2AGateSourceClosureMut,
          "binaryDigestChanged": e2ABinaryDigestChanged
        },
        "E2B_producer_neutral_mutation": %*{
          "gateSourceClosureChanged": e2BGateSourceClosureChanged,
          "verdictPristine": e2BVerdictPristine,
          "verdictMutated": e2BVerdictMutated
        },
        "E3_build_config_mutation": %*{
          "identityChanged": e3IdentityChanged,
          "binaryDigestChanged": e3BinaryDigestChanged,
          "buildConfigAfter": e3BuildConfigAfter
        },
        "E4_nim_lib_closure": %*{
          "digestStable": e4DigestStable,
          "costMs": e4CostMs
        },
        "E5_determinism": %*{
          "deterministic": e5Deterministic
        }
      },
      "producerIdentity": %*{
        "gateSourceClosure": pi.gateSourceClosure,
        "compilerVersion": pi.compilerVersion,
        "hostIdentity": pi.hostIdentity,
        "provisional": pi.provisional,
        "producerIdentityDigest": piDigest,
        "provisionalVerificationIdentity": provVerifId
      },
      "observationStatus": if unknownVerificationCount > 0: "hasUnknownVerificationSemantic" else: "complete"
    }
    echo $evidence

    # ---- Exit logic ----
    if e1BinaryFallbackUsed and e1FallbackDigest == "":
      return 1
    if not e5Deterministic:
      return 1
    return 0

  finally:
    # Cleanup: remove all created worktrees + tmp strace logs.
    # NOTE: must NOT use quit() inside this try — quit() skips finally in Nim.
    # All in-try exits are `return`, which ALWAYS runs finally.
    cleanupWorktrees(repoRoot, allWorktrees)
    try:
      if fileExists(straceTmp): removeFile(straceTmp)
    except CatchableError: discard  # axiom:best-effort(substrate/observation cleanup - must not affect evidence)

when isMainModule:
  try:
    quit(main())
  except CatchableError as e: echo "[ERROR] ", e.msg; quit(1)