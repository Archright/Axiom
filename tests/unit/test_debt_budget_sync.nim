## tests/unit/test_debt_budget_sync.nim
##
## Unit tests for debt_engine --sync-budget pipeline:
##   1. golden test — known fixture → expected ledger output
##   2. idempotency test — same fixture run twice → second diff = 0
##   3. determinism test — two runs produce identical byte-for-byte output
##
## All file I/O uses temp directories; real data files are never modified.

import std/[unittest, json, os, strutils, tables]

# ── Helpers to recreate debt_engine types/funcs locally ──────────────

type
  StatusKind* {.pure.} = enum
    stOpen, stClosed

  ResolutionKind* {.pure.} = enum
    rkFIXED, rkWONT_FIX

func isOpen*(status: string): bool {.raises: [].} =
  let low = status.strip().toLowerAscii()
  if "closed" in low: return false
  if "exemption" in low: return false
  if status == "\u2014": return false
  true

proc deriveStatusAndResolution(current, target: int; inverse: bool = false): tuple[status: StatusKind, resolution: ResolutionKind] =
  if inverse:
    if current >= target:
      (status: StatusKind.stClosed, resolution: ResolutionKind.rkFIXED)
    else:
      (status: StatusKind.stOpen, resolution: ResolutionKind.rkWONT_FIX)
  else:
    if current <= target:
      (status: StatusKind.stClosed, resolution: ResolutionKind.rkFIXED)
    else:
      (status: StatusKind.stOpen, resolution: ResolutionKind.rkWONT_FIX)

proc formatStatus(s: StatusKind): string =
  case s
  of StatusKind.stOpen: "open"
  of StatusKind.stClosed: "closed"

proc formatResolution(r: ResolutionKind): string =
  case r
  of ResolutionKind.rkFIXED: "FIXED"
  of ResolutionKind.rkWONT_FIX: "WONT_FIX"

# ── Fixture creation helpers ──────────────────────────────────────────

proc createFixtureDir(): string =
  result = getTempDir() / "debt_budget_test_$$"
  createDir(result)

proc writeRegistryFile(dir: string; openCount, closedCount: int) =
  var entries: seq[string] = @[]
  for i in 1 .. openCount:
    entries.add("{\"id\":\"DEBT#" & $i & "\",\"severity\":\"low\",\"category\":\"test\",\"description\":\"test entry\",\"status\":\"open\"}")
  for i in 1 .. closedCount:
    entries.add("{\"id\":\"DEBT-CI#" & $i & "\",\"severity\":\"low\",\"category\":\"test\",\"description\":\"test entry\",\"status\":\"closed\"}")
  let content = "{\n  \"version\": 3,\n  \"entries\": [" & entries.join(",") & "]\n}"
  writeFile(dir / "debt_registry.json", content)

proc writeLedgerFile(dir: string; budgetData: seq[tuple[id, metric, baseline, target, current, status, resolution: string]]) =
  var records: seq[string] = @[]
  for b in budgetData:
    let rec = "{\n      \"id\": \"" & b.id & "\",\n      \"category\": \"BudgetCategory\",\n      \"description\": \"test budget record\",\n      \"budgetCategory\": \"bcDebtRegistryOpen\",\n      \"metric\": \"" & b.metric & "\",\n      \"baseline\": " & b.baseline & ",\n      \"target\": " & b.target & ",\n      \"current\": " & b.current & ",\n      \"severity\": \"low\",\n      \"source\": \"debt_budgets.json\",\n      \"status\": \"" & b.status & "\",\n      \"resolution\": \"" & b.resolution & "\",\n      \"lastVerifiedAt\": \"2026-08-15T09:51:52Z\"\n    }"
    records.add(rec)
  let content = "{\n  \"version\": \"1.1.0\",\n  \"generated\": \"2026-08-15T09:51:52Z\",\n  \"totalRecords\": " & $budgetData.len & ",\n  \"records\": [" & records.join(",") & "]\n}"
  writeFile(dir / "debt_ledger.json", content)

