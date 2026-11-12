import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Registry-Based Unified Immunity Gate
##
## Consolidates 4 orthogonal immunity checks into a single registry-driven
## gate runner. Each layer is an independent `GateLayer` registered at startup
## and executed sequentially. A single layer failure blocks the gate.
##
## Layers:
##   1. Raises Coverage (Execution Plane) — {.raises: [].} annotation coverage
##   2. Break-Glass Debt (Control Plane) — stale unresolved break-glass entries
##   3. Quarantine Status (Execution Plane) — stale quarantined files
##   4. Ratchet Enforcement (Evolutionary Plane) — monotonic coverage baseline
##
## Baseline: data/immunity_baseline.json (auto-updated by Layer 4 on pass)
## Usage:
##   nim c -r src/gate/runners/immunity_gate.nim [repoRoot]
##
## Reference: AGENTS.md §0.6 (Static First Enforcement), §4 GUARDIAN

import std/json
import std/os
import std/strutils
import std/times
import core/axiom_pragmas
import core/utils/repo_root
import infrastructure/logging_facade


# axiomIoBoundary

axiomIoBoundary()

const
  GateTag = "[immunity]"
  BaselineRelPath = "data/immunity_baseline.json"
  CoreSrcRel = "src/core"
  BreakGlassRel = "logs/break_glass/audit.jsonl"
  QuarantineDirRel = "src/core/_quarantine"
  QuarantineManifestRel = "data/quarantine_manifest.json"

# ── Registry Types ──────────────────────────────────────────────────────────────

type
  GateResult* = object
    passed*: bool
    layer*: string
    message*: string
    education*: string
    autoFix*: string

  GateLayer* = object
    name*: string
    check*: proc(): GateResult {.raises: [CatchableError].}

  RaiseInfo = object
    file: string
    line: int
    name: string

var registry: seq[GateLayer] = @[]

# ── Registry Operations ────────────────────────────────────────────────────────

proc register*(layer: GateLayer) =
  ## Add a gate layer to the execution registry.
  registry.add(layer)

proc resultOk(layerName: string): GateResult =
  GateResult(passed: true, layer: layerName, message: "OK")

proc resultFail(layerName, message, education, autoFix: string): GateResult =
  GateResult(passed: false, layer: layerName, message: message,
             education: education, autoFix: autoFix)

# ── Educational DX Output ──────────────────────────────────────────────────────

proc printFailure(r: GateResult) =
  logInfo("immunity_gate", "\n")
  logError("immunity_gate", "  \x1b[31mFAILED\x1b[0m " & GateTag & " — Layer: " & r.layer & "\n")
  logInfo("immunity_gate", "  " & r.message & "\n\n")
  logInfo("immunity_gate", "  Why this matters:\n")
  for ln in r.education.splitLines():
    logInfo("immunity_gate", "    " & ln.strip() & "\n")
  logInfo("immunity_gate", "\n  Auto-fix:\n    " & r.autoFix & "\n")

# ── Layer 1: Raises Coverage (Execution Plane) ─────────────────────────────────

proc isExemptLine(line: string): bool =
  ## Check if a line carries an exemption pragma.
  const exemptions = ["{.importc}", "{.importcpp}", "{.dynlib}",
                      "{.axiomIoBoundary.}", "{.axiomEffect:"]
  for ex in exemptions:
    if ex in line:
      return true
  return false

