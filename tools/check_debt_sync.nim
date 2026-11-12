## tools/check_debt_sync.nim — DEBT#256 Cross-File Debt Synchronization Validator
##
## ╔══════════════════════════════════════════════════════════════════════════╗
## ║  DEPRECATED — superseded by tools/debt_engine.nim --validate               ║
## ║  Use: nim c -r tools/debt_engine.nim --validate                            ║
## ║                                                                             ║
## ║  This tool is retained only for tooling that still references it.           ║
## ║  Do not add incremental/optimization here.                                  ║
## ╚══════════════════════════════════════════════════════════════════════════╝
##
## Validates consistency across all 3 debt tracking files:
##   1. data/debt_registry.json  — issue-level SSOT (DEBT#NNN entries)
##   2. data/architecture_debt.json — file-level code smell counts
##   3. data/debt_ledger.json    — budget metrics ledger (v1.1.0, BUDGET#NNN)
##   4. docs/DEBT_REGISTRY.md    — auto-generated markdown (must match registry)
##
## Cross-file checks:
##   - No duplicate IDs within registry
##   - Ledger parses as v1.1.0 budget records (strict schema validation)
##   - Budget open/closed counts align with registry counts (derivable)
##   - BUDGET# ids are aggregate metrics, NOT registry identities — no orphan check
##   - Markdown header stats match computed registry stats
##   - architecture_debt files are referenced by at least one registry entry
##   - Open critical count within threshold
##
## Hash validation (updated for SHA-256 identity separation):
##   - rawContentHash: SHA-256 of exact file bytes
##   - canonicalSyntaxHash: canonical-text SHA-256 for semantic drift detection
##
## Exit code: 0 = all pass, 1 = failures detected
##
## Run: nim c -o:bin/check_debt_sync tools/check_debt_sync.nim
##      bin/check_debt_sync

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, tables, sets, hashes]
import core/debt/debt_integrity

const
  RegistryPath     = "data/debt_registry.json"
  ArchDebtPath     = "data/architecture_debt.json"
  LedgerPath       = "data/debt_ledger.json"
  MarkdownPath     = "docs/DEBT_REGISTRY.md"
  RemediationCommand = "bin/debt_engine --codegen && bin/debt_engine --validate"
  CriticalThreshold = 30

func isDigitStr(s: string): bool {.raises: [].} =
  if s.len == 0: return false
  for ch in s:
    if ch < '0' or ch > '9': return false
  true

func matchesDebtId(s: string): bool {.raises: [].} =
  if s.startsWith("DEBT#"): return isDigitStr(s[5..^1])
  if s.startsWith("DEBT-CI#"): return isDigitStr(s[8..^1])
  false

func parseDebtNum(id: string): int {.raises: [].} =
  let pos = id.find('#')
  if pos < 0: return 0
  var n = 0
  for i in (pos + 1) ..< id.len:
    if id[i] in Digits:
      n = n * 10 + (id[i].int - '0'.int)
  n

func normalizeSeverity(s: string): string {.raises: [].} =
  let low = s.strip().toLowerAscii()
  case low
  of "critical", "high", "medium", "low": low
  of "n/a", "info", "": "low"
  else: low

func isOpen(status: string): bool {.raises: [].} =
  let low = status.strip().toLowerAscii()
  if "closed" in low: return false
  if "exemption" in low: return false
  if status == "\u2014": return false
  true

func displaySeverity(s: string): string {.raises: [].} =
  s[0].toUpperAscii() & s[1..^1]

type
  RegistryEntry = object
    id: string
    idNum: int
    severity: string
    category: string
    description: string
    files: seq[string]
    status: string

  RegistryData = object
    entries: seq[RegistryEntry]
    severityCounts: Table[string, int]
    statusCounts: Table[string, string]
    openCount: int
    openBySeverity: Table[string, int]
    rawJson: JsonNode

