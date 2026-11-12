## verification_shadow_gate.nim — Standalone shadow verification gate runner.
##
## Probe reuse decision (documented): verification_probe.runProbe*(repoRoot, sha)
## creates its OWN internal worktree (proc signature: runProbe*(repoRoot: string; sha: string))
## and does NOT accept an existing substrate path. Therefore this tool implements
## a minimal strace observation wrapper around the oracle gate invocation instead
## of reusing runProbe. Strace output is parsed directly; observed paths are mapped
## via classifyPath -> probeReadClassToReadClass -> classifyReadClass.
##
## Standalone tool — NOT registered in gates.json / gates.manifest.toml / CI.

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, strutils, json, parseopt, times, algorithm, hashes, re]
import std/[sets, tables, sequtils]

import verification/verification_dependency
import verification/observation_pipeline
import verification/semantic_query_types
import verification/repo_snapshot_digest
import verification/observed_audit_contract
import verification/verification_query_engine
import core/crypto/hash_kernel
from ci/verification_probe import classifyPath, ProbeReadClass

# ---------------------------------------------------------------------------
# Shared category definition with tools/verification_auditor.nim infraModules
# (independent check requires definitional parity; walk/parse implemented separately).
# ---------------------------------------------------------------------------
const
  infraModulesFull* = [
    "os", "posix", "winlean", "asyncdispatch", "asyncfutures",
    "malebolgia", "threadpool", "isolates", "cpuload",
    "net", "rawsockets", "selectors",
    "dynlib", "pcre", "re", "nre",
    "db_sqlite", "db_postgres", "db_mysql", "db_odbc",
    "smtp", "httpclient", "asynchttpserver",
    "streams", "terminal", "rdstdin"
  ]

# ---------------------------------------------------------------------------
# Evidence entry type for dependency resolutions
# ---------------------------------------------------------------------------

type DependencyResolutionEntry* = object
  path*: string
  readClass*: string
  kind*: string
  resolution*: string

# ---------------------------------------------------------------------------
# Exported pure functions
# ---------------------------------------------------------------------------

func verifySubstrateIndependence*(paths: seq[string]; wantSha, wantTree: string): string {.raises: [].} =
  ## Verify substrate independence. Returns "" when valid, or an error string.
  ## Pure func — no I/O; suitable for unit testing without real worktrees.
  if paths.len == 0:
    return "error: empty paths list"
  if wantSha == "" or wantTree == "":
    return "error: wantSha or wantTree is empty"
  if wantSha != wantTree:
    return "error: SHA and tree differ"
  var seen = initHashSet[string]()
  for p in paths:
    if p == "":
      return "error: empty path in list"
    if p == ".":
      return "error: live-root path included"
    if p in seen:
      return "error: duplicate path: " & p
    seen.incl(p)
  ""

func parseGateOutput*(output: string; exitCode: int): tuple[verdict: string; domainCount: int; ok: bool] {.raises: [].} =
  ## Parse verification-auditor-gate output for verdict and domain count.
  ## Cross-checks exitCode (0=PASS,1=FAIL) against output verdict; mismatch -> ok=false (fail-closed).
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

func crossCheckStatus*(actualVerdict, modelVerdict: string): string {.raises: [].} =
  ## Return "MATCH" when both verdicts agree, "MISMATCH" otherwise.
  if actualVerdict == modelVerdict: "MATCH" else: "MISMATCH"

