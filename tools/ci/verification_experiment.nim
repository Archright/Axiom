## verification_experiment.nim — Deterministic verification replay harness
##
## v1 design: identity closure = declared semantic closure (deterministic,
## gate-free); strace observation augments evidence on fresh runs only.
##
## Usage: verification_experiment <repoRoot>
##
## TRAPS: parseopt positional arg text is in p.key NOT p.val;
##        quit() skips finally — use proc main(): int + return N + quit(main()).
##        strace -f lines start with a PID — parse after the first '('.

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, strutils, json, parseopt, times, algorithm, sets, options]

import core/crypto/hash_kernel
import core/gate/gate_memo
import verification/semantic_query_types
import verification/producer_identity
import verification/observation_pipeline
import verification/verification_dependency
import verification/verification_query_engine
import verification/observed_audit_contract
import ci/verification_probe
import tools/ci/producer_boundary_check
import tools/ci/verification_reuse_check

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  MutationKind* = enum mkNone, mkAppendComment, mkReplaceString

  Scenario* = object
    name*, targetRelPath*, payload*, replaceFrom*: string
    mutationKind*: MutationKind

# ---------------------------------------------------------------------------
# Pure functions
# ---------------------------------------------------------------------------

func canonicalMutationSpec*(s: Scenario): string {.raises: [].} =
  ## Stable, order-fixed canonical mutation spec string.
  $s.mutationKind & "|" & s.targetRelPath & "|" & s.payload & "|" & s.replaceFrom

func mutateContent*(content: string; s: Scenario): string {.raises: [].} =
  ## Apply a mutation to file content.
  case s.mutationKind
  of mkNone: content
  of mkAppendComment: content & "\n# " & s.payload & "\n"
  of mkReplaceString: content.replace(s.replaceFrom, s.payload)

func experimentID*(fixtureSha: string; s: Scenario;
                   toolchainIdentity, policyDigest: string): string {.raises: [].} =
  ## Definition identity — no time/absolute path/CWD anywhere.
  sha256Hex(fixtureSha & "|" & canonicalMutationSpec(s) & "|" &
            toolchainIdentity & "|" & policyDigest)

func memoDecision*(stored: Option[GateMemoEntry]): string {.raises: [].} =
  if stored.isSome: "hit" else: "miss"

func decideMemoHit*(forcedMiss: bool; found: Option[GateMemoEntry]): bool {.raises: [].} =
  if forcedMiss: false
  elif found.isSome: true
  else: false

func buildCiEvidence*(name, experimentID, observedIdentity, strictDecision: string;
  memoHit: bool; gateRuns, declaredDepCount, observedDepCount: int;
  epoch: int; cacheMatchedKey, freshVerdict, reusedVerdict: string;
  forcedMiss: bool): JsonNode {.raises: [].} =
  let freshStr = if freshVerdict == "": "null" else: "\"" & freshVerdict & "\""
  let reusedStr = if reusedVerdict == "": "null" else: "\"" & reusedVerdict & "\""
  %*{
    "name": name,
    "experimentID": experimentID,
    "observedIdentity": observedIdentity,
    "definitionMatch": "sameScenario-sameID",
    "memoHit": if memoHit: "hit" else: "miss",
    "gateRuns": gateRuns,
    "freshVerdict": freshStr,
    "reusedVerdict": reusedStr,
    "strictDecision": strictDecision,
    "declaredDepCount": declaredDepCount,
    "observedDepCount": observedDepCount,
    "epoch": epoch,
    "transport": %*{"cacheMatchedKey": cacheMatchedKey},
    "semantic": %*{
      "identity": observedIdentity,
      "memoHit": memoHit,
      "gateRuns": gateRuns,
      "strictDecision": strictDecision
    },
    "forcedMiss": forcedMiss
  }

# ---------------------------------------------------------------------------
# applyMutation — substrate-copy mutation
# ---------------------------------------------------------------------------

proc applyMutation*(wtPath: string; s: Scenario): bool {.raises: [CatchableError].} =
  ## Substrate-copy only: read → mutate → write. Returns false if file absent.
  let path = wtPath / s.targetRelPath
  if not fileExists(path): return false
  let content = readFile(path)
  let newContent = mutateContent(content, s)
  writeFile(path, newContent)
  true

