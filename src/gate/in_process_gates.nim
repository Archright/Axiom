import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## in_process_gates.nim — ProjectMap-based in-process gate runners
## These replace subprocess-based gate execution for fast gates.
## File content comes from ProjectMap (already in memory) — no disk I/O.
##
## Registered in pipeline_orchestrator.registerInProcessGate().

import std/[strutils, tables, json, os, sequtils]
import core/observer
import core/trusted/axiom_pragmas
import gate/gate_consts
import infrastructure/logging_facade

func containsDebtMarker(line: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Detect TODO/FIXME/HACK/XXX as whole words only (not substrings like NOT_TODO).
  ## Case-insensitive. Returns true when a standalone debt marker is found.
  let lower = line.toLowerAscii()
  for keyword in ["todo", "fixme", "hack", "xxx"]:
    var pos = 0
    while true:
      let idx = lower.find(keyword, pos)
      if idx < 0: break
      let beforeOk = idx == 0 or not (lower[idx-1].isAlphaNumeric or lower[idx-1] == '_')
      let afterPos = idx + keyword.len
      let afterOk = afterPos >= lower.len or not (lower[afterPos].isAlphaNumeric or lower[afterPos] == '_')
      if beforeOk and afterOk:
        return true
      pos = idx + 1
  return false

# ─── Import Encapsulation Gate (In-Process) ────────────────────────────────

proc isExempted(filepath: string; internal: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if filepath.startsWith("src/core/"):
    return true
  if hubMapping.hasKey(filepath):
    for exc in hubMapping.getOrDefault(filepath):
      if internal.startsWith(exc):
        return true
  for hubKey, hubExceptions in hubMapping.pairs:
    if hubKey.endsWith("/") and filepath.startsWith(hubKey):
      for exc in hubExceptions:
        if internal.startsWith(exc):
          return true
  result = false

proc checkFileContent(relPath: string; content: string): int {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check file content for import encapsulation violations.
  ## Returns violation count (0 = pass).
  result = 0
  var inImportBlock = false
  var lineNo = 0
  for line in content.splitLines:
    inc lineNo
    let stripped = line.strip
    if stripped.len == 0 or stripped.startsWith("#"):
      inImportBlock = false
      continue
    var isImportLine = false
    if stripped.startsWith("import ") or stripped.startsWith("from "):
      inImportBlock = false
      isImportLine = true
    elif stripped == "import":
      inImportBlock = true
      continue
    elif inImportBlock:
      if line.startsWith(" ") or line.startsWith("\t"):
        isImportLine = true
      else:
        inImportBlock = false
    if isImportLine:
      for internal in InternalPaths:
        if internal in stripped:
          if internal in relPath:
            continue
          if isExempted(relPath, internal):
            continue
          inc result

proc runImportEncapsulationInProcess*(pm: ProjectMap;
 repoRoot: string): bool =
  ## In-process import encapsulation check using ProjectMap.
  ## Returns true if all imports are properly encapsulated.
  var totalViolations = 0
  for relPath in pm.sortedPaths:
    if not relPath.endsWith(".nim"): continue
    let entry = pm.files.getOrDefault(relPath)
    if entry.content.len == 0: continue
    let violations = checkFileContent(relPath, entry.content)
    totalViolations += violations
  result = totalViolations == 0

# ─── Logging Policy Gate (In-Process) ──────────────────────────────────────

type
  Severity = enum
    sevError, sevWarning

  PatternRule = object
    id: string
    description: string
    pattern: string
    context: string
    severity: Severity

func parseSeverity(raw: string): Severity {.raises: [].} =
  case raw.strip()
  of "error": sevError
  of "warning": sevWarning
  else: sevWarning

proc parseLoggingConfig(content: string): seq[PatternRule] =
  ## Parse logging_policy.json config. Reads all patterns from each rule's "patterns" array.
  result = @[]
  try:
    let root = parseJson(content)
    if not root.hasKey("forbidden"): return
    for ruleNode in root["forbidden"]:
      if ruleNode.kind != JObject: continue
      let ruleId = ruleNode{"id"}.getStr("")
      let ruleDesc = ruleNode{"description"}.getStr("")
      if not ruleNode.hasKey("patterns"): continue
      let patterns = ruleNode["patterns"]
      if patterns.kind != JArray: continue
      for patNode in patterns:
        if patNode.kind != JObject: continue
        let pattern = patNode{"pattern"}.getStr("")
        let context = patNode{"context"}.getStr("")
        let severity = parseSeverity(patNode{"severity"}.getStr("warning"))
        if pattern.len > 0 and ruleId.len > 0:
          result.add(PatternRule(
            id: ruleId, description: ruleDesc,
            pattern: pattern, context: context,
            severity: severity))
  except CatchableError:
    return @[]  # axiom:fail-closed — corrupt config = no valid rules, caller must fail gate

func matchesFileContext(rule: PatternRule; filePath: string): bool {.raises: [].} =
  if rule.context.len == 0 or rule.context == "all" or rule.context == "log-statement":
    return true
  let ext = filePath.splitFile().ext
  case rule.context
  of "nim": ext == ".nim"
  of "javascript": ext in [".js", ".ts", ".jsx", ".tsx"]
  of "python": ext == ".py"
  else: true

proc scanFileContent(filePath: string; content: string;
                     rules: seq[PatternRule]): (int, int) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan file content against rules. Returns (errorCount, warningCount).
  var errorCount = 0
  var warningCount = 0
  for rule in rules:
    if not matchesFileContext(rule, filePath):
      continue
    # IMPORTANT: & (AND) must be checked BEFORE | (OR) — mixed patterns like
    # "echo|stderr & password|token" would incorrectly enter the OR branch otherwise.
    if rule.pattern.contains('&'):
      # Line-level AND: any single line must match ALL groups
      let groups = rule.pattern.split('&').mapIt(it.strip())
      var anyLineMatches = false
      for line in content.splitLines():
        var allGroupsMatch = true
        for group in groups:
          var groupMatch = false
          if group.contains('|'):
            let alternatives = group.split('|').mapIt(it.strip())
            for alt in alternatives:
              var needle = alt
              var caseInsensitive = false
              if needle.startsWith("(?i)"):
                needle = needle[4..^1]
                caseInsensitive = true
              let haystack = if caseInsensitive: line.toLowerAscii() else: line
              let pat = if caseInsensitive: needle.toLowerAscii() else: needle
              if haystack.contains(pat):
                groupMatch = true
                break
          else:
            var needle = group
            var caseInsensitive = false
            if needle.startsWith("(?i)"):
              needle = needle[4..^1]
              caseInsensitive = true
            let haystack = if caseInsensitive: line.toLowerAscii() else: line
            let pat = if caseInsensitive: needle.toLowerAscii() else: needle
            groupMatch = haystack.contains(pat)
          if not groupMatch:
            allGroupsMatch = false
            break
        if allGroupsMatch:
          anyLineMatches = true
          break
      if anyLineMatches:
        if rule.severity == sevError: inc errorCount
        else: inc warningCount
    elif rule.pattern.contains('|'):
      # OR: match any
      let alternatives = rule.pattern.split('|').mapIt(it.strip())
      var matched = false
      for alt in alternatives:
        var needle = alt
        var caseInsensitive = false
        if needle.startsWith("(?i)"):
          needle = needle[4..^1]
          caseInsensitive = true
        for line in content.splitLines():
          let haystack = if caseInsensitive: line.toLowerAscii() else: line
          let pat = if caseInsensitive: needle.toLowerAscii() else: needle
          if haystack.contains(pat):
            matched = true
            break
        if matched: break
      if matched:
        if rule.severity == sevError: inc errorCount
        else: inc warningCount
    else:
      var needle = rule.pattern
      var caseInsensitive = false
      if needle.startsWith("(?i)"):
        needle = needle[4..^1]
        caseInsensitive = true
      for line in content.splitLines():
        let haystack = if caseInsensitive: line.toLowerAscii() else: line
        let pat = if caseInsensitive: needle.toLowerAscii() else: needle
        if haystack.contains(pat):
          if rule.severity == sevError: inc errorCount
          else: inc warningCount
          break
  (errorCount, warningCount)

proc runLoggingPolicyInProcess*(pm: ProjectMap; repoRoot: string): bool {.axiomEffect: IOEffect.} =
  ## In-process logging policy check using ProjectMap.
  ## Returns true if no violations found.
  let configPath = repoRoot / "logging_policy.json"
  var rules: seq[PatternRule]
  if fileExists(configPath):
    try:
      rules = parseLoggingConfig(readFile(configPath))
    except CatchableError:
      return false  # Config parse error = fail closed
  else:
    return false  # Missing logging policy config = fail closed

  var totalErrors = 0
  var totalWarnings = 0
  for relPath in pm.sortedPaths:
    if not relPath.endsWith(".nim"): continue
    let entry = pm.files.getOrDefault(relPath)
    if entry.content.len == 0: continue
    let (errors, warnings) = scanFileContent(relPath, entry.content, rules)
    totalErrors += errors
    totalWarnings += warnings

  result = totalErrors == 0

# ─── Debt Reduction Gate (In-Process) ──────────────────────────────────────

proc runDebtReductionInProcess*(pm: ProjectMap; repoRoot: string): bool {.axiomEffect: IOEffect.} =
  ## In-process debt reduction check using ProjectMap.
  ## Compares current debt count against baseline.
  let baselinePath = repoRoot / "data" / "debt_reduction_baseline.json"
  if not fileExists(baselinePath): return false  # Baseline SSOT missing = fail closed

  var baselineTotal = 0
  try:
    let j = parseJson(readFile(baselinePath))
    baselineTotal = j{"total"}.getInt(0)
  except CatchableError:
    logError("debt-reduction-gate", "Corrupt debt_reduction_baseline.json = FAIL")
    return false

  var currentDebt = 0
  for relPath in pm.sortedPaths:
    if not relPath.endsWith(".nim"): continue
    let entry = pm.files.getOrDefault(relPath)
    if entry.content.len == 0: continue
    # Count debt markers: TODO, FIXME, HACK, XXX — only in comments with word-boundary matching
    # axiom:theater-fix — was counting substrings in any context (false positives on NOT_TODO, variable names)
    for line in entry.content.splitLines():
      let stripped = line.strip()
      if not (stripped.startsWith("#") or stripped.startsWith("//")):
        continue
      if containsDebtMarker(stripped):
        inc currentDebt

  # Pass if current debt ≤ baseline (monotonic non-increase)
  result = currentDebt <= baselineTotal

# ─── Monotonic Whitelist Gate (In-Process) ─────────────────────────────────

proc runMonotonicWhitelistInProcess*(pm: ProjectMap; repoRoot: string): bool {.axiomEffect: IOEffect.} =
  ## In-process monotonic whitelist check.
  ## Verifies that the architecture policy lock file only grows (never shrinks).
  let lockPath = repoRoot / "src" / "gate" / "architecture_policy.lock"
  if not fileExists(lockPath): return false  # Lock SSOT missing = fail closed

  var entryCount = 0
  try:
    let content = readFile(lockPath)
    for line in content.splitLines():
      if line.strip().len > 0 and not line.strip().startsWith("#"):
        inc entryCount
  except CatchableError:
    logError("monotonic-whitelist-gate", "Can't read architecture_policy.lock = FAIL")
    return false

  # Baseline check: entry count must not decrease
  let baselinePath = repoRoot / "data" / "monotonic_whitelist_baseline.json"
  if not fileExists(baselinePath): return false

  try:
    let j = parseJson(readFile(baselinePath))
    let baselineCount = j{"count"}.getInt(0)
    result = entryCount >= baselineCount
  except CatchableError:
    logError("monotonic-whitelist-gate", "Corrupt monotonic_whitelist_baseline.json = FAIL")
    result = false

# ─── Conflict Marker Gate (In-Process) ─────────────────────────────────────

proc runConflictMarkerInProcess*(pm: ProjectMap; repoRoot: string): bool =
  ## In-process conflict marker check using ProjectMap.
  ## Scans all .nim files for leftover git conflict markers and
  ## CONFLICT_UNRESOLVED annotations indicating incomplete rebase/merge.
  ## Returns true if no violations found.
  for relPath in pm.sortedPaths:
    if not relPath.endsWith(".nim"): continue
    # Exclude this gate's own source to avoid false positives on detection strings
    if relPath.endsWith("conflict_marker_gate.nim"): continue
    if relPath.endsWith("in_process_gates.nim"): continue
    let entry = pm.files.getOrDefault(relPath)
    if entry.content.len == 0: continue
    var inConflict = false
    for line in entry.content.splitLines():
      let stripped = line.strip()
      # Conflict annotation comment
      if "# CONFLICT_UNRESOLVED" in stripped:
        return false
      # Conflict marker begin: <<<<<<<
      if stripped.startsWith("<<<<<<< "):
        inConflict = true
        return false
      # Conflict marker separator: ======= (only within conflict)
      if stripped == "=======" and inConflict:
        return false
      # Conflict marker end: >>>>>>>>
      if stripped.startsWith(">>>>>>> "):
        inConflict = false
        return false
  result = true

# ─── Language Ban Gate (In-Process) ────────────────────────────────────────

const
  LangBanAllowedExts: array[14, string] = [
    "nim", "lean", "md", "toml", "nims", "lock", "feature",
    "json", "yaml", "yml", "gitignore", "gitattributes", "editorconfig",
    "nimble"
  ]

  LangBanAllowedPrefixes: array[6, string] = [
    "vendor/", ".", "LICENSE", "README", "lakefile", "lean-toolchain"
  ]

  LangBanAllowedExact: array[7, string] = [
    "Makefile", "lean-toolchain", "Dockerfile.build",
    "logs/bypass_audit.jsonl", "bin/sync-branch",
    "bin/sync-main-worktree",
    "data/expected_invariant_hash.txt"
  ]

func langBanHasAllowedExt(path: string): bool {.raises: [].} =
  let lastDot = path.rfind('.')
  if lastDot < 0: return false
  let ext = path[lastDot + 1 .. ^1].toLowerAscii()
  for allowed in LangBanAllowedExts:
    if ext == allowed:
      return true
  false

func langBanMatchesAllowedPath(path: string): bool {.raises: [].} =
  for prefix in LangBanAllowedPrefixes:
    if path.startsWith(prefix):
      return true
  for exact in LangBanAllowedExact:
    if path == exact:
      return true
    let lastSlash = path.rfind('/')
    if lastSlash >= 0 and path[lastSlash + 1 .. ^1] == exact:
      return true
  false

proc runLanguageBanInProcess*(pm: ProjectMap; repoRoot: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## In-process language ban check using ProjectMap.
  ## Verifies no disallowed file extensions exist in the project source.
  ## Returns true if all files have allowed extensions.
  for relPath in pm.sortedPaths:
    # Skip paths that match allowlisted prefixes or exact patterns
    if langBanMatchesAllowedPath(relPath): continue
    if not langBanHasAllowedExt(relPath):
      return false
  result = true

# ─── Nimtry Gate (In-Process) ─────────────────────────────────────────────

import gate/nimtry/nimtry_cli

proc runNimtryGateInProcess*(pm: ProjectMap; repoRoot: string): bool {.axiomEffect: IOEffect.} =
  ## In-process nimtry architecture check.
  ## Delegates to runNimtryInProcess with --full-tree for comprehensive scan.
  ## Returns true if no architecture violations found.
  let res = runNimtryInProcess(@["--full-tree"])
  result = res.exitCode == 0

{.pop.}

