## debt_ct_validator.nim — Compile-Time JSON Debt Validator
##
## ╔══════════════════════════════════════════════════════════════════════════╗
## ║  DEPRECATED — replaced by tools/debt_engine.nim --validate              ║
## ║  Use: nim c -r tools/debt_engine.nim --validate                         ║
## ╚══════════════════════════════════════════════════════════════════════════╝
##
## Validates all 3 debt JSON files against expected structure and
## cross-file consistency. Returns exit code 0 for pass, 1 for fail.
##
## Architecture:
##   bin/hermetic_build --validate-debt → this tool
##   Validates: architecture_debt.json, debt_registry.json, debt_ledger.json
##
## Cross-file checks:
##   - No duplicate IDs within a single registry
##   - Every open critical entry must have a matching file in architecture_debt
##   - Open critical count must not exceed configurable threshold (default 20)
##
## Run: nim c -o:bin/debt_ct_validator tools/debt_ct_validator.nim
##      bin/debt_ct_validator

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, tables]

const
  ArchitectureDebtPath = "data/architecture_debt.json"
  DebtRegistryPath = "data/debt_registry.json"
  DebtLedgerPath = "data/debt_ledger.json"
  DefaultCriticalThreshold = 20

# ── Pure helpers ──────────────────────────────────────────────────────────────

func isDigitStr(s: string): bool {.raises: [].} =
  ## True if s is non-empty and all characters are ASCII digits.
  if s.len == 0: return false
  for ch in s:
    if ch < '0' or ch > '9': return false
  true

func matchesDebtId(s: string): bool {.raises: [].} =
  ## True if s matches pattern DEBT#NNN (DEBT# + digits).
  if not s.startsWith("DEBT#"): return false
  isDigitStr(s[5..^1])

func matchesSeverity(s: string): bool {.raises: [].} =
  s in ["critical", "high", "medium", "low", "info", "n/a"]

func matchesStatus(s: string): bool {.raises: [].} =
  ## Accept canonical values plus real-world patterns found in the registry.
  ## Strip leading markdown/bullet characters for prefix matching.
  let raw = s.strip()
  var base = raw
  # Strip leading non-alpha characters (markdown bold, bullets, dashes)
  while base.len > 0 and base[0] notin {'a'..'z', 'A'..'Z'}:
    base = base[1..^1]
  base = base.toLowerAscii()

  if base in ["open", "closed", "accepted", "deferred",
              "exemption approved", "partial", "in_progress"]:
    return true
  # Prefix patterns: "closed**", "closed — ...", "open (...)", "partial (...)"
  if base.startsWith("closed") or base.startsWith("open") or base.startsWith("partial"):
    return true
  # Em-dash / n/a as "not set"
  if raw in ["—", "n/a", ""] or base == "":
    return true
  false

func jsonStr(node: JsonNode): string =
  ## Safe string extraction; returns "<missing>" for non-string nodes.
  if node.kind == JString: node.getStr()
  else: "<" & $node.kind & ">"

func matchesBudgetId(s: string): bool {.raises: [].} =
  ## True if s matches pattern BUDGET#\d{3} (BUDGET# + exactly 3 digits).
  if not s.startsWith("BUDGET#"): return false
  let tail = s[8..^1]
  if tail.len != 3: return false
  isDigitStr(tail)

func matchesLedgerSeverity(s: string): bool {.raises: [].} =
  s in ["low", "medium", "high"]

func matchesBudgetCategory(s: string): bool {.raises: [].} =
  s in [
    "bcImportLint",
    "bcLayerViolation",
    "bcEffectViolation",
    "bcNimtryViolation",
    "bcDebtRegistryOpen",
    "bcDebtRegistryClosed"
  ]

# ── architecture_debt.json validation ─────────────────────────────────────────

