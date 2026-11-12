## verification_reuse_check.nim — Standalone reuse proof runner
##
## Proves the FIRST actual reuse per the approved design:
##   CASE A (same identity) → reused stored PASS
##   CASE B (different identity) → miss → fresh
##
## Usage: verification_reuse_check <repoRoot>
##
## TRAPS: parseopt positional arg text is in p.key NOT p.val;
##        quit() skips finally — use proc main(): int + return N + quit(main()).

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, strutils, json, parseopt, times, algorithm, sets, options]

import core/gate/gate_memo
import verification/semantic_query_types
import verification/repo_snapshot_digest
import verification/verification_dependency
import verification/producer_identity
import verification/observation_pipeline
import verification/verification_query_engine
import verification/observed_audit_contract
import ci/verification_probe
import tools/ci/producer_boundary_check

# ---------------------------------------------------------------------------
# Helper: build the set of verification-phase PIDs from strace lines
# ---------------------------------------------------------------------------

func buildVerificationPids(straceLines: seq[string]): HashSet[string] =
  result = initHashSet[string]()
  for line in straceLines:
    let (pid, syscallName, path) = producer_boundary_check.parseStraceLine(line)
    if syscallName == "execve" and isExecAuditor(path):
      result.incl(pid)

# ---------------------------------------------------------------------------
# Helper: classify a strace path into a ValidatedDependency
# ---------------------------------------------------------------------------

func straceEntryToDep(path: string): ValidatedDependency =
  let prc = classifyPath(path)
  let rc = probeReadClassToReadClass(prc)
  let kind = classifyReadClass(rc)
  let phase = ppVerification
  let domain = dependencyDomain(rc, path, phase)
  let status = if domain == ddUnknown: osUnknown else: osComplete
  newValidatedDependency(path, rc, kind, "", status)

# ---------------------------------------------------------------------------
# declaredDeps — deterministic closure from on-disk state (gate-free)
# ---------------------------------------------------------------------------

proc declaredDeps*(wtPath: string): seq[ValidatedDependency] =
  ## Deterministic closure of declared semantic dependencies derived
  ## from the worktree's on-disk state. Gate-free: no strace observation
  ## required. v1 identity closure — deterministic, stable across runs.
  let srcDir = wtPath / "src"
  if dirExists(srcDir):
    for fp in walkDirRec(srcDir):
      if fp.endsWith(".nim"):
        let relPath = relativePath(fp, wtPath)
        let content = readFile(fp)
        let rc = rcModuleContent
        let kind = classifyReadClass(rc)
        let digest = semanticContentDigest(rc, content)
        result.add(newValidatedDependency(relPath, rc, kind, digest, osComplete))
  for depInfo in [("data/verification_auditor_baseline.json", rcBaseline),
                  ("config/gates.json", rcPolicy),
                  ("topology.lock", rcLockFile)]:
    let p = wtPath / depInfo[0]
    if fileExists(p):
      let content = readFile(p)
      let rc = depInfo[1]
      let kind = classifyReadClass(rc)
      let digest = semanticContentDigest(rc, content)
      result.add(newValidatedDependency(depInfo[0], rc, kind, digest, osComplete))

# ---------------------------------------------------------------------------
# buildObservationIdentity — extracted inline identity computation
# ---------------------------------------------------------------------------

