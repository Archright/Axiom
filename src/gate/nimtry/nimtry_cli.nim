import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Nimtry standalone CLI entry point — unified Tier 2d gate.
##
## Runs all nimtry queries (soc-transitive, solid-lsp, solid-srp) PLUS
## the core architecture rules (layer import violations, SSOT type placement,
## SOLID forbidden calls, SSOT forbidden assignments, surface area limits,
## DRY duplicate detection) that were previously in architecture_gate.
##
## Usage: nimtry [--full-tree] [file1.nim file2.nim ...]

import std/os
import std/strutils
import std/options
import std/sequtils
import std/osproc
import std/json
import std/tables
import std/algorithm
import std/sets
import std/times
import core/axiom_pragmas
{.pop.}

import core/parsers/safe_parsers
import core/results
import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/rule_patterns
import gate/nimtry/nimtry_query
import gate/nimtry/nimtry_cache
import gate/nimtry/nimtry_extract_part3_part2
import gate/nimtry/nimtry_policy_lock
import core/utils/file_utils
import core/utils/repo_root
import checksums/sha2
import infrastructure/logger
import infrastructure/logging_facade

type
  Baseline* = object
    totalViolations*: int
    errorCount*: int
  ViolationBaseline* = object
    version*: int
    created*: string
    totalViolations*: int
    bySeverity*: Table[string, int]
    fingerprints*: HashSet[string]

  NimtryStatus* = enum
    nsPass = "PASS"
    nsFail = "FAIL"
    nsQuarantined = "QUARANTINED"

  NimtryResult* = object
    status*: NimtryStatus
    message*: string
    exitCode*: int  ## 0 = pass, 1 = fail

  NimtryContext* = object
    ## Isolated execution context for in-process nimtry.
    ## Created fresh on every call to prevent state contamination.
    errorCount*: int
    cacheHits*: int
    cacheMisses*: int
    allModuleFacts*: seq[ModuleFacts]
    violations*: seq[ArchitectureViolationArtifact]

proc loadBaseline*(path: string): Option[Baseline] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load ratchet baseline from JSON file.
  ## Returns none if file missing or malformed — graceful degradation.
  if not fileExists(path):
    return none(Baseline)
  let content = try: readFile(path) except CatchableError: return none(Baseline)
  let node = try: parseJson(content) except CatchableError: return none(Baseline)
  try:
    let total = node["total_violations"].getInt()
    let bySev = node["by_severity"]
    let errors = if bySev.hasKey("error"): bySev["error"].getInt() else: total
    return some(Baseline(totalViolations: total, errorCount: errors))
  except CatchableError:
    return none(Baseline)