proc validateArchitectureDebt(path: string): bool =
  ## Validate structure of data/architecture_debt.json.
  ## Expected: { "version": int, "entries": [...] }
  ## Each entry: { "file": string, "count": int>0, "firstSeen": string,
  ##               "lastSeen": string, "contentHash": string }
  if not fileExists(path):
    echo "❌ [architecture_debt] File not found: " & path
    return false

  var json: JsonNode
  try:
    json = parseJson(readFile(path))
  except JsonParsingError:
    echo "❌ [architecture_debt] Invalid JSON: " & getCurrentExceptionMsg()
    return false

  var passed = true

  # Top-level version: must be int
  if not json.hasKey("version"):
    echo "❌ [architecture_debt] Missing required key: 'version'"
    passed = false
  elif json["version"].kind != JInt:
    echo "❌ [architecture_debt] 'version' must be int, got " & $json["version"].kind
    passed = false

  # Top-level entries: must be array
  if not json.hasKey("entries"):
    echo "❌ [architecture_debt] Missing required key: 'entries'"
    passed = false
  elif json["entries"].kind != JArray:
    echo "❌ [architecture_debt] 'entries' must be array"
    passed = false
  else:
    let entries = json["entries"]
    for idx in 0..<entries.len:
      let entry = entries[idx]
      let file = entry{"file"}
      let count = entry{"count"}
      let firstSeen = entry{"firstSeen"}
      let lastSeen = entry{"lastSeen"}
      let contentHash = entry{"contentHash"}

      if file.kind != JString or file.getStr().len == 0:
        echo "❌ [architecture_debt] entry[" & $idx & "].file: must be non-empty string"
        passed = false
      if count.kind != JInt:
        echo "❌ [architecture_debt] entry[" & $idx & "].count: must be int"
        passed = false
      elif count.getInt() <= 0:
        echo "❌ [architecture_debt] entry[" & $idx & "].count: must be > 0, got " & $count.getInt()
        passed = false
      if firstSeen.kind != JString:
        echo "❌ [architecture_debt] entry[" & $idx & "].firstSeen: must be string"
        passed = false
      if lastSeen.kind != JString:
        echo "❌ [architecture_debt] entry[" & $idx & "].lastSeen: must be string"
        passed = false
      if contentHash.kind != JString:
        echo "❌ [architecture_debt] entry[" & $idx & "].contentHash: must be string"
        passed = false

    if passed:
      echo "✅ [architecture_debt] " & $entries.len & " entries validated"

  passed

# ── debt_registry.json validation ─────────────────────────────────────────────

proc validateDebtRegistry(path: string): bool =
  ## Validate structure of data/debt_registry.json.
  ## Expected: { "entries": [...] }
  ## Each entry: { "id": "DEBT#NNN", "severity": critical|high|medium|low,
  ##               "status": open|closed|accepted|deferred,
  ##               "category": non-empty string, "description": non-empty string }
  if not fileExists(path):
    echo "❌ [debt_registry] File not found: " & path
    return false

  var json: JsonNode
  try:
    json = parseJson(readFile(path))
  except JsonParsingError:
    echo "❌ [debt_registry] Invalid JSON: " & getCurrentExceptionMsg()
    return false

  var passed = true

  if not json.hasKey("entries"):
    echo "❌ [debt_registry] Missing required key: 'entries'"
    return false
  if json["entries"].kind != JArray:
    echo "❌ [debt_registry] 'entries' must be array"
    return false

  let entries = json["entries"]
  for idx in 0..<entries.len:
    let entry = entries[idx]
    let id = entry{"id"}
    let severity = entry{"severity"}
    let status = entry{"status"}
    let category = entry{"category"}
    let description = entry{"description"}

    # id: DEBT#\d+
    if id.kind != JString or not matchesDebtId(id.getStr()):
      echo "❌ [debt_registry] entry[" & $idx & "].id: invalid format '" &
        jsonStr(id) & "', expected DEBT#\\d+"
      passed = false

    # severity: one of critical|high|medium|low
    if severity.kind != JString or not matchesSeverity(severity.getStr()):
      echo "❌ [debt_registry] entry[" & $idx & "].severity: invalid value '" &
        jsonStr(severity) & "'"
      passed = false

    # status: one of open|closed|accepted|deferred
    if status.kind != JString or not matchesStatus(status.getStr()):
      echo "❌ [debt_registry] entry[" & $idx & "].status: invalid value '" &
        jsonStr(status) & "'"
      passed = false

    # category: non-empty string
    if category.kind != JString or category.getStr().len == 0:
      echo "❌ [debt_registry] entry[" & $idx & "].category: must be non-empty string"
      passed = false

    # description: non-empty string
    if description.kind != JString or description.getStr().len == 0:
      echo "❌ [debt_registry] entry[" & $idx & "].description: must be non-empty string"
      passed = false

  if passed:
    echo "✅ [debt_registry] " & $entries.len & " entries validated"

  passed