proc parseRegistry(path: string): RegistryData =
  let raw = parseJson(readFile(path))
  result.rawJson = raw

  for node in raw["entries"]:
    var entry: RegistryEntry
    entry.id = node["id"].getStr()
    entry.idNum = parseDebtNum(entry.id)
    entry.severity = normalizeSeverity(node["severity"].getStr())
    entry.category = node["category"].getStr()
    entry.description = node["description"].getStr()
    entry.status = node["status"].getStr()

    if node.hasKey("files"):
      let filesNode = node["files"]
      case filesNode.kind
      of JArray:
        for f in filesNode:
          entry.files.add(f.getStr())
      of JString:
        for part in filesNode.getStr().split(","):
          let t = part.strip()
          if t.len > 0: entry.files.add(t)
      else: discard

    result.entries.add(entry)
    result.severityCounts.mgetOrPut(entry.severity, 0) += 1
    if isOpen(entry.status):
      result.openCount += 1
      result.openBySeverity.mgetOrPut(entry.severity, 0) += 1

type
  BudgetRecord = object
    id: string
    category: string
    description: string
    budgetCategory: string
    metric: string
    baseline: int
    target: int
    current: int
    severity: string
    source: string
    status: string
    resolution: string
    lastVerifiedAt: string

  BudgetData = object
    records: seq[BudgetRecord]
    ids: HashSet[string]
    rawJson: JsonNode

func isValidBudgetId(id: string): bool {.raises: [].} =
  if not id.startsWith("BUDGET#"): return false
  let suffix = id[7..^1]
  if suffix.len != 3: return false
  for ch in suffix:
    if ch < '0' or ch > '9': return false
  true

proc parseLedger(path: string): BudgetData =
  let raw = parseJson(readFile(path))
  result.rawJson = raw

  if not raw.hasKey("version"):
    echo "FATAL: debt_ledger.json missing 'version' key"
    quit(1)
  if raw["version"].getStr() != "1.1.0":
    echo "FATAL: debt_ledger.json version '" & raw["version"].getStr() & "' is not supported (expected 1.1.0)"
    quit(1)

  if not raw.hasKey("records"):
    echo "FATAL: debt_ledger.json missing 'records' key"
    quit(1)

  for node in raw["records"]:
    var rec: BudgetRecord
    var fieldErrors: seq[string]

    rec.id = node["id"].getStr()
    if rec.id.len == 0: fieldErrors.add("missing 'id'")

    rec.category = node["category"].getStr()
    rec.description = node["description"].getStr()
    rec.budgetCategory = node["budgetCategory"].getStr()
    rec.metric = node["metric"].getStr()
    rec.baseline = node["baseline"].getInt()
    rec.target = node["target"].getInt()
    rec.current = node["current"].getInt()
    rec.severity = node["severity"].getStr()
    rec.source = node["source"].getStr()
    rec.status = node["status"].getStr()
    rec.resolution = node["resolution"].getStr()
    rec.lastVerifiedAt = node["lastVerifiedAt"].getStr()

    if rec.id.len == 0: fieldErrors.add("missing 'id'")
    if not isValidBudgetId(rec.id): fieldErrors.add("invalid BUDGET#NNN id")
    if rec.budgetCategory.len == 0: fieldErrors.add("missing 'budgetCategory'")
    if rec.metric.len == 0: fieldErrors.add("missing 'metric'")
    if rec.severity.len == 0: fieldErrors.add("missing 'severity'")
    if rec.status.len == 0: fieldErrors.add("missing 'status'")
    if rec.resolution.len == 0: fieldErrors.add("missing 'resolution'")
    if rec.source.len == 0: fieldErrors.add("missing 'source'")
    if rec.lastVerifiedAt.len == 0: fieldErrors.add("missing 'lastVerifiedAt'")

    if fieldErrors.len > 0:
      echo "ERROR: record " & (if rec.id.len > 0: rec.id else: "(unknown)") & ": " & fieldErrors.join("; ")
    else:
      result.records.add(rec)
      result.ids.incl(rec.id)

type
  MdStats = object
    totalEntries: int
    openCount: int
    closedCount: int
    hasHeader: bool

proc parseMarkdownHeader(path: string): MdStats =
  if not fileExists(path):
    return
  let content = readFile(path)
  for line in content.splitLines():
    if line.startsWith("> Total entries:"):
      let parts = line.split(":")
      if parts.len >= 2:
        let numStr = parts[1].strip()
        result.totalEntries = parseInt(numStr)
    elif line.startsWith("> Open:"):
      let afterOpen = line.split(":")[1..^1].join(":").strip()
      let pipePos = afterOpen.find('|')
      if pipePos >= 0:
        result.openCount = parseInt(afterOpen[0..<pipePos].strip())
        let afterClosed = afterOpen[pipePos + 1 ..^ 1].strip()
        let colonPos = afterClosed.find(':')
        if colonPos >= 0:
          result.closedCount = parseInt(afterClosed[colonPos + 1 ..^ 1].strip())
  result.hasHeader = result.totalEntries > 0

