## tests/unit/test_debt_engine_sync_budget.nim
##
## End-to-end CLI contract for `bin/debt_engine --sync-budget` (DEBT#543):
##   1. happy path — every ledger metric has a runnable evaluator; the sync
##      measures, writes the ledger, and exits 0 with "Sync complete.".
##   2. idempotency — a second run on the synced fixture reports 0 updates.
##   3. fail-closed (missing evaluator dependency) — a budget record whose
##      evaluator binary is absent (nimtry_violations without bin/nimtry) is
##      skipped, the sync reports INCOMPLETE and exits 1, measured records
##      still land in the ledger, and the unmeasured record keeps its last
##      verified value — never a fabricated current.
##   4. fail-closed (no evaluator registered) — a ledger record whose metric
##      has no evaluator in the registry also fails closed (exit 1).
##
## Mirrors the harness shape of hermetic_source_hash_gate_test.nim: the tool is
## compiled from the live working tree into an isolated scratch binary and run
## against sandbox fixtures via workingDir (debt_engine resolves all data
## paths relative to CWD).

import std/[unittest, os, osproc, strutils, json, times]

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  raise newException(IOError, ".axiom_root not found from " & getCurrentDir())

proc ensureDebtEngineBin(repoRoot, scratchDir: string): string =
  ## Compile tools/debt_engine.nim from the live working tree into an
  ## isolated test binary so the suite always exercises the current source
  ## even when invoked under `AXIOM_HERMETIC_BUILDING=1` (`make test-fast`).
  let outBin = scratchDir / "debt_engine_under_test"
  let nimCache = scratchDir / "nimcache_de"
  let srcPath = repoRoot / "tools" / "debt_engine.nim"
  let cmd = "AXIOM_HERMETIC_BUILDING=1 nim c --hints:off --warnings:off " &
            "--nimcache:" & quoteShell(nimCache) & " " &
            "-o:" & quoteShell(outBin) & " " & quoteShell(srcPath)
  let (output, rc) = execCmdEx(cmd, workingDir = repoRoot)
  if rc != 0:
    raise newException(IOError,
      "failed to compile tools/debt_engine.nim (rc=" & $rc & "):\n" & output)
  result = outBin

type
  LedgerRec = tuple
    id, metric, baseline, target, current, status, resolution: string

proc writeSandbox(sandboxBase, tag: string; ledgerRecs: seq[LedgerRec]): string =
  ## Sandbox with data/{debt_registry,debt_budgets,debt_ledger}.json.
  ## Registry carries 3 open + 5 closed entries; budgets declare only the
  ## two in-process registry metrics, so the happy path needs no sibling
  ## binaries. Sandbox has no bin/ and no tools/ — subprocess evaluators
  ## deterministically report "binary unavailable" there.
  let sandboxRoot = sandboxBase / tag
  result = sandboxRoot
  let dataDir = sandboxRoot / "data"
  createDir(dataDir)
  var entries: seq[string] = @[]
  for i in 1 .. 3:
    entries.add("{\"id\":\"DEBT#" & $i & "\",\"severity\":\"low\",\"category\":\"test\",\"description\":\"test entry\",\"status\":\"open\"}")
  for i in 1 .. 5:
    entries.add("{\"id\":\"DEBT-C#" & $i & "\",\"severity\":\"low\",\"category\":\"test\",\"description\":\"test entry\",\"status\":\"closed\"}")
  writeFile(dataDir / "debt_registry.json",
    "{\n  \"version\": 3,\n  \"entries\": [" & entries.join(",") & "]\n}")
  writeFile(result / "data" / "debt_budgets.json", """{
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
}""")
  var records: seq[string] = @[]
  for b in ledgerRecs:
    records.add("{\n      \"id\": \"" & b.id & "\",\n" &
      "      \"category\": \"BudgetCategory\",\n" &
      "      \"description\": \"test budget record\",\n" &
      "      \"budgetCategory\": \"bcDebtRegistryOpen\",\n" &
      "      \"metric\": \"" & b.metric & "\",\n" &
      "      \"baseline\": " & b.baseline & ",\n" &
      "      \"target\": " & b.target & ",\n" &
      "      \"current\": " & b.current & ",\n" &
      "      \"severity\": \"low\",\n" &
      "      \"source\": \"debt_budgets.json\",\n" &
      "      \"status\": \"" & b.status & "\",\n" &
      "      \"resolution\": \"" & b.resolution & "\",\n" &
      "      \"lastVerifiedAt\": \"2026-11-15T00:00:00Z\"\n    }")
  writeFile(result / "data" / "debt_ledger.json",
    "{\n  \"version\": \"1.1.0\",\n  \"generated\": \"2026-11-15T00:00:00Z\",\n" &
    "  \"totalRecords\": " & $ledgerRecs.len & ",\n  \"records\": [" & records.join(",") & "]\n}")

proc runSync(engineBin, sandbox: string; dryRun = false): tuple[output: string, exitCode: int] =
  let cmd = quoteShell(engineBin) & " --sync-budget" & (if dryRun: " --dry-run" else: "")
  execCmdEx(cmd, workingDir = sandbox)

proc ledgerJson(sandbox: string): JsonNode =
  parseJson(readFile(sandbox / "data" / "debt_ledger.json"))

proc recordByMetric(sandbox: string; metric: string): JsonNode =
  for rec in ledgerJson(sandbox)["records"]:
    if rec["metric"].getStr() == metric:
      return rec
  raise newException(KeyError, "no ledger record for metric " & metric)