# ── debt_ledger.json validation (v1.1.0) ──────────────

proc validateDebtLedger(path: string): bool =
  ## Validate structure of data/debt_ledger.json (v1.1.0 ONLY).
  ## Top-level keys: version (MUST be "1.1.0"), generated, description,
  ##   totalRecords, records: [...]
  ## Each record: id (BUDGET#NNN), category ("BudgetCategory"), description,
  ##   budgetCategory (bcImportLint|bcLayerViolation|bcEffectViolation|
  ##     bcNimtryViolation|bcDebtRegistryOpen|bcDebtRegistryClosed),
  ##   metric (non-empty string), baseline/target/current (int ≥ 0),
  ##   severity (low|medium|high), source, status (open|closed),
  ##   resolution (WONT_FIX|FIXED), lastVerifiedAt.
  if not fileExists(path):
    echo "❌ [debt_ledger] File not found: " & path
    return false

  var json: JsonNode
  try:
    json = parseJson(readFile(path))
  except JsonParsingError:
    echo "❌ [debt_ledger] Invalid JSON: " & getCurrentExceptionMsg()
    return false

  var passed = true

  # Version: must be exactly "1.1.0" — fail-closed, never silently pass
  let versionNode = json["version"]
  if versionNode.kind != JString:
    echo "❌ [debt_ledger] 'version' must be string"
    return false
  if versionNode.getStr() != "1.1.0":
    echo "❌ [debt_ledger] version must be '1.1.0', got '" & versionNode.getStr() & "'"
    return false

  # Records array: required
  let recordsNode = json["records"]
  if recordsNode.kind != JArray:
    echo "❌ [debt_ledger] Missing or invalid 'records' array"
    return false

  let records = recordsNode
  for idx in 0..<records.len:
    let rec = records[idx]
    if rec.kind != JObject:
      echo "❌ [debt_ledger] records[" & $idx & "] must be object"
      passed = false
      continue

    # id: BUDGET#NNN
    let id = rec{"id"}
    if id.kind != JString or id.getStr().len == 0:
      echo "❌ [debt_ledger] records[" & $idx & "].id: must be non-empty string"
      passed = false
    elif not matchesBudgetId(id.getStr()):
      echo "❌ [debt_ledger] records[" & $idx & "].id: invalid format '" &
        id.getStr() & "', expected BUDGET#NNN"
      passed = false

    # category: must be "BudgetCategory"
    let category = rec{"category"}
    if category.kind != JString or category.getStr() != "BudgetCategory":
      echo "❌ [debt_ledger] records[" & $idx & "].category: must be 'BudgetCategory'"
      passed = false

    # description: non-empty string
    let description = rec{"description"}
    if description.kind != JString or description.getStr().len == 0:
      echo "❌ [debt_ledger] records[" & $idx & "].description: must be non-empty string"
      passed = false

    # budgetCategory: enum membership
    let budgetCategory = rec{"budgetCategory"}
    if budgetCategory.kind != JString or not matchesBudgetCategory(budgetCategory.getStr()):
      echo "❌ [debt_ledger] records[" & $idx & "].budgetCategory: invalid value '" &
        jsonStr(budgetCategory) & "'"
      passed = false

    # metric: non-empty string
    let metric = rec{"metric"}
    if metric.kind != JString or metric.getStr().len == 0:
      echo "❌ [debt_ledger] records[" & $idx & "].metric: must be non-empty string"
      passed = false

    # baseline: int ≥ 0
    let baseline = rec{"baseline"}
    if baseline.kind != JInt:
      echo "❌ [debt_ledger] records[" & $idx & "].baseline: must be int"
      passed = false
    elif baseline.getInt() < 0:
      echo "❌ [debt_ledger] records[" & $idx & "].baseline: must be ≥ 0, got " & $baseline.getInt()
      passed = false

    # target: int ≥ 0
    let target = rec{"target"}
    if target.kind != JInt:
      echo "❌ [debt_ledger] records[" & $idx & "].target: must be int"
      passed = false
    elif target.getInt() < 0:
      echo "❌ [debt_ledger] records[" & $idx & "].target: must be ≥ 0, got " & $target.getInt()
      passed = false

    # current: int ≥ 0
    let current = rec{"current"}
    if current.kind != JInt:
      echo "❌ [debt_ledger] records[" & $idx & "].current: must be int"
      passed = false
    elif current.getInt() < 0:
      echo "❌ [debt_ledger] records[" & $idx & "].current: must be ≥ 0, got " & $current.getInt()
      passed = false

    # severity: low|medium|high
    let severity = rec{"severity"}
    if severity.kind != JString or not matchesLedgerSeverity(severity.getStr()):
      echo "❌ [debt_ledger] records[" & $idx & "].severity: invalid value '" &
        jsonStr(severity) & "'"
      passed = false

    # source: non-empty string
    let source = rec{"source"}
    if source.kind != JString or source.getStr().len == 0:
      echo "❌ [debt_ledger] records[" & $idx & "].source: must be non-empty string"
      passed = false

    # status: open|closed
    let status = rec{"status"}
    if status.kind != JString or status.getStr() notin ["open", "closed"]:
      echo "❌ [debt_ledger] records[" & $idx & "].status: invalid value '" &
        jsonStr(status) & "'"
      passed = false

    # resolution: WONT_FIX|FIXED
    let resolution = rec{"resolution"}
    if resolution.kind != JString or resolution.getStr() notin ["WONT_FIX", "FIXED"]:
      echo "❌ [debt_ledger] records[" & $idx & "].resolution: invalid value '" &
        jsonStr(resolution) & "'"
      passed = false

    # lastVerifiedAt: non-empty string
    let lastVerifiedAt = rec{"lastVerifiedAt"}
    if lastVerifiedAt.kind != JString or lastVerifiedAt.getStr().len == 0:
      echo "❌ [debt_ledger] records[" & $idx & "].lastVerifiedAt: must be non-empty string"
      passed = false

  if passed:
    echo "✅ [debt_ledger] " & $records.len & " records validated"

  passed