proc normalizeDetail(detail: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Strip line:col numbers from detail to make fingerprints stable across edits.
  ## "src/foo.nim:42:5: message" → "src/foo.nim::: message"
  result = detail
  var i = 0
  while i < result.len:
    if result[i] == ':' and i + 1 < result.len and result[i+1].isDigit:
      # Check if this follows a .nim path
      var j = i - 1
      var hasNimExt = false
      while j >= 4:
        if result[j-3..j] == ".nim":
          hasNimExt = true
          break
        dec j
      if hasNimExt:
        # Skip :digits or :digits:digits pattern (line or line:col)
        var endIdx = i
        var segments = 0
        while endIdx < result.len and segments < 2:
          if result[endIdx] == ':':
            inc endIdx
            while endIdx < result.len and result[endIdx].isDigit:
              inc endIdx
            inc segments
          else:
            break
        if segments >= 1:
          result = result[0..<i] & "::" & result[endIdx..^1]
          i += 2
          continue
    inc i

proc computeViolationFingerprint(rule, file, detail: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var normalized = normalizeDetail(detail)
  let root = try: findRepoRoot() except CatchableError: (try: getCurrentDir() except OSError: "")
  let prefix = root.replace("\\", "/").strip(chars = {'/'}) & "/"
  if prefix != "/" and prefix.len > 1:
    normalized = normalized.replace(prefix, "")
  let input = rule & "::" & file & "::" & normalized
  var hasher = initSha_256()
  hasher.update(input)
  result = $hasher.digest()

proc loadBaselineV2(path: string): ViolationBaseline {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load baseline from JSON. Falls back to v1 (count-only) if no violations array.
  if not fileExists(path):
    return ViolationBaseline(version: 2, fingerprints: initHashSet[string]())
  try:
    let j = parseFile(path)
    result.version = if j.hasKey("version"): j["version"].getInt else: 1
    result.totalViolations = if j.hasKey("total_violations"): j["total_violations"].getInt else: 0
    result.bySeverity = initTable[string, int]()
    if j.hasKey("by_severity"):
      for k, v in j["by_severity"]:
        result.bySeverity[k] = v.getInt
    result.fingerprints = initHashSet[string]()
    if j.hasKey("violations"):
      for v in j["violations"]:
        let idNode = v{"id"}
        if idNode != nil:
          result.fingerprints.incl(idNode.getStr)
  except CatchableError:
    result = ViolationBaseline(version: 2, fingerprints: initHashSet[string]())

proc saveBaselineV2(path: string; violations: seq[ArchitectureViolationArtifact]) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Save current violations as the new baseline with per-violation fingerprints.
  var j = newJObject()
  j["version"] = %2
  let ts = try: now().format("yyyy-MM-dd'T'HH:mm:sszzz") except CatchableError: ""
  j["created"] = %ts
  j["total_violations"] = %violations.len
  var bySev = newJObject()
  var counts = initTable[string, int]()
  for v in violations:
    counts.mgetOrPut(v.severity, 0).inc
  for k, c in counts:
    bySev[k] = %c
  j["by_severity"] = bySev
  var jViolations = newJArray()
  for v in violations:
    var jv = newJObject()
    let file = if v.files.len > 0: v.files[0] else: ""
    jv["id"] = %computeViolationFingerprint(v.rule, file, v.detail)
    jv["rule"] = %v.rule
    jv["file"] = %file
    jv["detail"] = %v.detail
    jv["severity"] = %v.severity
    jViolations.add(jv)
  j["violations"] = jViolations
  try:
    writeFile(path, j.pretty)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc normalizedPath(path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var p = path.replace("\\", "/")
  # Resolve symlinks to canonical path for DRY detection
  try:
    if symlinkExists(p):
      let target = expandSymlink(p)
      if target.len > 0:
        p = target.replace("\\", "/")
  except OSError:
    discard
  # Strip repo root prefix for consistent comparison
  let repoRoot = try: getCurrentDir() except OSError: ""
  if repoRoot.len > 0:
    let prefix = repoRoot.replace("\\", "/") & "/"
    if p.startsWith(prefix):
      p = p[prefix.len .. ^1]
  p

proc collectSourceFiles(repoRoot: string; fullTree: bool; stagedFiles: seq[
    string]): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if fullTree:
    try:
      for path in walkDirRec(repoRoot / "src"):
        if path.endsWith(".nim"):
          result.add(normalizedPath(path))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  else:
    for rawPath in stagedFiles:
      if rawPath.endsWith(".nim"):
        result.add(normalizedPath(rawPath))
      elif dirExists(repoRoot / rawPath):
        try:
          for path in walkDirRec(if isAbsolute(rawPath): rawPath else: repoRoot / rawPath):
            if path.endsWith(".nim"):
              result.add(normalizedPath(path))
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
  # walkDirRec yields filesystem(readdir) order, which is NOT deterministic
  # across machines (ext4/xfs vs local). Sorting at the collection entry makes
  # allModuleFacts order deterministic so last-write-wins bare-name resolution
  # in call_graph/effect_queries/purity_queries never flips on CI.
  algorithm.sort(result)

proc shellQuote(s: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Simple POSIX shell single-quote escaping.
  "'" & s.replace("'", "'\\''") & "'"

proc parseAddedLineRanges(baseRef: string; filePath: string): seq[tuple[
    startLine, endLine: int]] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run git diff --unified=0 against baseRef for the given file and
  ## extract line ranges of added code.
  if baseRef.len == 0:
    return @[]
  let cmd = "git diff --unified=0 --no-color " & shellQuote(baseRef) & " -- " &
      shellQuote(filePath)
  let (output, exitCode) = try:
    execCmdEx(cmd)
  except CatchableError:
    return @[]
  if exitCode != 0:
    return @[]
  if output.len == 0:
    return @[]
  var ranges: seq[tuple[startLine, endLine: int]] = @[]
  for line in output.splitLines():
    # Parse hunk header: @@ -oldLine,oldCount +newLine,newCount @@
    if line.len >= 4 and line[0] == '@' and line[1] == '@':
      # Extract +newLine,newCount part
      let plusIdx = line.find("+", 3)
      if plusIdx < 0:
        continue
      let commaIdx = line.find(',', plusIdx)
      let spaceAfter = line.find(' ', plusIdx)
      var newLine: int
      var newCount: int
      if commaIdx > 0 and (spaceAfter < 0 or commaIdx < spaceAfter):
        # format: +newLine,newCount
        let newLineStr = line[plusIdx + 1 .. commaIdx - 1]
        # find end of newCount
        var endPos = commaIdx + 1
        while endPos < line.len and line[endPos] in {'0'..'9'}:
          endPos += 1
        let newCountStr = line[commaIdx + 1 .. endPos - 1]
        let newLineRes = safeParseInt(newLineStr)
        let newCountRes = safeParseInt(newCountStr)
        if newLineRes.isErr or newCountRes.isErr:
          continue
        newLine = newLineRes.get
        newCount = newCountRes.get
      else:
        # format: +newLine (count = 1)
        let endPos = if spaceAfter > 0: spaceAfter - 1 else: line.high
        let newLineStr = line[plusIdx + 1 .. endPos]
        let newLineRes = safeParseInt(newLineStr)
        if newLineRes.isErr:
          continue
        newLine = newLineRes.get
        newCount = 1
      if newCount > 0:
        ranges.add((newLine, newLine + newCount - 1))
  result = ranges

proc runNimtryInProcess*(args: seq[string]): NimtryResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## In-process entry point for nimtry scan.
  ## Takes explicit args instead of reading commandLineParams().
  ## All state is local — safe for in-process calls from the pipeline orchestrator.

  # ── Compiler Version Lock (Phase 5B) ─────────────────────────────────────
  let compilerLockPath = "data/nimtry_compiler_lock.json"
  if fileExists(compilerLockPath):
    let lockData = try: parseFile(compilerLockPath) except CatchableError: newJObject()
    let expected = lockData{"expected_version"}.getStr("")
    if expected.len > 0 and NimVersion != expected:
      try:
        logInfo("nimtry_cli", "⚠ [nimtry] Compiler version mismatch: expected " & expected &
                         ", got " & NimVersion & ". Results may be unreliable.")
      except IOError: # axiom:best-effort(logging failure must not block gate result)
        discard

  # ── Version / Canary ──
  for p in args:
    if p == "--version" or p == "-v":
      try:
        logger.info("nimtry 1.0.0")
      except IOError: # axiom:best-effort(logging failure must not block gate result)
        discard
      return NimtryResult(status: nsPass, message: "nimtry 1.0.0", exitCode: 0)

  var files: seq[string]
  var fullTree = false
  var updateLock = false
  var baseRef = ""
  var listViolations = false
  var strictMode = false
  var updateBaseline = false
  var diffBaseline = false
  let params = args
  if params.len == 0:
    fullTree = true
  else:
    var i = 0
    while i < params.len:
      let p = params[i]
      case p
      of "--full-tree":
        fullTree = true
      of "--update-lock":
        updateLock = true
      of "--strict":
        strictMode = true
      of "--update-baseline":
        updateBaseline = true
      of "--diff-baseline":
        diffBaseline = true
      of "--base-ref":
        if i + 1 < params.len:
          i += 1
          baseRef = params[i]
      else:
        if p == "--list":
          listViolations = true
        elif not p.startsWith("-"):
          files.add(p)
      i += 1

  # Default to full-tree scan when no files are explicitly specified
  if not fullTree and files.len == 0:
    fullTree = true

  let repoRoot = try: getCurrentDir() except OSError: "."
  let sourceFiles = collectSourceFiles(repoRoot, fullTree, files)

  # policyHash: only files that affect nimtry analysis results.
  # architecture_debt.json is SRP-only (config.nims SRP block) — excluded to prevent
  # full cache invalidation when debt registry changes.
  let policyHash = nimtry_cache.computeMultiFileHash(@[repoRoot / "src/gate/architecture_policy.lock", repoRoot / "config.nims"])
  let binaryHash = nimtry_cache.computeFileHash(getAppFilename())

  var allModuleFacts: seq[ModuleFacts] = @[]
  var cacheHits = 0
  var cacheMisses = 0
  for path in sourceFiles:
    if not fileExists(path): continue

    let cached = loadCachedFacts(path, policyHash, binaryHash)
    if cached.isSome:
      var facts = cached.get
      if baseRef.len > 0:
        facts.addedLineRanges = parseAddedLineRanges(baseRef, path)
      allModuleFacts.add(facts)
      cacheHits += 1
      continue

    let source = try: readFileSafe(path) except CatchableError: continue
    var facts = extractModuleFactsV4(path, source)
    if baseRef.len > 0:
      facts.addedLineRanges = parseAddedLineRanges(baseRef, path)
    allModuleFacts.add(facts)
    saveCachedFacts(path, facts, policyHash, binaryHash)
    cacheMisses += 1

  if updateLock:
    ## Ground Truth mode: skip policy validation, derive directly from codebase
    let lockContent = generatePolicyLock(allModuleFacts, loadArchitecturePolicy().policy)
    if not writeFileSafe(repoRoot / "src/gate/architecture_policy.lock", lockContent):
      try:
        logError("nimtry_cli", "[nimtry] FAILED — could not write lock file")
      except IOError: # axiom:best-effort(logging failure must not block gate result)
        discard
      return NimtryResult(status: nsFail, message: "lock update failed", exitCode: 1)
    logger.info("[nimtry] LOCK UPDATED — Ground Truth written to architecture_policy.lock")
    return NimtryResult(status: nsPass, message: "lock updated", exitCode: 0)

  let parsedPolicy = loadArchitecturePolicy()
  if not parsedPolicy.ok:
    try:
      logError("nimtry_cli", "[nimtry] FAILED — policy invalid: " &
          parsedPolicy.diagnostics.join("; "))
    except IOError:
      discard
    return NimtryResult(status: nsFail, message: "policy invalid", exitCode: 1)
  let policy = parsedPolicy.policy

  let violations = runAllQueries(allModuleFacts, policy)

  # Live-count sidecar: current measured violations, consumed by
  # debt_integrity_gate.nim for the "Active Violations" metric. This is the
  # authoritative runtime number — the baseline total is the Historical Cap.
  let livePath = repoRoot / "data/nimtry_live_count.json"
  try:
    let liveCount = %*{"total_violations": violations.len,
                       "error_violations": violations.filterIt(it.severity == "error").len,
                       "warning_violations": violations.filterIt(it.severity == "warning").len,
                       "generated_at": now().format("yyyy-MM-dd'T'HH:mm:ss'Z'")}
    discard writeFileSafe(livePath, liveCount.pretty()) # axiom:best-effort(live-count sidecar — informational, gating uses baseline cap)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  if listViolations:
    try:
      for v in violations:
        let sev = v.severity.toUpperAscii()
        logInfo("nimtry_cli", "  [" & sev & "] " & v.rule & ": " & v.detail)
    except IOError:
      discard

  # ── Baseline Fingerprint Protocol (v2) ──
  let baselinePath = repoRoot / "data/nimtry_baseline.json"

  # Update baseline: freeze current violations as new baseline
  if updateBaseline:
    saveBaselineV2(baselinePath, violations)
    try:
      logger.info("[nimtry] Baseline updated with " & $violations.len & " violations.")
    except IOError:
      discard
    return NimtryResult(status: nsPass, message: "baseline updated", exitCode: 0)

  # ── Debt Anchoring: Fingerprint-based v2 Protocol (PRIMARY) ──
  # Existing violations are anchored as debt; only NEW violations trigger failure.
  let baselineV2 = loadBaselineV2(baselinePath)
  if baselineV2.version >= 2 and baselineV2.fingerprints.len > 0:
    var newViolations: seq[ArchitectureViolationArtifact]
    var resolvedCount = 0
    var currentFingerprints = initHashSet[string]()

    for v in violations:
      let file = if v.files.len > 0: v.files[0] else: ""
      let fp = computeViolationFingerprint(v.rule, file, v.detail)
      currentFingerprints.incl(fp)
      if fp notin baselineV2.fingerprints:
        newViolations.add(v)

    for fp in baselineV2.fingerprints:
      if fp notin currentFingerprints:
        inc resolvedCount

    # --diff-baseline: show diff without gating
    if diffBaseline:
      try:
        logger.info("=== Baseline Diff ===")
        logger.info "New: " & $newViolations.len
        logger.info "Resolved: " & $resolvedCount
        logger.info "Stable: " & $(violations.len - newViolations.len)
        for v in newViolations:
          logger.info "  NEW: [" & v.severity & "] " & v.rule & " — " & v.detail
      except IOError: # axiom:best-effort(logging failure must not block gate result)
        discard
      return NimtryResult(status: nsPass, message: "diff shown", exitCode: 0)

    # Primary gating: block on any NEW violation not in baseline
    let newErrors = newViolations.filterIt(it.severity == "error")
    if newErrors.len > 0:
      try:
        logError("nimtry_cli", "[nimtry] FAIL: " & $newErrors.len & " new ERROR violations not in baseline (debt anchoring)")
        for v in newErrors:
          logError("nimtry_cli", "  [error] " & v.rule & " — " & v.detail)
      except IOError: # axiom:best-effort(logging failure must not block gate result)
        discard
      return NimtryResult(status: nsFail, message: "new ERROR violations", exitCode: 1)
    if newViolations.len > 0:
      try:
        logError("nimtry_cli", "[nimtry] FAIL: " & $newViolations.len & " new violations not in baseline (debt anchoring)")
        for v in newViolations:
          logInfo("nimtry_cli", "  [" & v.severity & "] " & v.rule & " — " & v.detail)
      except IOError: # axiom:best-effort(logging failure must not block gate result)
        discard
      return NimtryResult(status: nsFail, message: "new violations", exitCode: 1)

    # No new violations → PASS with debt status
    let total = violations.len
    let errorCount = violations.filterIt(it.severity == "error").len
    let warningCount = total - errorCount
    if total > 0:
      let resolved = if resolvedCount > 0: ", " & $resolvedCount & " resolved" else: ""
      try:
        logError("nimtry_cli", "[nimtry] PASS — " & $total & " violations (debt anchored)" &
          " (errors: " & $errorCount & ", warnings: " & $warningCount &
          resolved & ")" &
          " (cache: " & $cacheHits & " hits, " & $cacheMisses & " misses)")
      except IOError: # axiom:best-effort(logging failure must not block gate result)
        discard
    else:
      try:
        logger.info "[nimtry] PASSED — no violations. (cache: " & $cacheHits &
            " hits, " & $cacheMisses & " misses)"
      except IOError: # axiom:best-effort(logging failure must not block gate result)
        discard
    return NimtryResult(status: nsPass, message: "pass", exitCode: 0)

  # ── Ratchet Protocol (FALLBACK: v1 baselines only) ──
  # Activates only when v2 fingerprint baseline is unavailable.
  let baseline = loadBaseline(baselinePath)
  let total = violations.len
  let errorCount = violations.filterIt(it.severity == "error").len
  let warningCount = total - errorCount
  let limit = if baseline.isSome: baseline.get.totalViolations else: total
  let errorLimit = if baseline.isSome: baseline.get.errorCount else: errorCount

  if errorCount > errorLimit:
    try:
      logError("nimtry_cli", "[nimtry] REGRESSION — error violations: " & $errorCount &
        " > baseline " & $errorLimit & " (+" & $(errorCount - errorLimit) & ")")
      if not listViolations:
        let newErrors = violations.filterIt(it.severity == "error")
        for v in newErrors:
          logError("nimtry_cli", "  [ERROR] " & v.rule & ": " & v.detail)
    except IOError:
      discard
    return NimtryResult(status: nsFail, message: "error regression", exitCode: 1)

  if total > limit:
    try:
      logInfo("nimtry_cli", "[nimtry] REGRESSION — total violations: " & $total &
        " > baseline " & $limit & " (+" & $(total - limit) & ")")
      logInfo("nimtry_cli", "[nimtry] New violations must not increase the total count.")
    except IOError:
      discard
    return NimtryResult(status: nsFail, message: "total regression", exitCode: 1)

  if total > 0:
    let trend = if total < limit: " ↓" & $(limit - total) & " improving"
                elif total == limit: " stable"
                else: ""
    try:
      logError("nimtry_cli", "[nimtry] PASS — " & $total & " violations " &
        "(errors: " & $errorCount & ", warnings: " & $warningCount &
        ", baseline: " & $limit & trend & ")" &
        " (cache: " & $cacheHits & " hits, " & $cacheMisses & " misses)")
    except IOError: # axiom:best-effort(logging failure must not block gate result)
      discard
  else:
    try:
      logger.info "[nimtry] PASSED — no violations. (cache: " & $cacheHits &
          " hits, " & $cacheMisses & " misses)"
    except IOError: # axiom:best-effort(logging failure must not block gate result)
      discard
  return NimtryResult(status: nsPass, message: "pass", exitCode: 0)

proc runNimtry*(): NimtryResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## CLI entry point. Delegates to runNimtryInProcess with command-line args.
  ## Kept for backward compatibility with nimtry_gate.nim and standalone usage.
  runNimtryInProcess(commandLineParams())

proc main*() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Thin wrapper for backward compatibility. Delegates to runNimtry().
  let res = runNimtry()
  quit(res.exitCode)