proc writeBudgetsFile(dir: string) =
  let content = """{
  "version": "v2",
  "baseline_date": "2026-07-27",
  "weekly_reduction_pct": 5.0,
  "description": "Test budgets SSOT",
  "metrics": {
    "debt_registry_open": {
      "baseline": 107,
      "target": 0,
      "description": "open entries in debt_registry.json"
    },
    "debt_registry_closed": {
      "baseline": 0,
      "target": 92,
      "description": "closed entries in debt_registry.json"
    }
  }
}"""
  writeFile(dir / "debt_budgets.json", content)

# ── Sync simulation (mirrors cmdSyncBudget logic) ────────────────────

proc simulateSyncBudget(dir: string; dryRun: bool): tuple[updates: int, skipped: int] =
  let regPath = dir / "debt_registry.json"
  let ledgerPath = dir / "debt_ledger.json"
  let budgetsPath = dir / "debt_budgets.json"

  let budgetsJson = parseJson(readFile(budgetsPath))
  let metricsObj = budgetsJson["metrics"]

  var ledgerJson = parseJson(readFile(ledgerPath))
  var recordsArr = ledgerJson["records"]

  var evalMap: Table[string, proc(): int {.raises: [CatchableError].}] = initTable[string, proc(): int {.raises: [CatchableError].}]()

  evalMap["debt_registry_open"] = proc(): int {.raises: [CatchableError].} =
    let regJson = parseJson(readFile(regPath))
    if regJson{"entries"}.kind != JArray: return 0
    for entry in regJson["entries"]:
      if isOpen(entry{"status"}.getStr()): result += 1

  evalMap["debt_registry_closed"] = proc(): int {.raises: [CatchableError].} =
    let regJson = parseJson(readFile(regPath))
    if regJson{"entries"}.kind != JArray: return 0
    for entry in regJson["entries"]:
      if not isOpen(entry{"status"}.getStr()): result += 1

  var updates = 0
  var skipped = 0

  for idx in 0 ..< recordsArr.len:
    let recNode = recordsArr[idx]
    let recId = recNode["id"].getStr()
    let metricName = recNode["metric"].getStr()
    let target = recNode["target"].getInt()
    let oldCurrent = recNode["current"].getInt()

    let evaluator = evalMap.getOrDefault(metricName)
    if evaluator.isNil:
      inc skipped
      continue

    let newCurrent = evaluator()

    let inverseMetric = metricName == "debt_registry_closed"
    let (newStatus, newResolution) = deriveStatusAndResolution(newCurrent, target, inverseMetric)

    let oldStatus = if recNode["status"].getStr().toLowerAscii() == "closed": StatusKind.stClosed else: StatusKind.stOpen
    let oldResolution = if recNode["resolution"].getStr() == "FIXED": ResolutionKind.rkFIXED else: ResolutionKind.rkWONT_FIX

    if newCurrent == oldCurrent and newStatus == oldStatus and newResolution == oldResolution:
      continue

    inc updates
    recordsArr[idx]["current"] = %newCurrent
    recordsArr[idx]["status"] = %formatStatus(newStatus)
    recordsArr[idx]["resolution"] = %formatResolution(newResolution)

  if not dryRun:
    writeFile(ledgerPath, ledgerJson.pretty())

  result = (updates: updates, skipped: skipped)

# ═══════════════════════════════════════════════════════════════════════
# Test Suite
# ═══════════════════════════════════════════════════════════════════════

suite "debt budget sync - golden test":
  test "registry-derived metrics update ledger correctly":
    let dir = createFixtureDir()
    try:
      writeRegistryFile(dir, 3, 5)
      writeLedgerFile(dir, @[
        ("BUDGET#005", "debt_registry_open", "107", "0", "0", "closed", "FIXED"),
        ("BUDGET#006", "debt_registry_closed", "0", "92", "5", "closed", "FIXED"),
      ])
      writeBudgetsFile(dir)

      let result = simulateSyncBudget(dir, dryRun = false)

      let ledgerJson = parseJson(readFile(dir / "debt_ledger.json"))
      let records = ledgerJson["records"]

      check records[0]["current"].getInt() == 3
      check records[0]["status"].getStr() == "open"
      check records[0]["resolution"].getStr() == "WONT_FIX"

      check records[1]["current"].getInt() == 5
      check records[1]["status"].getStr() == "open"
      check records[1]["resolution"].getStr() == "WONT_FIX"

      check records[0]["lastVerifiedAt"].getStr() == "2026-08-15T09:51:52Z"
      check records[1]["lastVerifiedAt"].getStr() == "2026-08-15T09:51:52Z"

      check result.updates == 2
      check result.skipped == 0
    finally:
      removeDir(dir)

