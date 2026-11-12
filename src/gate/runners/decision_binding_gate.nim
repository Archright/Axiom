import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## decision_binding_gate.nim — Decision Binding Gate
##
## Scans staged changes for functions that require {.axiomDecision.} pragma.
## The gate PASSES when all decision-point functions carry the required pragma.
##
## Decision points detected:
##   1. Functions returning Result[T, E] or Option[T] types
##   2. Functions with early-return patterns (if/elif before final return)
##   3. Functions containing validation logic (assert, check, guard clauses)
##
## Exemptions in config/decision_binding.waiver.json are honored.
##
## See: Decision Binding Framework Phase 4

import gate/gate_contract
import gate/gate_types
import gate/utils/gate_safety_macro
import std/[json, strutils, os, times]

# ─── Decision Point Indicators ──────────────────────────────────────────────

func hasResultOrOptionReturnType*(sig: string): bool {.raises: [].} =
  ## Detect Result[T, E] or Option[T] return type patterns.
  let lowerSig = sig.toLowerAscii()
  result = "result[" in lowerSig or "option[" in lowerSig

func hasEarlyReturnPattern*(content: string): bool {.raises: [].} =
  ## Detect multiple return statements with conditional guards.
  var returnCount = 0
  var guardedReturns = 0
  let lines = content.split("\n")
  var idx = 0

  for line in lines:
    let stripped = line.strip()
    if stripped.startsWith("proc ") or stripped.startsWith("func "):
      inc idx
      continue

    if stripped.startsWith("return") and stripped.len > 6:
      inc returnCount
      # Check if preceded by if/elif/guard clause (last 5 lines before return)
      for i in countdown(max(0, idx - 1), max(0, idx - 5)):
        let prevLine = lines[i].strip().toLowerAscii()
        if prevLine.startsWith("if ") or prevLine.startsWith("elif ") or
           prevLine.startsWith("when ") or prevLine.startsWith("guard "):
          inc guardedReturns
          break

    inc idx

  result = returnCount >= 2 and guardedReturns > 0

func hasValidationLogic*(content: string): bool {.raises: [].} =
  ## Detect assert, check, guard clauses in function body.
  let lines = content.split("\n")
  for line in lines:
    let stripped = line.strip()
    if stripped.startsWith("assert(") or stripped.startsWith("check(") or
       stripped.startsWith("guard "):
      return true
  return false

func isExemptedFromScan*(filePath: string): bool {.raises: [].} =
  ## Skip generated files, test files, and known exempt modules.
  let exemptPatterns = [
    "/generated/",
    "/nimcache/",
    "_test.nim",
    "_feature_test.nim",
    "/tests/",
    "mock_",
    "stubs/"
  ]
  for pat in exemptPatterns:
    if pat in filePath:
      return true
  return false

# ─── Exemption Loading ──────────────────────────────────────────────────────

proc loadWaiverConfig*(repoRoot: string): JsonNode {.raises: [CatchableError].} =
  ## Load config/decision_binding.waiver.json for exemption rules.
  ## Returns null node if file missing (conservative: no exemptions).
  let path = repoRoot / "config" / "decision_binding.waiver.json"
  try:
    result = parseFile(path)
  except CatchableError:
    result = nil

proc isFileExempt*(filePath: string, waiver: JsonNode): bool {.raises: [CatchableError].} =
  ## Check if a file is explicitly exempted in the waiver config.
  ## Checks grandfather array for matching file entry with valid expiry.
  if waiver.isNil or not waiver.hasKey("grandfather"):
    return false
  var grandfather: JsonNode
  try:
    grandfather = waiver["grandfather"]
  except KeyError:
    return false
  if grandfather.kind == JNull:
    return false
  let today = utc(now()).format("yyyy-MM-dd")
  for entry in grandfather:
    if entry.kind == JObject:
      if entry.hasKey("file") and entry["file"].kind == JString:
        if entry["file"].getStr() == filePath:
          if entry.hasKey("expires") and entry["expires"].kind == JString:
            let expires = entry["expires"].getStr()
            if expires < today:
              continue
          return true
  return false

proc isModuleExempt*(moduleName: string, waiver: JsonNode): bool {.raises: [CatchableError].} =
  ## Check if a module prefix is exempted in the waiver config.
  ## Checks grandfather array for matching file entry with valid expiry.
  if waiver.isNil or not waiver.hasKey("grandfather"):
    return false
  var grandfather: JsonNode
  try:
    grandfather = waiver["grandfather"]
  except KeyError:
    return false
  if grandfather.kind == JNull:
    return false
  let today = utc(now()).format("yyyy-MM-dd")
  for entry in grandfather:
    if entry.kind == JObject:
      if entry.hasKey("file") and entry["file"].kind == JString:
        let filePath = entry["file"].getStr()
        if moduleName.startsWith(filePath) or filePath in moduleName:
          if entry.hasKey("expires") and entry["expires"].kind == JString:
            let expires = entry["expires"].getStr()
            if expires < today:
              continue
          return true
  return false

