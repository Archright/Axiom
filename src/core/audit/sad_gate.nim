import core/trusted/layer_declaration
axiomLayer "domain"
import burn_down_queue
import core/interfaces/file_io_executor
import core/pure/json_parse
import core/types/hubs/audit_hub
import hotspot_analyzer
import hotspot_gate
import std/[algorithm, os, strutils, times]
import std/json except parseJson
import core/trusted/axiom_pragmas
# axiomIoBoundary

{.push raises: [IOError, OSError, CatchableError].}  # readFile, walkDir, writeFile, createDir at I/O boundary; DaysUntilEnforcementError is CatchableError

let fileIo* = SystemFileIoExecutor()
type
  AuditMode* = enum
    amWarn      ## Warning only (grace period)
    amFail      ## Hard fail (enforcement)
const
  ExemptAnnotation* = "@no-sad-required"

  # ── Temporal Tiering Configuration ─────────────────────────────────
  EnforcementStartDate* = "2026-06-11"
  EnforcementEndDate* = "2026-06-25"
  BaseRadius* = 20
  TargetRadius* = 100
  OverrideConfigPath* = "config/hardening_override.json"
  AuditLogPath* = "logs/hardening_audit.jsonl"
# ── Break-glass Mechanism ────────────────────────────────────────────

type
  HardeningOverride = object
    overrideRadius: int
    reason: string
    expires: string  # ISO date
    appliedBy: string  # git user or "manual"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readOverrideConfig(path: string): HardeningOverride {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read hardening override config if it exists and is not expired.
  result = HardeningOverride(overrideRadius: -1)  # -1 = no override
  if not fileIo.fileExists(path):
    return
  let content = fileIo.readFile(path)
  if content.len == 0:
    return
  var node: JsonNode
  try:
    node = pureParseJson(content)
  except CatchableError:
    return
  result.overrideRadius = node.getOrDefault("override_radius").getInt(-1)
  result.reason = node.getOrDefault("reason").getStr("")
  result.expires = node.getOrDefault("expires").getStr("")
  result.appliedBy = node.getOrDefault("applied_by").getStr("unknown")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isOverrideActive(override: HardeningOverride): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if override is active (not expired).
  if override.overrideRadius < 0:
    return false
  if override.expires.len == 0:
    return false  # DEBT#298: No expiry = reject (max 24h enforced)
  try:
    let expiryDate = parse(override.expires, "yyyy-MM-dd")
    let today = now()
    let maxExpiry = today + 24.hours
    result = today <= expiryDate and expiryDate <= maxExpiry
  except CatchableError:
    result = false  # Invalid date = treat as expired
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc logHardeningAudit(
  radius: int;
  reason: string;
  appliedBy: string;
  overrideActive: bool
) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append audit record to hardening_audit.jsonl for post-mortem analysis.
  let logDir = AuditLogPath.parentDir
  if not fileIo.dirExists(logDir):
    discard fileIo.createDir(logDir)
  var entry = newJObject()
  entry["timestamp"] = %now().format("yyyy-MM-dd'T'HH:mm:ss")
  entry["radius"] = %radius
  entry["reason"] = %reason
  entry["applied_by"] = %appliedBy
  entry["override_active"] = %overrideActive
  discard fileIo.appendLine(AuditLogPath, $entry)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc calculateEnforcementRadius*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic: same date → same radius.
  ## Linear interpolation from BaseRadius to TargetRadius over period.
  ## Respects break-glass override if active.

  # Check break-glass override first
  let override = readOverrideConfig(OverrideConfigPath)
  if isOverrideActive(override):
    logHardeningAudit(
      override.overrideRadius,
      "Break-glass override: " & override.reason,
      override.appliedBy,
      true
    )
    return override.overrideRadius

  # Temporal tiering: linear interpolation
  let today = now()
  var startDate: DateTime
  var endDate: DateTime
  try:
    startDate = parse(EnforcementStartDate, "yyyy-MM-dd")
    endDate = parse(EnforcementEndDate, "yyyy-MM-dd")
  except CatchableError:
    logHardeningAudit(TargetRadius, "Date parse error — using target radius", "system", false)
    return TargetRadius

  let daysElapsed = (today - startDate).inDays
  let totalDays = (endDate - startDate).inDays

  if totalDays <= 0:
    logHardeningAudit(TargetRadius, "Invalid period — using target radius", "system", false)
    return TargetRadius

  var radius: int
  if daysElapsed >= totalDays:
    radius = TargetRadius  # D-0: full enforcement
  elif daysElapsed <= 0:
    radius = BaseRadius  # Before start: minimum enforcement
  else:
    radius = BaseRadius + (daysElapsed * (TargetRadius - BaseRadius) div totalDays)

  logHardeningAudit(radius, "Temporal tiering — day " & $daysElapsed & "/" & $totalDays, "system", false)
  result = radius
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc formatHardeningNotice*(radius: int; filePath: string = ""): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Format early warning message for CI output.
  let startDate = try: parse(EnforcementStartDate, "yyyy-MM-dd") except CatchableError: now()
  let endDate = try: parse(EnforcementEndDate, "yyyy-MM-dd") except CatchableError: now()
  let today = now()
  let daysLeft = max(0, (endDate - today).inDays)

  if filePath.len > 0:
    result = "[Hardening Notice] Tier " & $radius & "/" & $TargetRadius &
             ": " & filePath & " is in this hardening tier. Please add 1+ assertion."
  else:
    result = "[Hardening Notice] Tier " & $radius & "/" & $TargetRadius &
             ": " & $daysLeft & " days until full enforcement. Current radius: top-" &
             $radius & " modules."