suite "debt budget sync - idempotency test":
  test "second sync produces zero changes":
    let dir = createFixtureDir()
    try:
      writeRegistryFile(dir, 2, 8)
      writeLedgerFile(dir, @[
        ("BUDGET#005", "debt_registry_open", "107", "0", "2", "open", "WONT_FIX"),
        ("BUDGET#006", "debt_registry_closed", "0", "92", "8", "open", "WONT_FIX"),
      ])
      writeBudgetsFile(dir)

      discard simulateSyncBudget(dir, dryRun = false)

      let result2 = simulateSyncBudget(dir, dryRun = false)
      check result2.updates == 0
      check result2.skipped == 0
    finally:
      removeDir(dir)

suite "debt budget sync - determinism test":
  test "two independent runs produce identical ledger output":
    let dir1 = createFixtureDir()
    let dir2 = createFixtureDir()
    try:
      writeRegistryFile(dir1, 4, 6)
      writeRegistryFile(dir2, 4, 6)
      writeLedgerFile(dir1, @[
        ("BUDGET#005", "debt_registry_open", "107", "0", "0", "closed", "FIXED"),
        ("BUDGET#006", "debt_registry_closed", "0", "92", "6", "closed", "FIXED"),
      ])
      writeLedgerFile(dir2, @[
        ("BUDGET#005", "debt_registry_open", "107", "0", "0", "closed", "FIXED"),
        ("BUDGET#006", "debt_registry_closed", "0", "92", "6", "closed", "FIXED"),
      ])
      writeBudgetsFile(dir1)
      writeBudgetsFile(dir2)

      discard simulateSyncBudget(dir1, dryRun = false)
      discard simulateSyncBudget(dir2, dryRun = false)

      let content1 = readFile(dir1 / "debt_ledger.json")
      let content2 = readFile(dir2 / "debt_ledger.json")
      check content1 == content2
    finally:
      removeDir(dir1)
      removeDir(dir2)

suite "debt budget sync - evaluator registry":
  test "unknown metric is skipped":
    let dir = createFixtureDir()
    try:
      writeRegistryFile(dir, 1, 2)
      writeLedgerFile(dir, @[
        ("BUDGET#005", "debt_registry_open", "107", "0", "0", "closed", "FIXED"),
        ("BUDGET#006", "debt_registry_closed", "0", "92", "2", "closed", "FIXED"),
        ("BUDGET#007", "import_lint_violations", "36", "0", "10", "open", "WONT_FIX"),
      ])
      writeBudgetsFile(dir)

      let result = simulateSyncBudget(dir, dryRun = false)
      check result.updates == 2
      check result.skipped == 1
    finally:
      removeDir(dir)

suite "debt budget sync - deriveStatusAndResolution":
  test "normal metric: current <= target → closed/FIXED":
    let (status, res) = deriveStatusAndResolution(0, 0, false)
    check status == StatusKind.stClosed
    check res == ResolutionKind.rkFIXED

  test "normal metric: current > target → open/WONT_FIX":
    let (status, res) = deriveStatusAndResolution(5, 0, false)
    check status == StatusKind.stOpen
    check res == ResolutionKind.rkWONT_FIX

  test "inverse metric: current >= target → closed/FIXED":
    let (status, res) = deriveStatusAndResolution(100, 92, true)
    check status == StatusKind.stClosed
    check res == ResolutionKind.rkFIXED

  test "inverse metric: current < target → open/WONT_FIX":
    let (status, res) = deriveStatusAndResolution(50, 92, true)
    check status == StatusKind.stOpen
    check res == ResolutionKind.rkWONT_FIX