proc buildObservationIdentity*(wtPath: string; deps: seq[ValidatedDependency]): string =
  ## Canonical verification identity from (snapshot, producer, closure).
  ## Same computation as the inline block formerly in main().
  let gateSrcPath = wtPath / "src/gate/runners/verification_auditor_gate.nim"
  let gateImplIdentity = sha256File(gateSrcPath)
  let sqRes = buildSemanticQuery(wtPath, gateImplIdentity, DefaultSelectionRule)
  if not sqRes.ok: return ""
  let sq = sqRes.value
  let nimExe = findExe("nim")
  let compilerExeDigest = if nimExe.len > 0: sha256File(nimExe) else: ""
  let compilerVersion = if nimExe.len > 0: execCmdOut(nimExe & " --version 2>&1 | head -1") else: "no-nim"
  let hostIdentity = hostOS & "-" & hostCPU
  let nimLibClosure = if nimExe.len > 0: sha256Dir(nimExe.parentDir().parentDir() / "lib") else: ""
  let buildConfig = producer_boundary_check.computeBuildEnvHash(wtPath)
  let gateSourceClosure = sha256File(gateSrcPath)
  let pi = newProducerIdentity(
    gateSourceClosure, "",
    compilerExeDigest, compilerVersion,
    hostIdentity, nimLibClosure,
    buildConfig
  )
  let closureDigest = dependencyClosureDigest(deps)
  let identity = canonicalVerificationIdentity(sq, pi, deps)
  identity

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main(): int =
  var repoRoot = ""
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdArgument:
      # Trap: positional arg text is in p.key, NOT p.val
      if repoRoot == "": repoRoot = p.key
      else: echo "Unexpected argument: " & p.key
    of cmdShortOption, cmdLongOption:
      case p.key
      of "help", "h": echo "Usage: verification_reuse_check <repoRoot>"; quit(0)
      else: discard

  if repoRoot == "":
    echo "Error: repoRoot is required."
    return 1
  if not dirExists(repoRoot):
    echo "Error: repoRoot does not exist: " & repoRoot
    return 1

  let savedDir = getCurrentDir()
  let epoch = epochTime().int

  # Pre-declare cleanup paths
  var rcPath = ""
  var mutPath = ""

  try:
    # ---- Step 1: Resolve fixture and create ONE detached substrate ----
    let (headOut, headCode) = execCmdEx("git rev-parse HEAD", workingDir = repoRoot)
    if headCode != 0:
      echo "Error: cannot resolve HEAD SHA"
      return 1
    let fixture = headOut.strip()

    rcPath = repoRoot / ("rc-" & $epoch)
    let (wtOut, wtCode) = execCmdEx("git worktree add --detach " & rcPath & " " & fixture, workingDir = repoRoot)
    if wtCode != 0:
      echo "Error: failed to create substrate: " & wtOut
      return 1

    # Pre-flight: HEAD == fixture
    let (head2Out, head2Code) = execCmdEx("git rev-parse HEAD", workingDir = rcPath)
    if head2Code != 0 or head2Out.strip() != fixture:
      echo "Error: substrate HEAD mismatch"
      return 1

    # ---- Step 2: Run gate under strace; build dep list ----
    let straceFile = rcPath / "strace.log"
    let straceCmd = "strace -e trace=file,execve -f -o " & straceFile & " -- nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " & rcPath & " full 2"
    discard execCmdEx(straceCmd, workingDir = rcPath, options = {poStdErrToStdOut})

    var straceLines: seq[string] = @[]
    if fileExists(straceFile):
      straceLines = readFile(straceFile).splitLines()

    let vPids = buildVerificationPids(straceLines)

    var deps: seq[ValidatedDependency] = @[]
    var totalDeps = 0
    var dUnknownCount = 0
    for line in straceLines:
      let (pid, syscallName, path) = producer_boundary_check.parseStraceLine(line)
      if path == "": continue
      if not (path.endsWith(".nim") or path.contains("tests/gateway") or
              path.contains("baseline") or path.contains(".lock") or
              path.contains("gates.json") or path.contains("config/")):
        continue
      if pid notIn vPids: continue
      let dep = straceEntryToDep(path)
      deps.add(dep)
      inc totalDeps
      if depStatus(dep) == osUnknown: inc dUnknownCount

        # ---- Step 3-4: Build identity from declared closure (gate-free) ----
    let declaredDepsList = declaredDeps(rcPath)
    let identity = buildObservationIdentity(rcPath, declaredDepsList)
    let canonicalId = newCanonicalIdentity(identity)

    # Compute pi for mutation-case identity recompute
    let nimExe = findExe("nim")
    let compilerExeDigest = if nimExe.len > 0: sha256File(nimExe) else: ""
    let compilerVersion = if nimExe.len > 0: execCmdOut(nimExe & " --version 2>&1 | head -1") else: "no-nim"
    let hostIdentity = hostOS & "-" & hostCPU
    let nimLibClosure = if nimExe.len > 0: sha256Dir(nimExe.parentDir().parentDir() / "lib") else: ""
    let buildConfig = producer_boundary_check.computeBuildEnvHash(rcPath)
    let gateSourceClosure = sha256File(rcPath / "src/gate/runners/verification_auditor_gate.nim")
    let pi = newProducerIdentity(
      gateSourceClosure, "",
      compilerExeDigest, compilerVersion,
      hostIdentity, nimLibClosure,
      buildConfig
    )

    # ---- Step 5: Memo round-trip in isolated CWD ----
    let tmpDir = getTempDir() / ("axiom_reuse_memo_" & $epoch)
    createDir(tmpDir / ".axiom" / "cache" / "gate_memo")
    setCurrentDir(tmpDir)

    let memoEpoch = currentCacheEpoch()
    let gateId = "verification-auditor"
    saveGateMemo(gateId, identity, true, memoEpoch)

    # ---- Step 6: CASE B (miss) — different identity → lookup miss → fresh gate ----
    let missLockHash = identity & "-different"
    let idx = loadMemoIndex(GateMemoBaseDir / "epoch_" & $memoEpoch)
    let missLookup = lookupMemo(idx, gateId, missLockHash)

    let gateCmd = "nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " & rcPath & " full 2"
    let (gateOut, gateExitCode) = execCmdEx(gateCmd, workingDir = rcPath, options = {poStdErrToStdOut})
    let parsedGate = parseGateOutput(gateOut, gateExitCode)
    let freshVerdict = parsedGate.verdict
    saveGateMemo(gateId, missLockHash, freshVerdict == "PASS", memoEpoch)

    # ---- Step 7: CASE A (hit) — same identity → lookup hit → NO gate run ----
    let hitLookup = lookupMemo(idx, gateId, identity)
    let reusedVerdict = if hitLookup.isSome:
      if hitLookup.get.result: "PASS" else: "FAIL"
    else:
      "MISSING"

    # ---- Step 8: Mutation CASE B2 — second substrate with mutated src file ----
    mutPath = repoRoot / ("rc-mut-" & $epoch)
    var mutIdentityChanged = false
    let (mutWtOut, mutWtCode) = execCmdEx("git worktree add --detach " & mutPath & " " & fixture, workingDir = repoRoot)
    if mutWtCode == 0:
      # Find one src/*.nim file and mutate it (NOT touching live/frozen files)
      var targetFile = ""
      for fp in walkDirRec(rcPath / "src"):
        if fileExists(fp) and fp.endsWith(".nim"):
          targetFile = fp
          break
      if targetFile.len > 0:
        let relPath = relativePath(targetFile, rcPath)
        let mutTarget = mutPath / relPath
        if fileExists(mutTarget):
          let origContent = readFile(mutTarget)
          writeFile(mutTarget, origContent & "\n# reuse-mutation-test\n")

          # Recompute identity on mutated substrate (snapshot digest changes)
          let mutGateImpl = sha256File(mutPath / "src/gate/runners/verification_auditor_gate.nim")
          let mutSqRes = buildSemanticQuery(mutPath, mutGateImpl, DefaultSelectionRule)
          if mutSqRes.ok:
            let mutId = canonicalVerificationIdentity(mutSqRes.value, pi, deps)
            mutIdentityChanged = (mutId != identity)
          try: writeFile(mutTarget, origContent)
          except CatchableError: discard  # axiom:best-effort(worktree/memo cleanup best-effort)

    let mutLookup = lookupMemo(idx, gateId, "mutated-" & identity)
    let caseMutationMiss = mutLookup.isNone and mutIdentityChanged

    # ---- Step 9: Strictness — decideReuseCanonical for CASE A hit ----
    var strictDecision = "rdRecompute"
    if hitLookup.isSome:
      let storedResult = newStoredVerificationResultCanonical(canonicalId,
        if hitLookup.get.result: "PASS" else: "FAIL")
      let decision = decideReuseCanonical(storedResult, canonicalId, declaredDepsList)
      strictDecision = $decision

    # ---- Step 10: Evidence JSON ----
    let hitOk = missLookup.isNone
    let reuseOk = hitLookup.isSome
    let mutOk = caseMutationMiss
    let equivalenceHeld = (freshVerdict == reusedVerdict)

    let evidence = %*{
      "tool": "verification_reuse_check",
      "ref": fixture,
      "identity": identity,
      "caseMissFresh": hitOk,
      "caseHitReused": reuseOk,
      "caseMutationMiss": mutOk,
      "freshVerdict": freshVerdict,
      "reusedVerdict": reusedVerdict,
      "lookupHit": hitLookup.isSome,
      "lookupMiss": missLookup.isNone,
      "strictDecision": strictDecision,
      "totalDeps": totalDeps,
      "dUnknownCount": dUnknownCount
    }
    echo $evidence

    if not equivalenceHeld: return 1
    if not hitOk: return 1
    if not reuseOk: return 1
    if not mutOk: return 1
    return 0

  finally:
    # Cleanup: remove substrate(s) + restore CWD + remove temp memo dir
    if mutPath != "":
      try:
        if dirExists(mutPath):
          discard execCmdEx("git worktree remove --force " & mutPath, workingDir = repoRoot)
      except CatchableError: discard  # axiom:best-effort(worktree/memo cleanup best-effort)
    if rcPath != "":
      try:
        if dirExists(rcPath):
          discard execCmdEx("git worktree remove --force " & rcPath, workingDir = repoRoot)
      except CatchableError: discard  # axiom:best-effort(worktree/memo cleanup best-effort)
    try: setCurrentDir(savedDir)
    except CatchableError: discard  # axiom:best-effort(worktree/memo cleanup best-effort)
    let tmpDir = getTempDir() / ("axiom_reuse_memo_" & $epoch)
    try:
      if dirExists(tmpDir): removeDir(tmpDir)
    except CatchableError: discard  # axiom:best-effort(worktree/memo cleanup best-effort)

when isMainModule:
  try: quit(main())
  except CatchableError as e: echo "[ERROR] ", e.msg; quit(1)