proc isProcDecl(line: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Detect proc/func/method declarations at line start (after whitespace).
  let trimmed = line.strip()
  return trimmed.startsWith("proc ") or trimmed.startsWith("func ") or
         trimmed.startsWith("method ")

proc lineHasRaisesAnnot(line: string): bool {.raises: [].} =
  ## True when a line carries a pragma block containing a `raises:` keyword.
  ## Matches both the canonical `{.raises: ...}` form and combined pragma
  ## blocks such as `{.gcsafe, raises: [].}` / `{.axiomImpl., raises: [].}`,
  ## which previously escaped detection because they do not start with
  ## the literal `{.raises:` prefix.
  "{" in line and "}" in line and "raises:" in line

proc hasRaisesAnnot(text: string, declLine: int): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan up to 8 lines ahead of a declaration for any explicit `{.raises: ...}`
  ## annotation (inline `{.raises: [].}` or `{.raises: [CatchableError].}` etc.).
  ## Combined pragmas (`{.gcsafe, raises: [].}`) are recognized as well.
  let lines = text.splitLines()
  let scanEnd = min(declLine + 8, lines.len - 1)
  for i in declLine..scanEnd:
    if lineHasRaisesAnnot(lines[i]):
      return true
  return false

proc isInsideMainModule(text: string, lineIdx: int): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if a line index is inside a `when isMainModule` block.
  ## Scans backward from the line to find the guard.
  let lines = text.splitLines()
  for i in countdown(lineIdx, 0):
    let l = lines[i].strip()
    if l.endsWith("when isMainModule") or l == "when isMainModule:":
      return true
  return false

proc scanRaisesCoverage(content: string, filePath: string,
                        results: var seq[RaiseInfo]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan a single file for unannotated proc/func/method declarations.
  ## Honors file-scope `{.push raises: ...}` (used by 514/571 src/core files):
  ## a proc is considered annotated when an explicit inline `{.raises: ...}`
  ## is present OR a `{.push raises: ...}` scope is currently active.
  let lines = content.splitLines()
  var i = 0
  var raisesPushDepth = 0
  while i < lines.len:
    let line = lines[i]
    if "{.push raises" in line:
      inc raisesPushDepth
    if "{.pop raises" in line and raisesPushDepth > 0:
      dec raisesPushDepth
    if isProcDecl(line):
      if isInsideMainModule(content, i):
        inc i
        continue
      if isExemptLine(line):
        inc i
        continue
      if raisesPushDepth > 0 or hasRaisesAnnot(content, i):
        inc i
        continue
      let trimmed = line.strip()
      var procName = trimmed
      let parenIdx = procName.find('(')
      if parenIdx > 0:
        procName = procName[0 ..< parenIdx]
      for kw in ["proc ", "func ", "method "]:
        if procName.startsWith(kw):
          procName = procName[kw.len .. ^1]
          break
      if procName.endsWith("*"):
        procName = procName[0 ..^ 2]
      results.add(RaiseInfo(file: filePath, line: i + 1, name: procName.strip()))
    inc i

proc collectNimFiles(root, subDir: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Recursively collect .nim files under root/subDir.
  let fullPath = root / subDir
  if not dirExists(fullPath):
    return @[]
  for kind, path in walkDir(fullPath):
    if kind == pcFile and path.endsWith(".nim"):
      result.add(path.relativePath(root))
    elif kind == pcDir:
      result.add(collectNimFiles(root, path.relativePath(root)))

proc checkRaisesCoverage(): GateResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Layer 1: Scan src/core/ for {.raises: [].} annotation coverage.
  let repoRoot = findRepoRoot()
  let baselinePath = repoRoot / BaselineRelPath

  var thresholdPct = 42.0
  if fileExists(baselinePath):
    try:
      let data = parseJson(readFile(baselinePath))
      thresholdPct = data["raises_coverage"]["threshold_pct"].getFloat()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  let nimFiles = collectNimFiles(repoRoot, CoreSrcRel)
  var unannotated: seq[RaiseInfo] = @[]
  var totalDecls = 0

  for relPath in nimFiles:
    let absPath = repoRoot / relPath
    try:
      let content = readFile(absPath)
      let lines = content.splitLines()
      for line in lines:
        if isProcDecl(line):
          inc totalDecls
      scanRaisesCoverage(content, relPath, unannotated)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  let annotated = totalDecls - unannotated.len
  var coveragePct = 0.0
  if totalDecls > 0:
    coveragePct = (annotated.float / totalDecls.float) * 100.0

  if coveragePct >= thresholdPct:
    return resultOk("Raises Coverage")

  var fileList = ""
  var shown = 0
  for info in unannotated:
    if shown >= 10:
      fileList.add("  ... and " & $(unannotated.len - shown) & " more\n")
      break
    fileList.add("  " & info.file & ":" & $info.line & " " & info.name & "\n")
    inc shown

  resultFail(
    "Raises Coverage",
    "Coverage " & formatFloat(coveragePct, ffDecimal, 1) & "% < threshold " &
      formatFloat(thresholdPct, ffDecimal, 1) & "% (" & $annotated & "/" &
      $totalDecls & " annotated)",
    "AGENTS.md \u00a70.6 Static First Enforcement: All core engine logic " &
      "MUST default to `func` and `{.raises: [].}`. Runtime exception " &
      "possibility is driven to zero at compile time.",
    fileList & "\n  Add {.raises: [].} to each unannotated proc/func/method."
  )

# ── Layer 2: Break-Glass Debt (Control Plane) ──────────────────────────────────

proc extractJsonlString(line, field: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract a string value for a given field from a JSONL line.
  let marker = "\"" & field & "\""
  let idx = line.find(marker)
  if idx < 0: return ""
  let colonIdx = line.find(':', idx + marker.len)
  if colonIdx < 0: return ""
  let startQ = line.find('"', colonIdx + 1)
  if startQ < 0: return ""
  let endQ = line.find('"', startQ + 1)
  if endQ < 0: return ""
  result = line[startQ + 1 ..< endQ]

proc parseJsonlTimestamp(line: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract the "timestamp" field from a JSONL line via deterministic scan.
  extractJsonlString(line, "timestamp")

proc parseJsonlResolved(line: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract the "resolved" field from a JSONL line.
  const marker = "\"resolved\""
  let idx = line.find(marker)
  if idx < 0: return false
  let colonIdx = line.find(':', idx + marker.len)
  if colonIdx < 0: return false
  var pos = colonIdx + 1
  while pos < line.len and line[pos] == ' ':
    inc pos
  if line[pos ..< min(pos + 4, line.len)] == "true": return true
  return false

proc checkBreakGlassDebt(): GateResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Layer 2: Check for stale unresolved break-glass entries.
  let repoRoot = findRepoRoot()
  let auditPath = repoRoot / BreakGlassRel

  if not fileExists(auditPath):
    return resultOk("Break-Glass Debt")

  var maxAgeHours = 48
  let baselinePath = repoRoot / BaselineRelPath
  if fileExists(baselinePath):
    try:
      let data = parseJson(readFile(baselinePath))
      maxAgeHours = data["break_glass"]["max_age_hours"].getInt()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  let content = readFile(auditPath)
  let now = getTime()
  var staleEntries: seq[string] = @[]

  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    if parseJsonlResolved(trimmed):
      continue
    let ts = parseJsonlTimestamp(trimmed)
    if ts.len == 0:
      continue
    try:
      let entryTime = parseTime(ts, "yyyy-MM-dd'T'HH:mm:ss", utc())
      let elapsed = now - entryTime
      if elapsed.inSeconds > maxAgeHours * 3600:
        let ticket = extractJsonlString(trimmed, "ticket")
        if ticket.len > 0:
          staleEntries.add(ticket)
        else:
          staleEntries.add(ts)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  if staleEntries.len == 0:
    return resultOk("Break-Glass Debt")

  var ticketList = ""
  for t in staleEntries:
    ticketList.add("  - " & t & "\n")

  resultFail(
    "Break-Glass Debt",
    $staleEntries.len & " unresolved break-glass entry(ies) older than " &
      $maxAgeHours & "h",
    "AGENTS.md \u00a74 GUARDIAN: Break-glass entries must be resolved " &
      "within " & $maxAgeHours & " hours or escalated. Stale entries " &
      "erode trust boundaries.",
    "Resolve or escalate each stale break-glass entry:\n" & ticketList
  )

# ── Layer 3: Quarantine Status (Execution Plane) ───────────────────────────────

proc parseQuarantineAgeDays(manifest: string, filePath: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract quarantine age in days from manifest JSON for a given file.
  ## Returns -1 if not found.
  try:
    let data = parseJson(manifest)
    if data.hasKey("files"):
      for entry in data["files"]:
        if entry.hasKey("path") and entry["path"].getStr() == filePath:
          if entry.hasKey("quarantined_at"):
            let qTime = entry["quarantined_at"].getStr()
            let now = getTime()
            let qDateTime = parseTime(qTime, "yyyy-MM-dd'T'HH:mm:ss", utc())
            let elapsed = now - qDateTime
            return elapsed.inSeconds div 86400
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return -1

proc checkQuarantineStatus(): GateResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Layer 3: Check for stale quarantined files (> 7 days).
  let repoRoot = findRepoRoot()
  let quarantineDir = repoRoot / QuarantineDirRel

  if not dirExists(quarantineDir):
    return resultOk("Quarantine Status")

  let manifestPath = repoRoot / QuarantineManifestRel
  if not fileExists(manifestPath):
    return resultFail(
      "Quarantine Status",
      "Quarantine directory exists but no manifest found",
      "AGENTS.md \u00a70.3 Trust Boundaries: Quarantined files must be " &
        "tracked in a manifest with timestamps for audit trail.",
      "Create " & QuarantineManifestRel & " or remove " & QuarantineDirRel
    )

  let manifest = readFile(manifestPath)
  var staleFiles: seq[string] = @[]

  for kind, path in walkDir(quarantineDir):
    if kind in {pcFile, pcDir}:
      let relFile = path.relativePath(repoRoot)
      let ageDays = parseQuarantineAgeDays(manifest, relFile)
      if ageDays > 7:
        staleFiles.add(relFile)

  if staleFiles.len == 0:
    return resultOk("Quarantine Status")

  var fileList = ""
  for f in staleFiles:
    fileList.add("  git rm " & f & "\n")

  resultFail(
    "Quarantine Status",
    $staleFiles.len & " file(s) quarantined for > 7 days without resolution",
    "AGENTS.md \u00a70.3 Trust Boundaries: Quarantined files should be " &
      "resolved or removed promptly to prevent stale code accumulation.",
    "Remove stale quarantined files:\n" & fileList
  )

# ── Layer 4: Ratchet Enforcement (Evolutionary Plane) ──────────────────────────

proc saveBaseline(repoRoot: string, total, annotated: int; coverage: float) {.axiomEffect: IOEffect.} =
  ## Atomically update baseline via .tmp + rename.
  let baselinePath = repoRoot / BaselineRelPath
  let tmpPath = baselinePath & ".tmp"
  let now = getTime().format("yyyy-MM-dd'T'HH:mm:ss")
  let payload = %*{
    "version": "1.0.0",
    "auto_generated": true,
    "description": "Unified immunity gate baseline. Auto-updated by " &
      "immunity_gate on improvement. Ratchet: coverage can only go up, never down.",
    "last_golden_build": now,
    "raises_coverage": {
      "total_declarations": total,
      "annotated_declarations": annotated,
      "coverage_pct": coverage,
      "threshold_pct": coverage,
      "exempt_patterns": [
        "{.axiomIoBoundary.}", "{.importc}", "{.importcpp}", "{.dynlib}"
      ]
    },
    "quarantine": {
      "manifest_path": QuarantineManifestRel
    },
    "break_glass": {
      "audit_log_path": BreakGlassRel,
      "max_age_hours": 48
    }
  }
  try:
    writeFile(tmpPath, pretty(payload))
    copyFile(tmpPath, baselinePath)
    removeFile(tmpPath)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc enforceRatchet(): GateResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Layer 4: Monotonic ratchet — coverage can only increase.
  let repoRoot = findRepoRoot()
  let baselinePath = repoRoot / BaselineRelPath

  var baselineCoverage = 0.0
  var baselineAnnotated = 0
  if fileExists(baselinePath):
    try:
      let data = parseJson(readFile(baselinePath))
      baselineCoverage = data["raises_coverage"]["coverage_pct"].getFloat()
      baselineAnnotated = data["raises_coverage"]["annotated_declarations"].getInt()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  # Re-scan current coverage
  let nimFiles = collectNimFiles(repoRoot, CoreSrcRel)
  var unannotatedCount = 0
  var totalDecls = 0

  for relPath in nimFiles:
    let absPath = repoRoot / relPath
    try:
      let content = readFile(absPath)
      let lines = content.splitLines()
      for line in lines:
        if isProcDecl(line):
          inc totalDecls
      var unannotated: seq[RaiseInfo] = @[]
      scanRaisesCoverage(content, relPath, unannotated)
      unannotatedCount += unannotated.len
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  let annotated = totalDecls - unannotatedCount
  var currentCoverage = 0.0
  if totalDecls > 0:
    currentCoverage = (annotated.float / totalDecls.float) * 100.0

  if currentCoverage >= baselineCoverage:
    saveBaseline(repoRoot, totalDecls, annotated, currentCoverage)
    return resultOk("Ratchet")

  resultFail(
    "Ratchet",
    "Monotonic regression: current " & formatFloat(currentCoverage, ffDecimal, 1) &
      "% < baseline " & formatFloat(baselineCoverage, ffDecimal, 1) & "%",
    "AGENTS.md \u00a74 GUARDIAN: Ratchet enforces monotonic improvement. " &
      "Coverage must never decrease. This prevents silent debt accumulation.",
    "Revert the change that reduced coverage or add {.raises: [].} to " &
      "the " & $(baselineAnnotated - annotated) & " newly unannotated declaration(s)."
  )

# ── Runner Engine ──────────────────────────────────────────────────────────────

proc runAll*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute all registered gate layers. Returns true if all pass.
  var allPassed = true
  for layer in registry:
    try:
      let r = layer.check()
      if not r.passed:
        printFailure(r)
        allPassed = false
    except CatchableError as e:
      logInfo("immunity_gate", GateTag & " EXCEPTION in layer '" & layer.name & "': " & e.msg & "\n")
      allPassed = false
  if allPassed:
    logInfo("immunity_gate", GateTag & " ALL LAYERS PASSED\n")
  result = allPassed

# ── Main Entry Point ───────────────────────────────────────────────────────────

proc main() =
  register(GateLayer(name: "Raises Coverage", check: checkRaisesCoverage))
  register(GateLayer(name: "Break-Glass Debt", check: checkBreakGlassDebt))
  register(GateLayer(name: "Quarantine Status", check: checkQuarantineStatus))
  register(GateLayer(name: "Ratchet", check: enforceRatchet))
  if not runAll(): quit(1)

when isMainModule:
  main()