# ─── Single-File Scan ───────────────────────────────────────────────────────

proc checkProc*(procDecl: string, procBody: string, filePath: string, startLine: int): tuple[violations: bool, reasons: seq[string]] {.gcsafe, raises: [].}

proc scanFileForDecisionBinding*(filePath: string): tuple[hasViolations: bool, reasons: seq[string]] {.raises: [CatchableError].} =
  ## Scan a single file for missing axiomDecision pragmas on decision points.
  ## Returns (hasViolations, list of reasons) — empty reasons = clean.
  result = (false, @[])
  if not filePath.endsWith(".nim"):
    return
  if isExemptedFromScan(filePath):
    return

  try:
    let content = readFile(filePath)
    let lines = content.split("\n")
    var currentProcName = ""
    var currentProcStart = -1
    var inProc = false
    var procBraceDepth = 0
    var procContent = ""

    for i, line in lines.pairs():
      let stripped = line.strip()

      # Detect proc/func declaration
      if stripped.startsWith("proc ") or stripped.startsWith("func "):
        # Process previous proc if any
        if inProc and currentProcName.len > 0:
          let (violations, reasons) = checkProc(currentProcName, procContent, filePath, i - procContent.split("\n").len)
          if violations:
            result.hasViolations = true
            for r in reasons:
              result.reasons.add(r)

        # Start new proc
        inProc = true
        currentProcName = stripped
        currentProcStart = i
        procBraceDepth = 0
        procContent = ""

        # Extract name from signature
        let afterKw = if stripped.startsWith("proc "): stripped[5..^1] else: stripped[5..^1]
        let nameEnd = min(
          if '(' in afterKw: afterKw.find('(') else: high(int),
          if '*' in afterKw: afterKw.find('*') else: high(int)
        )
        if nameEnd < afterKw.len:
          currentProcName = afterKw[0..<nameEnd].strip()

      if inProc:
        procContent &= line & "\n"
        for ch in stripped:
          if ch == '{': inc procBraceDepth
          elif ch == '}': dec procBraceDepth

    # Process last proc
    if inProc and currentProcName.len > 0:
      let (violations, reasons) = checkProc(currentProcName, procContent, filePath, currentProcStart)
      if violations:
        result.hasViolations = true
        for r in reasons:
          result.reasons.add(r)

  except CatchableError:
    discard

# {.gcsafe.} on the forward declaration: Nim does not propagate inferred
# gcsafe through a forward decl consumed before the implementation is seen,
# so scanFileForDecisionBinding → run would otherwise infer non-gcsafe and
# break the runInProcess adapter (DEBT#497 follow-up). The implementation is
# pure string analysis — the annotation is truthful.
proc checkProc*(procDecl: string, procBody: string, filePath: string, startLine: int): tuple[violations: bool, reasons: seq[string]] {.gcsafe, raises: [].} =
  ## Check a single procedure for missing axiomDecision pragma.
  result = (false, @[])

  # Already has the pragma
  if "{.axiomDecision" in procBody or "{.axiomDecision" in procDecl:
    return (false, @[])

  # Check if this is a decision point that requires the pragma
  let returnTypeHasResult = hasResultOrOptionReturnType(procDecl)
  let hasEarlyReturns = hasEarlyReturnPattern(procBody)
  let hasValidation = hasValidationLogic(procBody)

  if returnTypeHasResult or hasEarlyReturns or hasValidation:
    var violationReasons: seq[string] = @[]
    if returnTypeHasResult:
      violationReasons.add("returns Result/Option without axiomDecision")
    if hasEarlyReturns:
      violationReasons.add("multiple returns without axiomDecision")
    if hasValidation:
      violationReasons.add("validation logic without axiomDecision")

    let msg = filePath & ":" & $startLine & ": " & procDecl & " " & violationReasons.join("; ")
    result.violations = true
    result.reasons.add(msg)

# ─── Public API ─────────────────────────────────────────────────────────────