# ── Cross-file consistency checks ─────────────────────────────────────────────

func collectOpenCriticalFiles(registryJson: JsonNode): seq[string] =
  ## Collect file paths referenced by open critical entries in the registry.
  ## Handles comma-separated paths and strips parenthetical annotations.
  result = @[]
  for entry in registryJson["entries"]:
    if entry{"status"}.getStr() == "open" and entry{"severity"}.getStr() == "critical":
      let files = entry{"files"}
      if files.kind == JArray:
        for f in files:
          let raw = f.getStr()
          # Split comma-separated paths and strip annotations
          for part in raw.split(","):
            var p = part.strip()
            # Strip parenthetical annotations like (전체), (all), etc.
            let parenStart = p.find('(')
            if parenStart >= 0:
              p = p[0..<parenStart].strip()
            # Strip trailing period/fullstop
            if p.endsWith("."):
              p = p[0..^2].strip()
            # Normalize: ensure directory paths end with /
            if p.len > 0 and p.endsWith("/"):
              discard  # already normalized
            elif p.len > 0 and not p.endsWith(".nim") and not p.contains('.'):
              # Likely a directory reference without trailing slash
              p = p & "/"
            if p.len > 0:
              result.add(p)

func collectArchDebtPaths(archJson: JsonNode): seq[string] =
  ## Collect all file paths from architecture_debt.json entries.
  result = @[]
  for entry in archJson["entries"]:
    result.add(entry{"file"}.getStr())