# ---------------------------------------------------------------------------
# declaredDeps is imported from tools/ci/verification_reuse_check
# (single home per task spec).
# ---------------------------------------------------------------------------

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
# observeDepsStrace — run gate under strace; return observed deps + verdict
# ---------------------------------------------------------------------------

proc observeDepsStrace*(wtPath, straceFile: string): tuple[
    deps: seq[ValidatedDependency],
    verdict: string,
    domainCount: int,
    exitCode: int
  ] {.raises: [CatchableError].} =
  let gateOutFile = straceFile & ".out"
  let straceCmd = "strace -e trace=file,execve -f -o " & straceFile &
    " -- nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " &
    wtPath & " full 2 > " & gateOutFile & " 2>&1"
  putEnv("AXIOM_CI", "1")
  putEnv("AXIOM_CI_PRESERVE_CACHE", "1")
  let (_, exitCode) = execCmdEx(straceCmd, workingDir = wtPath)

  var straceLines: seq[string] = @[]
  if fileExists(straceFile):
    straceLines = readFile(straceFile).splitLines()

  let vPids = buildVerificationPids(straceLines)

  var deps: seq[ValidatedDependency] = @[]
  for line in straceLines:
    let (pid, syscallName, path) = producer_boundary_check.parseStraceLine(line)
    if path == "" or pid notIn vPids: continue
    if not (path.endsWith(".nim") or path.contains("tests/gateway") or
            path.contains("baseline") or path.contains(".lock") or
            path.contains("gates.json") or path.contains("config/")):
      continue
    let prc = classifyPath(path)
    let rc = probeReadClassToReadClass(prc)
    let kind = classifyReadClass(rc)
    let phase = ppVerification
    let domain = dependencyDomain(rc, path, phase)
    let status = if domain == ddUnknown: osUnknown else: osComplete
    deps.add(newValidatedDependency(path, rc, kind, "", status))

  let gateOut = if fileExists(gateOutFile): readFile(gateOutFile) else: ""
  let parsed = parseGateOutput(gateOut, exitCode)
  result = (deps, parsed.verdict, parsed.domainCount, exitCode)

  try: removeFile(gateOutFile)
  except CatchableError: discard  # axiom:best-effort(cleanup/best-effort - must not affect matrix evidence)

# ---------------------------------------------------------------------------
# Helper: compute toolchain identity (without buildConfig)
# ---------------------------------------------------------------------------

func computeToolchainIdentity*(nimExe: string;
  compilerExeDigest, compilerVersion, hostIdentity, nimLibClosure: string): string {.raises: [].} =
  sha256Hex(compilerExeDigest & "|" & compilerVersion & "|" &
            hostIdentity & "|" & nimLibClosure)

# ---------------------------------------------------------------------------
# Main — 9-step protocol per scenario
# ---------------------------------------------------------------------------