func buildEvidenceJson*(tool, refSha, actualVerdict, modelVerdict, crossCheckStatus, queryId, gateImplIdentity, toolchain, obsStatusStr: string;
                        actualDomainCount, modelDomainCount, baselineDomainCount, oracleWallclockMs, unclassifiedObservations: int;
                        couplingFlags: seq[string];
                        dependencyResolutions: seq[DependencyResolutionEntry]): string {.raises: [].} =
  ## Build machine-readable JSON with RAW evidence only.
  ## Does NOT contain canReuse / evidenceComplete / summary keys.
  var depArr = newJArray()
  for dep in dependencyResolutions:
    depArr.add(%*{"path": dep.path, "readClass": dep.readClass, "kind": dep.kind, "resolution": dep.resolution})
  let j = %*{
    "tool": tool,
    "ref": refSha,
    "actualVerdict": actualVerdict,
    "modelVerdict": modelVerdict,
    "crossCheckStatus": crossCheckStatus,
    "actualDomainCount": actualDomainCount,
    "modelDomainCount": modelDomainCount,
    "baselineDomainCount": baselineDomainCount,
    "queryId": queryId,
    "gateImplIdentity": gateImplIdentity,
    "toolchain": toolchain,
    "couplingFlags": couplingFlags,
    "observationStatus": obsStatusStr,
    "oracleWallclockMs": oracleWallclockMs,
    "dependencyResolutions": depArr,
    "unclassifiedObservations": unclassifiedObservations
  }
  $j

# ---------------------------------------------------------------------------
# Independent domain module counting
# ---------------------------------------------------------------------------

func classifyFileIndependent*(content: string): string {.raises: [RegexError].} =
  ## 3-way classification independent of auditor's auditFile.
  ## Shares category definition with tools/verification_auditor.nim infraModules
  ## (definitional parity; walk/parse implemented separately).
  var codeLines: seq[string] = @[]
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.len > 0 and stripped[0] == '#': continue
    codeLines.add(line)
  let code = codeLines.join("\n")
  if code.find(re(r"\b(proc|func|method|template|macro)\b")) < 0:
    return "exempt"
  if code.find(re(r"\bimport\s+.*?\b(" & infraModulesFull.join("|") & r")\b")) >= 0:
    return "infrastructure"
  return "domain"

proc countDomainModulesIndependent*(repoRoot: string): tuple[count: int; ok: bool] {.raises: [OSError, IOError, CatchableError].} =
  ## Count domain modules independently using git ls-files + 3-way classification.
  ## Runs git ls-files with NO pathspec to avoid shell-glob bug.
  var domainCount = 0
  let (lsOut, lsCode) = execCmdEx("git ls-files", workingDir = repoRoot)
  if lsCode != 0:
    return (0, false)
  for line in lsOut.splitLines():
    let path = line.strip()
    if path.len == 0: continue
    if not (path.startsWith("src/") and path.endsWith(".nim")): continue
    let fullPath = repoRoot / path
    if not fileExists(fullPath): continue
    try:
      let content = readFile(fullPath)
      let cat = classifyFileIndependent(content)
      if cat == "domain":
        inc domainCount
    except CatchableError:
      discard  # axiom:best-effort(reconstruction read best-effort - verdict unaffected)
  (domainCount, true)

# ---------------------------------------------------------------------------
# Strace observation helper
# ---------------------------------------------------------------------------

func parseStraceLine*(line: string): tuple[path: string; found: bool] {.raises: [].} =
  ## Parse ONE strace -f line into the first quoted file path.
  ## strace -f prefixes every line with a PID (e.g. "152368 openat(AT_FDCWD,
  ## \"/path\", ...)") — match the syscall name ANYWHERE and extract the first
  ## quoted string AFTER the opening parenthesis. Pure func (unit-tested).
  result = ("", false)
  let s = line.strip()
  if s.len == 0: return
  let openParen = s.find('(')
  if openParen < 0: return
  let syscallName = s[0 ..< openParen]
  if not (syscallName.endsWith("openat") or syscallName.endsWith("stat") or
          syscallName.endsWith("access") or syscallName.endsWith("readlink")):
    return
  let firstQuote = s.find('"', openParen)
  if firstQuote < 0: return
  let secondQuote = s.find('"', firstQuote + 1)
  if secondQuote < 0: return
  let path = s.substr(firstQuote + 1, secondQuote - 1)
  if path.len > 0:
    result = (path, true)