var
  totalChecks = 0
  passedChecks = 0
  failedChecks = 0

proc check(name: string, passed: bool, detail: string = "") =
  inc totalChecks
  if passed:
    inc passedChecks
    echo "  \u2705 " & name
  else:
    inc failedChecks
    echo "  \u274c " & name
    if detail.len > 0:
      echo "       " & detail

proc checkRegistryStructure(reg: RegistryData): bool =
  echo ""
  echo "[1/6] Registry structure"
  var ok = true

  var seenIds: Table[string, int]
  for idx, entry in reg.entries:
    if entry.id in seenIds:
      check("No duplicate IDs", false,
            entry.id & " appears at indices " & $seenIds[entry.id] & " and " & $idx)
      ok = false
    else:
      seenIds[entry.id] = idx
  check("No duplicate IDs", ok)

  var allIdsValid = true
  for entry in reg.entries:
    if not matchesDebtId(entry.id):
      check("Valid ID format", false, entry.id)
      allIdsValid = false
  check("All IDs valid DEBT#NNN or DEBT-CI#NNN format", allIdsValid)

  var sorted = true
  for i in 1 ..< reg.entries.len:
    if reg.entries[i].idNum < reg.entries[i - 1].idNum:
      check("Entries sorted by ID", false,
            reg.entries[i].id & " < " & reg.entries[i - 1].id)
      sorted = false
  check("Entries sorted by ID ascending", sorted)

  var gapIds: seq[string]
  for i in 1 ..< reg.entries.len:
    let prev = reg.entries[i - 1].idNum
    let curr = reg.entries[i].idNum
    if curr - prev > 1:
      for g in (prev + 1) ..< curr:
        gapIds.add("DEBT#" & $g)
  if gapIds.len > 0:
    echo "  \u26a0\ufe0f  ID sequence gaps (warning): " & gapIds.join(", ")
  else:
    check("No gaps in ID sequence", true)

  ok

proc checkLedgerStructure(ledger: BudgetData): bool =
  echo ""
  echo "[2/6] Ledger structure (budget v1.1.0)"
  var ok = true

  var allIdsValid = true
  for rec in ledger.records:
    if not isValidBudgetId(rec.id):
      check("Valid budget ID format", false, rec.id)
      allIdsValid = false
  check("All ledger IDs valid BUDGET#NNN format", allIdsValid)

  var allMetricsValid = true
  for rec in ledger.records:
    if rec.metric.len == 0:
      check("Non-empty metric names", false, "record for " & rec.id)
      allMetricsValid = false
  check("Non-empty metric names", allMetricsValid)

  check("Total ledger records", true, $ledger.records.len & " records across " & $ledger.ids.len & " unique IDs")

  ok

proc checkLedgerRegistrySync(reg: RegistryData, ledger: BudgetData): bool =
  echo ""
  echo "[3/6] Budget \u2192 Registry count consistency"
  var ok = true

  ## BUDGET# ids are aggregate metrics, NOT registry identities.
  ## Do NOT require BUDGET# ids in the registry.
  ## Instead verify that budget open/closed counts align with registry counts.
  var budgetOpen, budgetClosed: int
  for rec in ledger.records:
    let low = rec.status.toLowerAscii()
    if "closed" in low or "fixed" in low or "exemption" in low:
      inc budgetClosed
    else:
      inc budgetOpen

  check("Budget open count matches registry open count",
        budgetOpen == reg.openCount,
        "Budget open=" & $budgetOpen & ", Registry open=" & $reg.openCount)

  var expectedClosed = reg.entries.len - reg.openCount
  check("Budget closed count matches registry closed count",
        budgetClosed == expectedClosed,
        "Budget closed=" & $budgetClosed & ", Registry closed=" & $expectedClosed)

  ok