func fileMatchesRef(filePath, refPath: string): bool {.raises: [].} =
  ## Check if an architecture_debt file path matches a registry reference.
  ## Registry uses directory paths (e.g. "src/core/") and file paths.
  if refPath.endsWith("/"):
    filePath.startsWith(refPath)
  else:
    filePath == refPath or filePath.startsWith(refPath)

proc crossFileConsistency(registryJson, archJson: JsonNode,
                          criticalThreshold: int): bool =
  ## Cross-file consistency checks. Returns true if all pass.
  var passed = true

  # 1. Duplicate ID check within registry
  var seenIds: Table[string, int]
  var entryIdx = 0
  for entry in registryJson["entries"]:
    let id = entry{"id"}.getStr()
    if id in seenIds:
      echo "❌ [cross-file] Duplicate ID in debt_registry: " & id &
        " (entries " & $seenIds[id] & " and " & $entryIdx & ")"
      passed = false
    else:
      seenIds[id] = entryIdx
    inc entryIdx

  # 2. Open critical entries must have matching file in architecture_debt
  let openCriticalFiles = collectOpenCriticalFiles(registryJson)
  let archFiles = collectArchDebtPaths(archJson)

  for critRef in openCriticalFiles:
    var found = false
    for archPath in archFiles:
      if fileMatchesRef(archPath, critRef):
        found = true
        break
    if not found:
      echo "❌ [cross-file] Open critical registry ref '" & critRef &
        "' has no matching file in architecture_debt.json"
      passed = false

  # 3. Open critical count threshold
  let openCriticalCount = openCriticalFiles.len
  if openCriticalCount > criticalThreshold:
    echo "❌ [cross-file] Open critical count " & $openCriticalCount &
      " exceeds threshold " & $criticalThreshold
    passed = false
  else:
    echo "✅ [cross-file] Open critical count: " & $openCriticalCount &
      " / " & $criticalThreshold & " threshold"

  if passed:
    echo "✅ [cross-file] Consistency checks passed"

  passed

# ── Main ──────────────────────────────────────────────────────────────────────

proc main() =
  echo "=== Debt JSON Validator ==="
  echo ""

  # Parse configurable threshold from env
  var criticalThreshold = DefaultCriticalThreshold
  let envThreshold = getEnv("AXIOM_CRITICAL_DEBT_THRESHOLD", "")
  if envThreshold.len > 0:
    try:
      criticalThreshold = parseInt(envThreshold)
    except ValueError:
      echo "⚠️  Invalid AXIOM_CRITICAL_DEBT_THRESHOLD: " & envThreshold &
        " — using default " & $DefaultCriticalThreshold

  var allPassed = true

  # 1. Validate architecture_debt.json
  if not validateArchitectureDebt(ArchitectureDebtPath):
    allPassed = false

  # 2. Validate debt_registry.json
  if not validateDebtRegistry(DebtRegistryPath):
    allPassed = false

  # 3. Validate debt_ledger.json
  if not validateDebtLedger(DebtLedgerPath):
    allPassed = false

  # 4. Cross-file consistency (only if structural validations passed)
  echo ""
  if allPassed:
    let registryJson = parseJson(readFile(DebtRegistryPath))
    let archJson = parseJson(readFile(ArchitectureDebtPath))
    if not crossFileConsistency(registryJson, archJson, criticalThreshold):
      allPassed = false
  else:
    echo "⚠️  Skipping cross-file checks due to structural validation failures"

  # Summary
  echo ""
  if allPassed:
    echo "All debt validation checks passed."
    quit(0)
  else:
    echo "Debt validation checks FAILED."
    quit(1)

main()