type
  DaysUntilEnforcementError* = ref object of CatchableError
    ## Raised when EnforcementEndDate cannot be parsed (DEBT#298).
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc daysUntilEnforcement*(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Return days until full enforcement (D-0).
  ## Raises DaysUntilEnforcementError on date parse failure.
  var endDate: DateTime
  try:
    endDate = parse(EnforcementEndDate, "yyyy-MM-dd")
  except TimeParseError:
    raise DaysUntilEnforcementError(msg: "Failed to parse EnforcementEndDate: " & EnforcementEndDate)
  let today = now()
  result = max(0, (endDate - today).inDays)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sadScore*(filePath: string): float {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Calculate Semantic Assertion Density (0.0 - 1.0)
  ## SAD = (check + assert + doAssert count) / total non-comment, non-empty lines
  let content = fileIo.readFile(filePath)
  let lines = content.splitLines()
  var assertionCount = 0
  var totalLines = 0
  for line in lines:
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    inc totalLines
    if "check" in stripped or "assert" in stripped or "doAssert" in stripped:
      inc assertionCount
  if totalLines == 0: return 0.0
  result = assertionCount.float / totalLines.float
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isExempt*(filePath: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if file has @no-sad-required annotation in first 10 lines
  let content = fileIo.readFile(filePath)
  let lines = content.splitLines()
  for i in 0 ..< min(10, lines.len):
    if ExemptAnnotation in lines[i]:
      return true
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auditFile*(filePath: string): AuditResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Audit a single test file for SAD compliance
  if not fileIo.fileExists(filePath):
    return arMissing
  if isExempt(filePath):
    return arExempt
  let sad = sadScore(filePath)
  if sad == 0.0:
    return arStub
  result = arPass
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auditChangedFiles*(files: seq[string]; mode: AuditMode = amWarn): tuple[passed: bool, warnings: seq[string], failures: seq[string]] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Audit changed test files for SAD compliance
  ## Returns (passed, warnings, failures)
  result.passed = true
  result.warnings = @[]
  result.failures = @[]
  for f in files:
    if not f.endsWith("_test.nim"):
      continue
    if "tests/legacy/" in f:
      continue  # Skip quarantined files
    let audit = auditFile(f)
    case audit
    of arPass, arExempt:
      discard
    of arStub:
      case mode
      of amWarn:
        result.warnings.add("SAD WARNING: " & f & " has SAD=0.0. This will cause CI failure starting 2026-06-25.")
      of amFail:
        result.failures.add("SAD FAIL: " & f & " is a compilation-only stub (SAD=0.0)")
        result.passed = false
    of arMissing:
      discard  # Handled by separate spec_presence_gate
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auditChangedFilesWithHotspotAwareness*(
  files: seq[string];
 mode: AuditMode = amWarn;
  hotspotTopN: int = 0;  # 0 = auto-calculate from temporal tiering
  hotspotSinceDays: int = 30
): tuple[passed: bool, warnings: seq[string], failures: seq[string]] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Audit changed files with hotspot awareness.
  ## If hotspotTopN = 0, uses dynamic radius from calculateEnforcementRadius().
  ## If a changed file is in the enforcement radius without tests or with low SAD,
  ## the gate escalates to warning or failure.

  # Determine effective radius
  let effectiveTopN = if hotspotTopN > 0: hotspotTopN else: calculateEnforcementRadius()

  # Print hardening notice
  fileIo.writeStderr(formatHardeningNotice(effectiveTopN))

  result = auditChangedFiles(files, mode)
  if effectiveTopN <= 0:
    return

  # Build hotspot queue
  let churn = computeChurnScoresCached(hotspotSinceDays)
  let queue = buildPriorityQueue(churn, effectiveTopN)
  if queue.len == 0:
    return

  for f in files:
    if not f.endsWith(".nim"):
      continue
    if f.startsWith("tests/") or f.startsWith("vendor/"):
      continue

    let name = extractFilename(f).replace(".nim", "")
    var isHot = false
    var entry: HotspotEntry
    for i in 0 ..< min(effectiveTopN, queue.len):
      if queue[i].moduleName == name or queue[i].filePath == f or queue[i].filePath.endsWith("/" & name & ".nim"):
        isHot = true
        entry = queue[i]
        break

    if not isHot:
      continue

    # Print per-file hardening notice
    fileIo.writeStderr(formatHardeningNotice(effectiveTopN, f))

    # Escalation rules for hotspots using context-rich messages
    let msg = formatHotspotContext(entry, hotspotSinceDays)
    if msg.len == 0:
      continue

    if not entry.hasTest:
      if mode == amFail:
        result.failures.add(msg)
        result.passed = false
      else:
        result.warnings.add(msg)
    elif entry.sadScore < 0.05:
      if mode == amFail:
        result.failures.add(msg)
        result.passed = false
      else:
        result.warnings.add(msg)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeBackRegistry*(legacyDir: string = "tests/legacy"; registryPath: string = "docs/history/test-stub-registry.md") {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Auto-generate quarantine registry from tests/legacy/ contents.
  ## This is system-generated state data — do not edit manually.
  var entries: seq[string] = @[]
  if fileIo.dirExists(legacyDir):
    for path in fileIo.walkDirEntries(legacyDir):
      if path.endsWith("_test.nim"):
        entries.add("- " & path.extractFilename())
  entries.sort()
  let timestamp = now().format("yyyy-MM-dd HH:mm")
  let registry = "# Test Stub Quarantine Registry\n" &
    "# Auto-generated by ax test audit — do not edit manually\n" &
    "# Last updated: " & timestamp & "\n\n" &
    "## Quarantined Files (" & $entries.len & ")\n" &
    entries.join("\n") & "\n\n" &
    "## SSOT Authority\n" &
    "AGENTS.md §0.8 (No Stub Files)\n"
  let dir = registryPath.parentDir
  if not fileIo.dirExists(dir):
    discard fileIo.createDir(dir)
  discard fileIo.writeFile(registryPath, registry)