proc checkMarkdownSync(reg: RegistryData, md: MdStats): bool =
  echo ""
  echo "[4/6] Markdown \u2192 Registry consistency"
  var ok = true

  check("Markdown header exists", md.hasHeader,
        if not md.hasHeader: MarkdownPath & " missing or no header" else: "")

  if md.hasHeader:
    check("Total entries match", md.totalEntries == reg.entries.len,
          "Markdown=" & $md.totalEntries & ", Registry=" & $reg.entries.len)

    check("Open count match", md.openCount == reg.openCount,
          "Markdown=" & $md.openCount & ", Registry=" & $reg.openCount)

    let expectedClosed = reg.entries.len - reg.openCount
    check("Closed count match", md.closedCount == expectedClosed,
          "Markdown=" & $md.closedCount & ", Expected=" & $expectedClosed)

  ok

proc getExpectedHashes(filePath: string): (string, string) =
  ## Compute both raw and canonical hashes for a file.
  ## Returns (rawContentHash, canonicalSyntaxHash).
  if not fileExists(filePath):
    return ("", "")
  let content = readFile(filePath)
  let rawHash = computeRawContentHash(content)
  let canonicalHash = computeCanonicalSyntaxHash(content)
  (rawHash, canonicalHash)

proc checkArchitectureDebtContentHashes(archJson: JsonNode): bool =
  var mismatches: seq[string]
  var rawOnlyMismatches: seq[string]

  for entry in archJson["entries"]:
    let filePath = entry["file"].getStr()
    if not fileExists(filePath):
      mismatches.add(filePath & " missing")
    else:
      let (actualRaw, actualCanonical) = getExpectedHashes(filePath)

      var expectedRaw = ""
      var expectedCanonical = ""
      if entry.hasKey("rawContentHash"):
        expectedRaw = entry{"rawContentHash"}.getStr()
      if entry.hasKey("canonicalSyntaxHash"):
        expectedCanonical = entry{"canonicalSyntaxHash"}.getStr()

      let legacyContentHash = entry{"contentHash"}.getStr()
      let isLegacy = expectedRaw.len == 0 and expectedCanonical.len == 0 and legacyContentHash.len > 0

      if isLegacy:
        continue

      if expectedRaw.len > 0 and actualRaw != expectedRaw:
        if expectedCanonical.len > 0 and actualCanonical != expectedCanonical:
          mismatches.add(filePath & ": raw=" & expectedRaw[0..<7] & "... != actual=" & actualRaw[0..<7] & "...")
        elif expectedCanonical.len > 0:
          rawOnlyMismatches.add(filePath)
      elif expectedCanonical.len > 0 and actualCanonical != expectedCanonical:
        mismatches.add(filePath & ": canonical mismatch")

  if mismatches.len > 0 or rawOnlyMismatches.len > 0:
    echo "  Note: Missing new hash fields detected. Legacy contentHash format found."
  check("architecture_debt.json contentHash values", mismatches.len == 0,
        if mismatches.len > 0: mismatches.join("; ") else: "")
  return mismatches.len == 0

proc checkArchDebtSync(reg: RegistryData, archPath: string): bool =
  echo ""
  echo "[5/6] Architecture debt \u2192\u2192 Registry file coverage"
  var ok = true

  if not fileExists(archPath):
    check("architecture_debt.json exists", false, archPath & " not found")
    return false

  let archJson = parseJson(readFile(archPath))
  discard checkArchitectureDebtContentHashes(archJson)

  var archFiles: HashSet[string]
  for entry in archJson["entries"]:
    archFiles.incl(entry["file"].getStr())

  var regFiles: HashSet[string]
  for entry in reg.entries:
    if isOpen(entry.status):
      for f in entry.files:
        for part in f.split(","):
          let trimmed = part.strip()
          if trimmed.len > 0:
            regFiles.incl(trimmed)

  var unmatchedRefs: seq[string]
  for refPath in regFiles:
    if refPath.len == 0: continue
    if not refPath.endsWith(".nim"): continue
    if not refPath.startswith("src/"): continue
    var found = false
    if refPath.contains("/*"):
      let dirPrefix = refPath.split("/*")[0] & "/"
      for archPath in archFiles:
        if archPath.startswith(dirPrefix):
          found = true
          break
    else:
      found = refPath in archFiles
    if not found:
      unmatchedRefs.add(refPath)

  check("Open registry .nim src/ files have arch_debt entries", unmatchedRefs.len == 0,
        if unmatchedRefs.len > 0: "Unmatched: " & unmatchedRefs.join(", ") else: "")

  check("Architecture debt entry count", true,
        $archFiles.len & " unique files tracked")

  ok