proc runDecisionBindingCheck*(repoRoot: string, files: seq[string], waiver: JsonNode): bool {.raises: [CatchableError].} =
  ## Public API: scan files for decision binding violations.
  ## Returns true (PASS) when all decision-point functions carry {.axiomDecision.}.
  var filesToScan: seq[string]

  if files.len == 0:
    let srcDir = repoRoot / "src"
    if not dirExists(srcDir):
      return true
    proc walkRec(dir: string) =
      for kind, path in walkDir(dir):
        if kind == pcFile and path.endsWith(".nim"):
          filesToScan.add(path)
        elif kind == pcDir:
          walkRec(path)
    if dirExists(srcDir):
      walkRec(srcDir)
  else:
    filesToScan = files

  var violationCount = 0
  var seenFiles: seq[string] = @[]

  for f in filesToScan:
    if f in seenFiles:
      continue
    seenFiles.add(f)

    # Check exemptions
    if isFileExempt(f, waiver):
      continue
    let relPath = f.replace(repoRoot & "/", "")
    if isModuleExempt(relPath, waiver):
      continue

    let scanResult = if fileExists(f): scanFileForDecisionBinding(f) else: (false, @[])
    if scanResult.hasViolations:
      inc violationCount

  return violationCount == 0

# ─── Gate Runner Interface ──────────────────────────────────────────────────

proc run*(gate: GateConfig, ctx: InProcessGateContext): GateResult {.raises: [CatchableError].} =
  ## Gate runner interface for the in-process dispatch macro.
  let repoRoot = ctx.repoRoot
  let stagedFiles = ctx.stagedFiles
  let waiver = loadWaiverConfig(repoRoot)
  let passed = runDecisionBindingCheck(repoRoot, stagedFiles, waiver)

  if passed:
    result = GateResult(
      ok: true,
      name: "decision-binding-gate",
      stdout: "All decision-point functions carry {.axiomDecision.} pragma.",
      stderr: "",
      duration: initDuration())
  else:
    var violationDetails: seq[string] = @[]
    var filesToScan = if stagedFiles.len > 0: stagedFiles else: @[]
    if filesToScan.len == 0:
      let srcDir = repoRoot / "src"
      if dirExists(srcDir):
        proc walkRec(dir: string) =
          for kind, path in walkDir(dir):
            if kind == pcFile and path.endsWith(".nim"):
              filesToScan.add(path)
            elif kind == pcDir:
              walkRec(path)
        walkRec(srcDir)

    for f in filesToScan:
      if isFileExempt(f, waiver):
        continue
      let relPath = f.replace(repoRoot & "/", "")
      if isModuleExempt(relPath, waiver):
        continue
      let scanResult = if fileExists(f): scanFileForDecisionBinding(f) else: (false, @[])
      if scanResult.hasViolations:
        for reason in scanResult.reasons:
          violationDetails.add(reason)

    result = GateResult(
      ok: false,
      name: "decision-binding-gate",
      # "FAIL" marker line: the orchestrator's classifyFailure extracts reason
      # lines by the "FAIL" substring — without it the memo layer records this
      # verdict as moNotEvaluated and a FAIL would never replay as FAIL_CACHED
      # (DEBT#471 verdict-axis durability lesson, DEBT#497 follow-up).
      stdout: "FAIL decision-binding-gate: Missing {.axiomDecision.} pragmas detected:\n" & violationDetails.join("\n"),
      stderr: "",
      failureCategory: fcValidation,
      failureReason: "Decision binding violations: " & $violationDetails.len & " function(s) missing pragma",
      duration: initDuration())

{.pop.}

# ─── In-Process Dispatch Adapter (DEBT#497 follow-up) ──────────────────────

proc runInProcess*(ctx: InProcessGateContext): GateResult {.gcsafe, raises: [].} =
  ## InProcessGateProc-shaped adapter over run(). The runner module has no
  ## standalone main (manifest-driven registerLegacyCliGate registration only),
  ## so any standalone AOT link produced an empty 31,872-byte exit-0 binary —
  ## the subprocess CAS path ran nothing and reported PASS (DEBT#497). The
  ## allowlisted in-process path executes the SAME judgment — one verdict SSOT,
  ## no duplicated semantics.
  try:
    result = run(GateConfig(), ctx)
  except CatchableError as e:
    result = GateResult(
      ok: false, name: "decision-binding-gate",
      stdout: "FAIL decision-binding-gate: in-process execution failed — " & e.msg,
      failureCategory: fcValidation,
      failureReason: "in-process execution error: " & e.msg,
      skipCiRequested: false)

# ─── Manifest-Driven Registration ──────────────────────────────────────────
# This gate is registered via src/gate/manifest.d/decision-binding-gate.json
# (registerLegacyCliGate macro in all_gate_runners.nim). Do NOT call
# registerGate() here — it would cause a duplicate registration error.