suite "debt_engine --sync-budget CLI contract (DEBT#543)":
  let repoRoot = findRepoRoot()
  let suiteDir = getTempDir() / ("axiom_de_sync_" & $getCurrentProcessId() & "_" & $epochTime().int)
  createDir(suiteDir)
  let engineBin = ensureDebtEngineBin(repoRoot, suiteDir)

  test "happy path: all metrics measured, ledger written, exit 0":
    let sb = writeSandbox(suiteDir, "happy", @[
      ("BUDGET#005", "debt_registry_open", "107", "0", "0", "closed", "FIXED"),
      ("BUDGET#006", "debt_registry_closed", "0", "92", "5", "closed", "FIXED"),
    ])
    defer: removeDir(sb)

    let (outText, rc) = runSync(engineBin, sb)
    check rc == 0
    check outText.contains("Skipped (no evaluator): 0")
    check outText.contains("Sync complete.")
    check not outText.contains("Sync INCOMPLETE")

    # BUDGET#005: registry has 3 open entries → current 3, open/WONT_FIX
    let open5 = recordByMetric(sb, "debt_registry_open")
    check open5["current"].getInt() == 3
    check open5["status"].getStr() == "open"
    check open5["resolution"].getStr() == "WONT_FIX"
    check open5["lastVerifiedAt"].getStr() == "2026-11-15T00:00:00Z"

    # BUDGET#006: registry has 5 closed entries → current 5 (< target 92 → open)
    let closed6 = recordByMetric(sb, "debt_registry_closed")
    check closed6["current"].getInt() == 5
    check closed6["status"].getStr() == "open"
    check closed6["resolution"].getStr() == "WONT_FIX"

  test "idempotency: second run reports zero updates and still exits 0":
    let sb = writeSandbox(suiteDir, "idem", @[
      ("BUDGET#005", "debt_registry_open", "107", "0", "3", "open", "WONT_FIX"),
      ("BUDGET#006", "debt_registry_closed", "0", "92", "5", "open", "WONT_FIX"),
    ])
    defer: removeDir(sb)

    discard runSync(engineBin, sb)
    let (outText, rc) = runSync(engineBin, sb)
    check rc == 0
    check outText.contains("Updates applied:   0")
    check outText.contains("Skipped (no evaluator): 0")
    check outText.contains("Sync complete.")

  test "fail-closed: missing evaluator binary skips record, exit 1, no fabricated current":
    let sb = writeSandbox(suiteDir, "missing_bin", @[
      ("BUDGET#005", "debt_registry_open", "107", "0", "0", "closed", "FIXED"),
      ("BUDGET#006", "debt_registry_closed", "0", "92", "5", "closed", "FIXED"),
      # Sandbox has no bin/nimtry → evaluator reports binary unavailable.
      ("BUDGET#004", "nimtry_violations", "704", "0", "7", "open", "WONT_FIX"),
    ])
    defer: removeDir(sb)

    let (outText, rc) = runSync(engineBin, sb)
    check rc == 1
    check outText.contains("[skip] nimtry_violations: evaluator binary unavailable (bin/nimtry)")
    check outText.contains("BUDGET#004 (evaluator error)")
    check outText.contains("Sync INCOMPLETE: 1 of 3 BUDGET record(s) unmeasured")
    check not outText.contains("Sync complete.")

    # Measured records still land in the ledger.
    check recordByMetric(sb, "debt_registry_open")["current"].getInt() == 3
    # The unmeasured record keeps its last verified value — never fabricated.
    let unmeasured = recordByMetric(sb, "nimtry_violations")
    check unmeasured["current"].getInt() == 7
    check unmeasured["status"].getStr() == "open"
    check unmeasured["resolution"].getStr() == "WONT_FIX"
    check unmeasured["lastVerifiedAt"].getStr() == "2026-11-15T00:00:00Z"

  test "fail-closed: dry-run also exits 1 when a record is unmeasured":
    let sb = writeSandbox(suiteDir, "dryrun_missing", @[
      ("BUDGET#005", "debt_registry_open", "107", "0", "0", "closed", "FIXED"),
      ("BUDGET#004", "nimtry_violations", "704", "0", "7", "open", "WONT_FIX"),
    ])
    defer: removeDir(sb)

    let (outText, rc) = runSync(engineBin, sb, dryRun = true)
    check rc == 1
    check outText.contains("[DRY-RUN] No files written.")
    check outText.contains("Sync INCOMPLETE")
    # Dry-run writes nothing: the fixture ledger keeps its original bytes.
    check recordByMetric(sb, "debt_registry_open")["current"].getInt() == 0

  test "fail-closed: metric with no registered evaluator exits 1":
    let sb = writeSandbox(suiteDir, "unknown_metric", @[
      ("BUDGET#005", "debt_registry_open", "107", "0", "0", "closed", "FIXED"),
      ("BUDGET#009", "unknown_metric", "1", "0", "4", "open", "WONT_FIX"),
    ])
    defer: removeDir(sb)

    let (outText, rc) = runSync(engineBin, sb)
    check rc == 1
    check outText.contains("BUDGET#009 (metric=unknown_metric)")
    check outText.contains("Sync INCOMPLETE")
    check not outText.contains("Sync complete.")
    # The unmeasured record is preserved untouched.
    check recordByMetric(sb, "unknown_metric")["current"].getInt() == 4

  removeDir(suiteDir)