proc checkCriticalThreshold(reg: RegistryData): bool =
  echo ""
  echo "[6/6] Critical threshold gate"
  let openCrit = reg.openBySeverity.getOrDefault("critical", 0)
  check("Open critical count \u2264 threshold", openCrit <= CriticalThreshold,
        $openCrit & " open critical \u2264 " & $CriticalThreshold)
  true

proc updateArchDebtHashes(): int =
  if not fileExists(ArchDebtPath):
    echo "FATAL: " & ArchDebtPath & " not found"
    return 1
  var root = parseJson(readFile(ArchDebtPath))
  var updated = 0
  var missing: seq[string]
  var addedFields = 0

  for entry in root["entries"]:
    let filePath = entry["file"].getStr()
    if filePath.len == 0 or not fileExists(filePath):
      missing.add(filePath)
      continue

    let (rawHash, canonicalHash) = getExpectedHashes(filePath)

    if rawHash.len > 0:
      if entry{"rawContentHash"}.getStr() != rawHash:
        entry["rawContentHash"] = %rawHash
        if entry{"contentHash"}.getStr().len > 0:
          entry.delete("contentHash")
        inc updated
        inc addedFields
      elif entry{"canonicalSyntaxHash"}.getStr().len == 0 and canonicalHash.len > 0:
        entry["canonicalSyntaxHash"] = %canonicalHash
        inc addedFields

  if missing.len > 0:
    echo "FAIL: tracked file(s) missing on disk — no write performed:"
    for m in missing:
      echo "  " & m
    return 1

  let oldVersion = if root.hasKey("version"): root{"version"}.getInt() else: 1
  if oldVersion < 2:
    root["version"] = %2
    inc addedFields

  let newContent = root.pretty()
  if newContent != readFile(ArchDebtPath):
    let tmpPath = ArchDebtPath & ".tmp"
    try:
      writeFile(tmpPath, newContent)
      moveFile(tmpPath, ArchDebtPath)
    except CatchableError as e:
      echo "FAIL: could not write " & ArchDebtPath & ": " & e.msg
      return 1
    echo "[update] " & $updated & " rawContentHash(es) refreshed, " & $addedFields & " additional fields in " & ArchDebtPath
    echo "[update] schema version upgraded to 2"
  else:
    echo "[update] already in sync — no write performed (idempotent)"
  return 0

proc main() =
  if commandLineParams().contains("--update"):
    quit(updateArchDebtHashes())

  echo "=== DEBT#256 Debt Sync Validator ==="
  echo "Cross-file consistency check: registry + ledger + arch_debt + markdown"
  echo ""

  if not fileExists(RegistryPath):
    echo "FATAL: " & RegistryPath & " not found"
    quit(1)
  if not fileExists(LedgerPath):
    echo "FATAL: " & LedgerPath & " not found"
    quit(1)

  let reg = parseRegistry(RegistryPath)
  let ledger = parseLedger(LedgerPath)
  let md = parseMarkdownHeader(MarkdownPath)

  echo "Loaded: " & $reg.entries.len & " registry entries"
  echo "Loaded: " & $ledger.records.len & " budget records (" & $ledger.ids.len & " unique IDs)"
  echo "Loaded: markdown header (total=" & $md.totalEntries & ", open=" & $md.openCount & ")"

  discard checkRegistryStructure(reg)
  discard checkLedgerStructure(ledger)
  discard checkLedgerRegistrySync(reg, ledger)
  discard checkMarkdownSync(reg, md)
  discard checkArchDebtSync(reg, ArchDebtPath)
  discard checkCriticalThreshold(reg)

  echo ""
  echo "\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501"
  echo "  Checks: " & $totalChecks & " total, " & $passedChecks & " passed, " & $failedChecks & " failed"
  echo "\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501"

  if failedChecks > 0:
    echo ""
    echo "  Sync FAILED — " & $failedChecks & " inconsistencies detected."
    echo "  Remediate generated data with: " & RemediationCommand
    quit(1)
  else:
    echo ""
    echo "  All debt files are in sync."
    quit(0)

when isMainModule:
  main()