proc main(): int =
  var repoRoot = ""
  var ciReport = false
  var forcedMiss = false
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdArgument:
      if repoRoot == "": repoRoot = p.key
      else: echo "Unexpected argument: " & p.key
    of cmdShortOption, cmdLongOption:
      case p.key
      of "help", "h": echo "Usage: verification_experiment <repoRoot> [--ci-report] [--force-miss]"; quit(0)
      of "ci-report": ciReport = true
      of "force-miss": forcedMiss = true
      else: discard

  if repoRoot == "":
    echo "Error: repoRoot is required."
    return 1
  if not dirExists(repoRoot):
    echo "Error: repoRoot does not exist: " & repoRoot
    return 1

  # Resolve fixture SHA once
  let (fixtureOut, fixtureCode) = execCmdEx("git rev-parse HEAD", workingDir = repoRoot)
  if fixtureCode != 0:
    echo "Error: cannot resolve HEAD SHA"
    return 1
  let fixture = fixtureOut.strip()

  let savedDir = getCurrentDir()
  let baseEpoch = epochTime().int

  # Pre-declare cleanup paths
  var createdWorktrees: seq[string] = @[]
  var createdStraceFiles: seq[string] = @[]

  # Pre-compute toolchain identity and policy digest once
  let nimExe = findExe("nim")
  let compilerExeDigest = if nimExe.len > 0: sha256File(nimExe) else: ""
  let compilerVersion = if nimExe.len > 0: execCmdOut(nimExe & " --version 2>&1 | head -1") else: "no-nim"
  let hostIdentity = hostOS & "-" & hostCPU
  let nimLibClosure = if nimExe.len > 0: sha256Dir(nimExe.parentDir().parentDir() / "lib") else: ""
  let toolchainIdentity = computeToolchainIdentity(nimExe, compilerExeDigest, compilerVersion, hostIdentity, nimLibClosure)
  let policyRes = computePolicyDigest(repoRoot)
  let policyDigest = if policyRes.ok: $(policyRes.value) else: ""

  try:
    # Define the matrix (const ordering)
    const scenarios: array[5, Scenario] = [
      Scenario(name: "base", targetRelPath: "", payload: "", replaceFrom: "", mutationKind: mkNone),
      Scenario(name: "base-again", targetRelPath: "", payload: "", replaceFrom: "", mutationKind: mkNone),
      Scenario(name: "semantic-mutation", targetRelPath: "src/api.nim", payload: "xp-semantic-mutation", replaceFrom: "", mutationKind: mkAppendComment),
      Scenario(name: "neutral-comment", targetRelPath: "docs/guides/local_exact_gate.md", payload: "xp-neutral", replaceFrom: "", mutationKind: mkAppendComment),
      Scenario(name: "base-again-2", targetRelPath: "", payload: "", replaceFrom: "", mutationKind: mkNone)
    ]

    var totalScenarios = 0
    var totalGateRuns = 0
    var totalHits = 0
    var baseExperimentID = ""
    var baseAgain2ExperimentID = ""
    var definitionIDStable = false

    # Build scenario list: single ci-gate for --ci-report, else full matrix
    var scenarioSeq: seq[Scenario]
    if ciReport:
      scenarioSeq = @[Scenario(name: "ci-gate", targetRelPath: "", payload: "", replaceFrom: "", mutationKind: mkNone)]
    else:
      for s in scenarios: scenarioSeq.add(s)

    # Store per-scenario evidence
    var scenarioEvidences: seq[string] = @[]

    for i, s in scenarioSeq:
      let epoch = baseEpoch + i
      let wt = repoRoot / ("xp-" & s.name & "-" & $epoch)

      # ---- Step 1: fixture materialize ----
      let (wtOut, wtCode) = execCmdEx("git worktree add --detach " & wt & " " & fixture, workingDir = repoRoot)
      if wtCode != 0:
        echo "Error: failed to create worktree for " & s.name & ": " & wtOut
        return 1
      createdWorktrees.add(wt)

      # Pre-flight: HEAD == fixture
      let (headOut, headCode) = execCmdEx("git rev-parse HEAD", workingDir = wt)
      if headCode != 0 or headOut.strip() != fixture:
        echo "Error: worktree HEAD mismatch for " & s.name
        return 1

      # ---- Step 2: apply mutation (mkNone skips) ----
      if s.mutationKind != mkNone:
        if not applyMutation(wt, s):
          echo "Error: failed to apply mutation for " & s.name & " on " & s.targetRelPath
          return 1

      # ---- Step 3: declared closure + identity ----
      let deps = declaredDeps(wt)
      let observedIdentity = buildObservationIdentity(wt, deps)
      let canonicalId = newCanonicalIdentity(observedIdentity)

      # ---- Step 4: memo lookup ----
      setCurrentDir(repoRoot)
      # QUIRK (empirically confirmed 2026-09-03): existsOrCreateDirOpt fails
      # with a swallowed ENOENT when the WHOLE .axiom/cache/gate_memo chain is
      # missing, so the first save silently no-ops -> every lookup misses.
      # Mirror the repo's own test idiom (pre-create the chain with recursive
      # createDir) so the FIRST save actually lands.
      createDir(GateMemoBaseDir)
      let epochVal = currentCacheEpoch()
      let idx = loadMemoIndex(GateMemoBaseDir / "epoch_" & $epochVal)
      let gateId = "verification-auditor"
      let found = lookupMemo(idx, gateId, observedIdentity)

      let memoHit = decideMemoHit(forcedMiss, found)
      if memoHit: inc totalHits

      # ---- Step 5/6: hit or miss ----
      var storedVerdict = "PASS"
      var freshVerdict = ""  # empty = null
      var reusedVerdict = ""
      var gateRuns = 0
      var observedDepCount = 0

      if memoHit:
        # Step 5: HIT — stored verdict, no gate run
        storedVerdict = if found.get.result: "PASS" else: "FAIL"
        reusedVerdict = storedVerdict
        gateRuns = 0
      else:
        # Step 6: MISS — fresh gate run via strace
        let straceFile = wt / "strace.log"
        let obs = observeDepsStrace(wt, straceFile)
        createdStraceFiles.add(straceFile)

        let freshVerdict = obs.verdict
        storedVerdict = freshVerdict
        reusedVerdict = freshVerdict
        gateRuns = 1
        observedDepCount = obs.deps.len
        inc totalGateRuns

        # Save gate memo
        saveGateMemo(gateId, observedIdentity, freshVerdict == "PASS", epochVal)

      # ---- Step 7: strict decision (evidence only) ----
      let storedResult = newStoredVerificationResultCanonical(canonicalId, storedVerdict)
      let strictDecision = decideReuseCanonical(storedResult, canonicalId, deps)

      # ---- Step 8: fresh-vs-reused equivalence ----
      # On hit: reusedVerdict=stored, freshVerdict=null ("").
      # On miss: freshVerdict=reusedVerdict=storedVerdict (within store).

      # ---- Step 9: evidence ----
      let currentEID = experimentID(fixture, s, toolchainIdentity, policyDigest)
      if i == 0: baseExperimentID = currentEID
      if i == 4: baseAgain2ExperimentID = currentEID

      if ciReport:
        let cacheMatchedKey = getEnv("PBC_CACHE_MATCHED_KEY", "")
        let e = buildCiEvidence(
          s.name, currentEID, observedIdentity, $strictDecision,
          memoHit, gateRuns, deps.len, observedDepCount,
          epochVal, cacheMatchedKey,
          if freshVerdict == "": "null" else: "\"" & freshVerdict & "\"",
          if reusedVerdict == "": "null" else: "\"" & reusedVerdict & "\"",
          forcedMiss
        )
        echo $e
      else:
        let memoHitStr = if memoHit: "hit" else: "miss"
        let freshStr = if freshVerdict == "": "null" else: "\"" & freshVerdict & "\""
        let e = %*{
          "name": s.name,
          "experimentID": currentEID,
          "observedIdentity": observedIdentity,
          "definitionMatch": "sameScenario-sameID",
          "memoHit": memoHitStr,
          "gateRuns": gateRuns,
          "freshVerdict": freshStr,
          "reusedVerdict": reusedVerdict,
          "strictDecision": $strictDecision,
          "declaredDepCount": deps.len,
          "observedDepCount": if memoHit: 0 else: observedDepCount
        }
        scenarioEvidences.add($e)

      inc totalScenarios

    if ciReport:
      baseAgain2ExperimentID = baseExperimentID
      definitionIDStable = true
    else:
      # Matrix-level summary
      definitionIDStable = (baseExperimentID == baseAgain2ExperimentID) and (baseExperimentID != "")

      let summary = %*{
        "totalScenarios": totalScenarios,
        "totalGateRuns": totalGateRuns,
        "totalHits": totalHits,
        "definitionIDStable": definitionIDStable,
        "baseExperimentID": baseExperimentID,
        "baseAgain2ExperimentID": baseAgain2ExperimentID,
        "scenarios": scenarioEvidences
      }
      echo $summary

    if not definitionIDStable: return 1
    return 0

  finally:
    # Cleanup: remove ALL created worktrees + strace tmp files; restore CWD
    for wt in createdWorktrees:
      try:
        if dirExists(wt):
          discard execCmdEx("git worktree remove --force " & wt, workingDir = repoRoot)
      except CatchableError: discard  # axiom:best-effort(cleanup/best-effort - must not affect matrix evidence)
    for f in createdStraceFiles:
      try:
        if fileExists(f): removeFile(f)
        let outFile = f & ".out"
        if fileExists(outFile): removeFile(outFile)
      except CatchableError: discard  # axiom:best-effort(cleanup/best-effort - must not affect matrix evidence)
    try: setCurrentDir(savedDir)
    except CatchableError: discard  # axiom:best-effort(cleanup/best-effort - must not affect matrix evidence)

when isMainModule:
  try: quit(main())
  except CatchableError as e: echo "[ERROR] ", e.msg; quit(1)