proc observeOracleGate*(wtPath: string; straceTmpFile: string): tuple[entries: seq[DependencyResolutionEntry]; unclassifiedCount: int] {.raises: [CatchableError].} =
  ## Run the oracle gate invocation under strace -e trace=file and map observed
  ## paths through classifyPath -> probeReadClassToReadClass -> classifyReadClass
  ## into ValidatedDependencies. Returns dependency entries and unclassified count.
  let straceCmd = "strace -e trace=file -f -o " & straceTmpFile & " -- nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " & wtPath & " full 2"
  let (_, straceCode) = execCmdEx(straceCmd, workingDir = wtPath)
  discard straceCode
  var entries: seq[DependencyResolutionEntry] = @[]
  var unclassifiedCount = 0
  if not fileExists(straceTmpFile):
    return (entries, unclassifiedCount)
  for line in readFile(straceTmpFile).splitLines():
    let (path, found) = parseStraceLine(line)
    if not found: continue
    let prc = classifyPath(path)
    let rc = probeReadClassToReadClass(prc)
    let raw = newRawObservation(path, rc, "")
    let cls = classify(raw)
    let val = validate(cls)
    let res = resolve(val)
    entries.add(DependencyResolutionEntry(
      path: val.depPath,
      readClass: $val.depReadClass,
      kind: $val.depKind,
      resolution: $res
    ))
    if val.depKind == dkUnclassified:
      inc unclassifiedCount
  (entries, unclassifiedCount)

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
      # NOTE: parseopt stores cmdArgument text in p.key, NOT p.val (p.val is
      # only for option values). Using p.val here yields an empty repoRoot.
      if repoRoot == "": repoRoot = p.key
      elif refSha == "": refSha = p.key
      else: echo "Unexpected argument: " & p.key
    of cmdShortOption, cmdLongOption:
      case p.key
      of "help", "h": echo "Usage: verification_shadow_gate <repoRoot> [--ref <sha>]"; quit(0)
      of "ref": refSha = p.val
      else: discard

  if repoRoot == "":
    echo "Error: repoRoot is required."
    quit(1)
  if not dirExists(repoRoot):
    echo "Error: repoRoot does not exist: " & repoRoot
    quit(1)

  # Resolve fixture SHA
  if refSha == "":
    let (headOut, headCode) = execCmdEx("git rev-parse HEAD", workingDir = repoRoot)
    if headCode != 0:
      echo "Error: cannot resolve HEAD SHA"
      quit(1)
    refSha = headOut.strip()

  # Pre-flight: create TWO independent detached worktrees at the same fixture SHA
  let epoch = $epochTime()
  let oracleWtPath = repoRoot / ("sg-oracle-" & epoch)
  let modelWtPath = repoRoot / ("sg-model-" & epoch)

  # Create oracle worktree
  let (oracleWtOut, oracleWtCode) = execCmdEx("git worktree add --detach " & oracleWtPath & " " & refSha, workingDir = repoRoot)
  if oracleWtCode != 0:
    echo "Error: failed to create oracle worktree: " & oracleWtOut
    quit(1)

  # Create model worktree
  let (modelWtOut, modelWtCode) = execCmdEx("git worktree add --detach " & modelWtPath & " " & refSha, workingDir = repoRoot)
  if modelWtCode != 0:
    echo "Error: failed to create model worktree: " & modelWtOut
    try: discard execCmdEx("git worktree remove --force " & oracleWtPath, workingDir = repoRoot)
    except CatchableError: discard  # axiom:best-effort(cleanup/observation best-effort - must not affect shadow verdict)
    quit(1)

  var straceTmpFile = ""
  try:
    # ---- Pre-flight verification ----
    let indepErr = verifySubstrateIndependence(@[oracleWtPath, modelWtPath], refSha, refSha)
    if indepErr != "":
      echo "Error: substrate independence check failed: " & indepErr
      return 1

    # Verify each worktree HEAD == fixture SHA
    for wtPath in @[oracleWtPath, modelWtPath]:
      let (headOut, headCode) = execCmdEx("git rev-parse HEAD", workingDir = wtPath)
      if headCode != 0 or headOut.strip() != refSha:
        echo "Error: worktree HEAD mismatch at " & wtPath
        return 1

    # Verify fixture commit tree matches for both worktrees
    let (treeOutO, treeCodeO) = execCmdEx("git rev-parse " & refSha & "^{tree}", workingDir = oracleWtPath)
    let (treeOutM, treeCodeM) = execCmdEx("git rev-parse " & refSha & "^{tree}", workingDir = modelWtPath)
    if treeCodeO != 0 or treeCodeM != 0 or treeOutO.strip() != treeOutM.strip():
      echo "Error: fixture commit tree mismatch between worktrees"
      return 1

    # Verify wtPaths distinct from each other AND from repoRoot
    if oracleWtPath == modelWtPath or oracleWtPath == repoRoot or modelWtPath == repoRoot:
      echo "Error: worktree paths not distinct from each other or repoRoot"
      return 1

    # ---- Oracle side ----
    putEnv("AXIOM_CI", "1")
    putEnv("AXIOM_CI_PRESERVE_CACHE", "1")

    # Baseline self-feed: hash BEFORE the run
    let baselinePath = oracleWtPath / "data" / "verification_auditor_baseline.json"
    var baselineHashBefore = ""
    var baselineExistedBefore = fileExists(baselinePath)
    if baselineExistedBefore:
      try: baselineHashBefore = sha256Hex(readFile(baselinePath))
      except CatchableError: discard  # axiom:best-effort(cleanup/observation best-effort - must not affect shadow verdict)

    let gateCmd = "nim c --hints:off -r src/gate/runners/verification_auditor_gate.nim " & oracleWtPath & " full 2"
    let t0 = epochTime()
    let (oracleOut, oracleExitCode) = execCmdEx(gateCmd, workingDir = oracleWtPath, options = {poStdErrToStdOut})
    let oracleWallclockMs = int((epochTime() - t0) * 1000)

    # Parse oracle output
    let parsed = parseGateOutput(oracleOut, oracleExitCode)
    let actualVerdict = parsed.verdict
    let actualDomainCount = parsed.domainCount

    # Baseline self-feed: hash AFTER the run
    var couplingFlags: seq[string] = @[]
    var obsStatus = osComplete
    if baselineExistedBefore:
      try:
        let baselineHashAfter = sha256Hex(readFile(baselinePath))
        if baselineHashAfter != baselineHashBefore:
          couplingFlags.add("selfCalibration")
          obsStatus = osUnknown
      except CatchableError: discard  # axiom:best-effort(cleanup/observation best-effort - must not affect shadow verdict)
    elif fileExists(baselinePath):
      couplingFlags.add("selfCalibration")
      obsStatus = osUnknown

    # Exit-code / output-verb cross-check
    if not parsed.ok:
      couplingFlags.add("exitCodeMismatch")
      if obsStatus == osComplete:
        obsStatus = osUnknown

    # ---- Model side ----
    let subjectSnapshot = computeSubjectSnapshot(modelWtPath)
    let baselineDigest = readBaseline(modelWtPath)
    let policyDigest = readPolicy(modelWtPath)

    # Gate implementation digest (first caller of computeGateImplementationDigest)
    let binaryPath = modelWtPath / "bin" / "verification_auditor"
    var gateImplDigest = computeGateImplementationDigest(binaryPath)
    if gateImplDigest == newGateImplDigest(hash_kernel.sha256Hex("")):
      # Binary absent — fall back to sha256 of the gate source
      let gateSource = modelWtPath / "src/gate/runners/verification_auditor_gate.nim"
      if fileExists(gateSource):
        gateImplDigest = newGateImplDigest(hash_kernel.sha256Hex(readFile(gateSource)))
      else:
        gateImplDigest = newGateImplDigest(hash_kernel.sha256Hex(""))

    let gateImplIdentity = $gateImplDigest & "|nim:" & NimVersion

    # Independent domain count
    let (modelDomainCount, countOk) = countDomainModulesIndependent(modelWtPath)
    if not countOk:
      echo "Error: failed to count domain modules independently"
      return 1

    # Read baseline domain count for model verdict
    var baselineDomainCount = 0
    var baselineFound = false
    if fileExists(baselinePath):
      try:
        let bj = parseJson(readFile(baselinePath))
        if bj.hasKey("domain_count"):
          baselineDomainCount = bj["domain_count"].getInt()
          baselineFound = true
      except CatchableError: discard  # axiom:best-effort(cleanup/observation best-effort - must not affect shadow verdict)
    if not baselineFound:
      obsStatus = osUnknown

    let modelResult = buildObservedAuditResult(modelDomainCount, baselineDomainCount, couplingFlags, obsStatus)
    let modelResolution = resolve(modelResult)
    let modelVerdict = modelResult.verdict

    # Build semantic query
    let gateImplIdentityString = $gateImplDigest & "|nim:" & NimVersion
    let queryRes = buildSemanticQuery(modelWtPath, gateImplIdentityString, DefaultSelectionRule)
    if not queryRes.ok:
      echo "Error: failed to build semantic query: " & queryRes.err
      return 1
    let queryId = $(provisionalQueryID(queryRes.value))

    # ---- Observation (strace) ----
    straceTmpFile = repoRoot / ("sg_strace_" & epoch & ".log")
    let (depEntries, unclassifiedCount) = observeOracleGate(oracleWtPath, straceTmpFile)

    # Fail-closed observation accounting:
    #  - any dkUnclassified read -> osUnclassified (must not be ignored)
    #  - ZERO observations at all -> observation failure (broken/absent strace
    #    must NOT silently pass as an empty success — theater risk)
    if unclassifiedCount > 0:
      obsStatus = osUnclassified
    elif depEntries.len == 0:
      couplingFlags.add("observationFailure")
      obsStatus = osUnknown

    # ---- Cross-check + output ----
    let ccStatus = crossCheckStatus(actualVerdict, modelVerdict)

    # Build evidence JSON
    let toolchain = $NimVersion
    let obsStatusStr = $(obsStatus)
    let evidenceJson = buildEvidenceJson(
      "verification_shadow_gate", refSha, actualVerdict, modelVerdict, ccStatus,
      queryId, gateImplIdentity, toolchain,
      obsStatusStr, actualDomainCount, modelDomainCount, baselineDomainCount,
      oracleWallclockMs, unclassifiedCount,
      couplingFlags,
      depEntries
    )
    echo actualVerdict & " | " & modelVerdict & " | " & ccStatus
    echo evidenceJson

    # ---- Exit logic ----
    var shouldQuit = false
    var quitCode = 0
    if ccStatus != "MATCH":
      shouldQuit = true; quitCode = 1
    elif obsStatus != osComplete:
      shouldQuit = true; quitCode = 1
    elif unclassifiedCount > 0:
      shouldQuit = true; quitCode = 1
    elif not parsed.ok:
      shouldQuit = true; quitCode = 1
    elif oracleExitCode != 0:
      shouldQuit = true; quitCode = 1
    if shouldQuit:
      echo "Cross-check FAILED — reuse prohibited."
      return 1
    return 0

  finally:
    # Cleanup: remove both worktrees + strace temp file.
    # NOTE: must NOT use quit() inside this try — quit() skips finally in Nim.
    # All in-try exits are `return`, which ALWAYS runs finally.
    try: discard execCmdEx("git worktree remove --force " & oracleWtPath, workingDir = repoRoot)
    except CatchableError: discard  # axiom:best-effort(cleanup/observation best-effort - must not affect shadow verdict)
    try: discard execCmdEx("git worktree remove --force " & modelWtPath, workingDir = repoRoot)
    except CatchableError: discard  # axiom:best-effort(cleanup/observation best-effort - must not affect shadow verdict)
    if straceTmpFile != "" and fileExists(straceTmpFile):
      try: removeFile(straceTmpFile)
      except CatchableError: discard  # axiom:best-effort(cleanup/observation best-effort - must not affect shadow verdict)

when isMainModule:
  try:
    quit(main())
  except CatchableError as e: echo "[ERROR] ", e.msg; quit(1)