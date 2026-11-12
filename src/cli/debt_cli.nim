import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Debt CLI — architecture debt registry management (evidence-first).
##
##   ax debt sync       — read-only registry drift report (no writes; bin/debt_engine owns the registry)
##   ax debt check      — check debt registry integrity (entry count, open count, budget drift)
##   ax debt budget     — show debt budget status and drift metrics
##   ax debt ledger     — show the debt ledger (proc→func migration candidates)
##   ax debt audit      — canonical current-debt universe audit with classification
##   ax debt fingerprint — deterministic identity fingerprints for registry entries
##   ax debt classify   — classify each entry using the canonical classifier
##   ax debt universe   — emit a deterministic CanonicalCurrentDebtUniverse JSON document
##   ax debt observe    — convert registry entries to DebtObservation and append to evidence journal
##   ax debt evolve     — run full evidence-first classification pipeline with provenance
##   ax debt drift      — classify budget metrics as drift, never auto-promote to debt
##   ax debt audit-run  — commit decisions+events to the canonical journal and project (v8)
##   ax debt replay     — replay a committed run and verify all digests (v8)
##   ax debt reconstruct — rebuild the last (or historical) committed projection (v8)
##   ax debt explain    — show candidate classification and leading events (v8)

import std/[json, os, sequtils, strutils, times, algorithm, tables, options]
import checksums/sha2
import core/axiom_pragmas
import core/types/debt_types
import core/results
import infrastructure/logging_facade
import core/debt/debt_observation
import core/debt/debt_identity
import core/debt/debt_classifier
import core/debt/debt_budget
import core/debt/debt_claim
import core/debt/debt_provenance
import core/debt/debt_audit
import core/debt/integrity_patterns
import core/debt/debt_events
import core/debt/debt_projection
import core/debt/debt_pipeline
import sync_budget

const
  DebtRegistryPath = "data/debt_registry.json"
  DebtBudgetsPath = "data/debt_budgets.json"
  DebtLedgerPath = "data/debt_ledger.json"

proc loadJsonFile*(path: string): JsonNode {.raises: [CatchableError], axiomDecision.} =
  if not fileExists(path):
    return %*{}
  try:
    result = parseJson(readFile(path))
  except CatchableError:
    return %*{}

proc loadLedgerCurrentByMetric*(ledgerPath: string): Table[string, int] {.raises: [CatchableError], axiomDecision.} =
  ## Load current values from debt_ledger.json for each metric.
  ## Returns an empty table if the file is missing or malformed.
  if not fileExists(ledgerPath):
    return initTable[string, int]()
  try:
    let data = parseJson(readFile(ledgerPath))
    if data.isNil or data.kind != JObject:
      return initTable[string, int]()
    let records = data{"records"}
    if records.isNil or records.kind != JArray:
      return initTable[string, int]()
    for rec in records:
      let metric = rec{"metric"}.getStr("")
      let current = rec{"current"}.getInt(0)
      if metric.len > 0:
        result[metric] = current
  except CatchableError:
    return initTable[string, int]()

proc getOrDefaultStr*(node: JsonNode; key: string; default: string = ""): string {.raises: [CatchableError].} =
  if node.isNil or not node.hasKey(key) or node[key].kind == JNull:
    return default
  node[key].getStr(default)

proc getOrDefaultInt*(node: JsonNode; key: string; default: int = 0): int {.raises: [CatchableError].} =
  if node.isNil or not node.hasKey(key) or node[key].kind == JNull:
    return default
  node[key].getInt(default)

func normalizeFilePath*(path: string): string {.raises: [].} =
  ## Normalize a file path for canonical identity: backslashes to forward slashes, strip leading "./".
  result = path.replace("\\", "/")
  while result.startsWith("./"):
    result = result[2..^1]

func normalizeDescription*(desc: string): string {.raises: [].} =
  ## Normalize a description for canonical identity: lowercase and strip whitespace.
  result = desc.toLowerAscii().strip()

func computeFingerprint*(entry: JsonNode): string {.raises: [CatchableError].} =
  ## Compute deterministic fingerprint for a debt registry entry.
  ## fingerprint = sha256(category + "|" + normalized(join(files,"|")) + "|" + normalizedDescription)
  let category = entry.getOrDefaultStr("category", "")
  let description = entry.getOrDefaultStr("description", "")
  let normDesc = normalizeDescription(description)

  var normalizedFiles: seq[string] = @[]
  if entry.hasKey("files"):
    let filesNode = entry["files"]
    if filesNode.kind == JArray:
      for f in filesNode:
        normalizedFiles.add(normalizeFilePath(f.getStr()))
  normalizedFiles.sort()
  let joinedFiles = normalizedFiles.join("|")

  let raw = category & "|" & joinedFiles & "|" & normDesc
  result = "sha256:" & $Sha_256.secureHash(raw)

proc classifyEntry*(entry: JsonNode; cwd: string): DebtClass {.raises: [CatchableError].} =
  ## Classify a debt registry entry into its current lifecycle state.
  ## Shared logic used by cmdDebtAudit and cmdDebtClassify.
  let category = entry.getOrDefaultStr("category", "")
  if category.toLowerAscii().contains("quirk"):
    return dcQuirk

  let status = entry.getOrDefaultStr("status", "").toLowerAscii()
  let resolution = entry.getOrDefaultStr("resolution", "")

  # Check if any referenced files exist on disk
  var hasEvidence = false
  var hasFileEntry = false
  if entry.hasKey("files"):
    let filesNode = entry["files"]
    if filesNode.kind == JArray:
      for f in filesNode:
        hasFileEntry = true
        let filePath = f.getStr()
        let normalizedPath = normalizeFilePath(filePath)
        if fileExists(cwd / normalizedPath):
          hasEvidence = true
          break

  # Check source marker
  let source = entry.getOrDefaultStr("source", "")
  let hasSource = source.len > 0

  if status == "open":
    if hasEvidence or hasSource:
      return dcOpenDebt
    else:
      return dcUnverified

  if status == "closed" or status == "accepted":
    if resolution.len > 0:
      # Historical resolution (FIXED/WONT_FIX etc.) => RESOLVED regardless of
      # file presence; the debt lifecycle is settled.
      return dcResolved
    # No recorded resolution: distinguish materialized debt from historical refs.
    if hasFileEntry and not hasEvidence:
      # All referenced files are missing
      return dcStale
    return dcResolved

  return dcStale

proc getGitCommitSha*(): string {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the current git commit SHA from .git/HEAD.
  let headPath = getCurrentDir() / ".git" / "HEAD"
  if not fileExists(headPath):
    return "unknown"
  try:
    let headContent = readFile(headPath).strip()
    if headContent.startsWith("ref: "):
      let refPath = headContent[5..^1].strip()
      let fullRefPath = getCurrentDir() / ".git" / refPath
      if fileExists(fullRefPath):
        result = readFile(fullRefPath).strip()
      else:
        result = "unknown"
    else:
      # Detached HEAD — content is already the SHA
      result = headContent
  except CatchableError:
    result = "unknown"

proc cmdDebtAudit*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic canonical current-debt universe audit.
  ## Classifies each registry entry and checks budget drift.
  ## Returns 0 normally, 1 if any OPEN_DEBT or BUDGET_DRIFT found.
  echo "=== Axiom Debt Audit ==="
  let cwd = getCurrentDir()
  let registryPath = cwd / DebtRegistryPath
  try:
    let data = loadJsonFile(registryPath)
    if data.isNil or not data.hasKey("entries"):
      echo "[ERROR] No debt registry found at " & registryPath
      return 1

    let entries = data{"entries"}
    if entries.isNil or entries.kind != JArray:
      echo "[ERROR] Debt registry has no entries array"
      return 1

    # Classify each entry
    var openDebt: seq[JsonNode] = @[]
    var unverified: seq[JsonNode] = @[]
    var stale: seq[JsonNode] = @[]
    var resolved: seq[JsonNode] = @[]
    var quirks: seq[JsonNode] = @[]

    for entry in entries:
      let dc = classifyEntry(entry, cwd)
      case dc
      of dcOpenDebt:   openDebt.add(entry)
      of dcUnverified: unverified.add(entry)
      of dcStale:      stale.add(entry)
      of dcResolved:   resolved.add(entry)
      of dcQuirk:      quirks.add(entry)
      of dcBudgetDrift: discard

    # Check budget drift — current values come from the ledger (derived canonical snapshot),
    # not from debt_budgets.json which defines only baseline/target per the pipeline contract.
    let budgetsPath = cwd / DebtBudgetsPath
    let ledgerPath = cwd / DebtLedgerPath
    let ledgerCurrent = loadLedgerCurrentByMetric(ledgerPath)
    var budgetDrift: seq[(string, JsonNode)] = @[]
    let budgets = loadJsonFile(budgetsPath)
    if budgets.hasKey("metrics"):
      let metrics = budgets{"metrics"}
      for key in metrics.keys:
        let metric = metrics[key]
        let baseline = metric.getOrDefaultInt("baseline", 0)
        let current = ledgerCurrent.getOrDefault(key, 0)
        if current > baseline:
          budgetDrift.add((key, metric))

    # Print summary table
    echo ""
    echo "Classification Summary:"
    echo "  OPEN_DEBT:    ", $openDebt.len
    echo "  UNVERIFIED:   ", $unverified.len
    echo "  STALE:        ", $stale.len
    echo "  RESOLVED:     ", $resolved.len
    echo "  QUIRK:        ", $quirks.len
    echo "  BUDGET_DRIFT: ", $budgetDrift.len
    echo ""

    # Detail: OPEN_DEBT
    if openDebt.len > 0:
      echo "--- OPEN_DEBT ---"
      for entry in openDebt:
        let id = entry.getOrDefaultStr("id", "?")
        let category = entry.getOrDefaultStr("category", "?")
        let severity = entry.getOrDefaultStr("severity", "?")
        let desc = entry.getOrDefaultStr("description", "")
        if desc.len > 80:
          echo "  [", id, "] ", category, " (", severity, ") — ", desc[0..<80], "..."
        else:
          echo "  [", id, "] ", category, " (", severity, ") — ", desc
        let filesNode = entry{"files"}
        if filesNode.kind == JArray:
          for f in filesNode:
            echo "    file: ", f.getStr()
      echo ""

    # Detail: UNVERIFIED
    if unverified.len > 0:
      echo "--- UNVERIFIED ---"
      for entry in unverified:
        let id = entry.getOrDefaultStr("id", "?")
        let category = entry.getOrDefaultStr("category", "?")
        echo "  [", id, "] ", category
      echo ""

    # Detail: BUDGET_DRIFT
    if budgetDrift.len > 0:
      echo "--- BUDGET_DRIFT ---"
      for (key, metric) in budgetDrift:
        let current = ledgerCurrent.getOrDefault(key, 0)
        let baseline = metric.getOrDefaultInt("baseline", 0)
        let drift = current - baseline
        let pct = if baseline > 0: (drift.float / baseline.float * 100.0).formatFloat(ffDecimal, 1) else: "N/A"
        echo "  ", key, ": current=", $current, " baseline=", $baseline,
          " drift=", $drift, " (", pct, "%)"
      echo ""

    # Return code
    if openDebt.len > 0 or budgetDrift.len > 0:
      echo "[WARN] Audit found issues: ", $openDebt.len, " OPEN_DEBT, ", $budgetDrift.len, " BUDGET_DRIFT"
      result = 1
    else:
      echo "[OK] No OPEN_DEBT or BUDGET_DRIFT issues found"
      result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt audit] failed: " & e.msg)
    result = 1

proc cmdDebtFingerprint*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Show deterministic fingerprints for debt registry entries (sample).
  echo "=== Axiom Debt Fingerprint Sample ==="
  let registryPath = getCurrentDir() / DebtRegistryPath
  try:
    let data = loadJsonFile(registryPath)
    if data.isNil or not data.hasKey("entries"):
      echo "[ERROR] No debt registry found"
      return 1

    let entries = data{"entries"}
    if entries.isNil or entries.kind != JArray:
      echo "[ERROR] Debt registry has no entries array"
      return 1

    let sampleSize = min(entries.len, 5)
    echo "Showing ", $sampleSize, " of ", $entries.len, " fingerprints:"
    echo ""
    for i in 0 ..< sampleSize:
      let entry = entries[i]
      let id = entry.getOrDefaultStr("id", "?")
      let fingerprint = computeFingerprint(entry)
      echo "  ", id, " -> ", fingerprint

    if entries.len > sampleSize:
      echo "  ... and ", $(entries.len - sampleSize), " more"
    echo ""
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt fingerprint] failed: " & e.msg)
    result = 1

proc cmdDebtClassify*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Classify each debt registry entry using the canonical classifier.
  echo "=== Axiom Debt Classification ==="
  let cwd = getCurrentDir()
  let registryPath = cwd / DebtRegistryPath
  try:
    let data = loadJsonFile(registryPath)
    if data.isNil or not data.hasKey("entries"):
      echo "[ERROR] No debt registry found"
      return 1

    let entries = data{"entries"}
    if entries.isNil or entries.kind != JArray:
      echo "[ERROR] Debt registry has no entries array"
      return 1

    var counts: Table[DebtClass, int]
    for entry in entries:
      let dc = classifyEntry(entry, cwd)
      let id = entry.getOrDefaultStr("id", "?")
      echo id, " -> ", debtClassToStr(dc)
      counts[dc] = counts.getOrDefault(dc) + 1

    echo ""
    echo "Summary:"
    for dc in [dcOpenDebt, dcUnverified, dcStale, dcResolved, dcQuirk]:
      echo "  ", debtClassToStr(dc), ": ", $counts.getOrDefault(dc, 0)
    echo ""
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt classify] failed: " & e.msg)
    result = 1

proc cmdDebtUniverse*(args: seq[string]): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Emit a deterministic CanonicalCurrentDebtUniverse JSON document.
  echo "=== Axiom Debt Universe ==="
  let cwd = getCurrentDir()
  let registryPath = cwd / DebtRegistryPath
  try:
    let data = loadJsonFile(registryPath)
    if data.isNil or not data.hasKey("entries"):
      echo "[ERROR] No debt registry found"
      return 1

    let entries = data{"entries"}
    if entries.isNil or entries.kind != JArray:
      echo "[ERROR] Debt registry has no entries array"
      return 1

    # Classify each entry into universe arrays
    var openDebtArr: seq[JsonNode] = @[]
    var staleArr: seq[JsonNode] = @[]
    var unverifiedArr: seq[JsonNode] = @[]
    var resolvedArr: seq[JsonNode] = @[]
    var quirksArr: seq[JsonNode] = @[]

    for entry in entries:
      let dc = classifyEntry(entry, cwd)
      let id = entry.getOrDefaultStr("id", "?")
      let category = entry.getOrDefaultStr("category", "")
      let description = entry.getOrDefaultStr("description", "")
      let severity = entry.getOrDefaultStr("severity", "")
      let status = entry.getOrDefaultStr("status", "")
      let resolution = entry.getOrDefaultStr("resolution", "")
      let fingerprint = computeFingerprint(entry)

      var obj = %*{}
      obj["id"] = %id
      obj["category"] = %category
      obj["description"] = %description
      obj["severity"] = %severity
      obj["status"] = %status
      if resolution.len > 0:
        obj["resolution"] = %resolution
      obj["fingerprint"] = %fingerprint

      case dc
      of dcOpenDebt:   openDebtArr.add(obj)
      of dcUnverified: unverifiedArr.add(obj)
      of dcStale:      staleArr.add(obj)
      of dcResolved:   resolvedArr.add(obj)
      of dcQuirk:      quirksArr.add(obj)
      of dcBudgetDrift: discard

    # Sort each array by id for deterministic ordering
    for arr in [addr openDebtArr, addr staleArr, addr unverifiedArr, addr resolvedArr, addr quirksArr]:
      arr[].sort(proc(a, b: JsonNode): int =
        let aId = a["id"].getStr()
        let bId = b["id"].getStr()
        if aId < bId: -1
        elif aId > bId: 1
        else: 0
      )

    # Check budget drift — current values from the ledger (derived canonical snapshot).
    let budgetsPath = cwd / DebtBudgetsPath
    let ledgerPath = cwd / DebtLedgerPath
    let ledgerCurrent = loadLedgerCurrentByMetric(ledgerPath)
    let budgets = loadJsonFile(budgetsPath)
    var budgetDriftArr: seq[JsonNode] = @[]
    if budgets.hasKey("metrics"):
      let metrics = budgets{"metrics"}
      for key in metrics.keys:
        let metric = metrics[key]
        let baseline = metric.getOrDefaultInt("baseline", 0)
        let current = ledgerCurrent.getOrDefault(key, 0)
        if current > baseline:
          let drift = current - baseline
          let pct = if baseline > 0: (drift.float / baseline.float * 100.0).formatFloat(ffDecimal, 1) else: "N/A"
          var obj = %*{}
          obj["metric"] = %key
          obj["baseline"] = %baseline
          obj["current"] = %current
          obj["drift"] = %drift
          obj["pct"] = %pct
          obj["description"] = %metric.getOrDefaultStr("description", "")
          budgetDriftArr.add(obj)

    # Sort budget drift by metric name
    budgetDriftArr.sort(proc(a, b: JsonNode): int =
      let aKey = a["metric"].getStr()
      let bKey = b["metric"].getStr()
      if aKey < bKey: -1
      elif aKey > bKey: 1
      else: 0
    )

    # Build universe document
    let repoName = cwd.splitFile().name
    let commitSha = getGitCommitSha()

    var universe = %*{}
    universe["repository"] = %repoName
    universe["commitsha"] = %commitSha
    universe["detectorVersion"] = %"debt-static-v1"
    universe["classifierVersion"] = %DebtClassifierVersion
    universe["taxonomyVersion"] = %DebtTaxonomyVersion
    universe["openDebt"] = %openDebtArr
    universe["stale"] = %staleArr
    universe["unverified"] = %unverifiedArr
    universe["resolved"] = %resolvedArr
    universe["quirks"] = %quirksArr
    universe["budgetDrift"] = %budgetDriftArr

    var output = %*{}
    output["CanonicalCurrentDebtUniverse"] = %universe

    echo output.pretty()
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt universe] failed: " & e.msg)
    result = 1

func statusDriftIds(entries: JsonNode): seq[string] =
  ## Open entries that already carry a resolution — a sync would close them.
  for entry in entries:
    if entry.getOrDefaultStr("status", "").toLowerAscii() == "open" and
       entry.getOrDefaultStr("resolution", "").len > 0:
      result.add(entry.getOrDefaultStr("id", "?"))

proc hashDriftIds(entries: JsonNode): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Entries whose stored contentHash no longer matches the files they reference.
  for entry in entries:
    if not (entry.hasKey("files") and entry.hasKey("lineRange")): continue
    if entry{"files"}.kind != JArray: continue
    var fileHashes: seq[string] = @[]
    for f in entry{"files"}:
      let filePath = f.getStr()
      if fileExists(filePath):
        fileHashes.add("sha256:" & $Sha_256.secureHash(readFile(filePath)) & "\x02" & filePath)
    if fileHashes.len > 0:
      let computed = "sha256:" & $Sha_256.secureHash(fileHashes.join("\x01"))
      if entry.getOrDefaultStr("contentHash", "") != computed:
        result.add(entry.getOrDefaultStr("id", "?"))

proc reportDriftIds(label: string, ids: seq[string]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  echo label, " — ", ids.len, " entry(ies):"
  for id in ids:
    echo "  " & id

proc cmdDebtSync*(args: seq[string] = @[]): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read-only drift report for the debt registry. Never mutates the registry:
  ## bin/debt_engine is the sole writer of data/debt_registry.json.
  ## Reports the transitions that a sync would apply and exits non-zero on drift.
  echo "=== Axiom Debt Sync (read-only check) ==="
  for arg in args:
    if arg != "--check":
      echo "[ERROR] Unknown argument: " & arg
      echo "Usage: ax debt sync [--check]"
      return 1
  let registryPath = getCurrentDir() / DebtRegistryPath
  try:
    let data = loadJsonFile(registryPath)
    if data.isNil or not data.hasKey("entries"):
      echo "[WARN] No debt registry found at " & registryPath
      return 1

    let entries = data{"entries"}
    if entries.isNil or entries.kind != JArray:
      echo "[WARN] Debt registry has no entries array"
      return 1

    let wouldClose = statusDriftIds(entries)
    let wouldRehash = hashDriftIds(entries)
    if wouldClose.len == 0 and wouldRehash.len == 0:
      echo "No drift: registry statuses and content hashes are consistent."
      echo "Projections are materialized by bin/debt_engine --codegen (verify: bin/debt_engine --validate)."
      return 0

    if wouldClose.len > 0:
      reportDriftIds("Status drift — open entries carry a resolution (would close)", wouldClose)
    if wouldRehash.len > 0:
      reportDriftIds("Hash drift — stale contentHash (would rehash)", wouldRehash)
    echo "Registry is read-only here; apply through bin/debt_engine, then regenerate with bin/debt_engine --codegen."
    return 1
  except CatchableError as e:
    logError("debt_cli", "[debt sync check] failed: " & e.msg)
    result = 1

proc cmdDebtCheck*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check debt registry integrity: entry count, open count, budget drift.
  echo "=== Axiom Debt Check ==="
  let registryPath = getCurrentDir() / DebtRegistryPath
  try:
    let data = loadJsonFile(registryPath)
    if data.isNil or not data.hasKey("entries"):
      echo "[ERROR] No debt registry found"
      return 1

    let entries = data{"entries"}
    if entries.isNil or entries.kind != JArray:
      echo "[ERROR] Debt registry has no entries array"
      return 1

    let total = entries.len
    var openCount = 0
    var closedCount = 0
    var acceptedCount = 0
    var deferredCount = 0
    var inProgressCount = 0

    for entry in entries:
      let status = entry.getOrDefaultStr("status", "").toLowerAscii()
      case status
      of "open": inc openCount
      of "closed": inc closedCount
      of "accepted": inc acceptedCount
      of "deferred": inc deferredCount
      of "in_progress": inc inProgressCount
      else: discard

    echo "Total entries: ", $total
    echo "Open: ", $openCount
    echo "Closed: ", $closedCount
    echo "Accepted: ", $acceptedCount
    echo "Deferred: ", $deferredCount
    echo "In progress: ", $inProgressCount

    # Check budget drift — current values from the ledger (derived canonical snapshot).
    let budgetsPath = getCurrentDir() / DebtBudgetsPath
    let ledgerPath = getCurrentDir() / DebtLedgerPath
    let ledgerCurrent = loadLedgerCurrentByMetric(ledgerPath)
    let budgets = loadJsonFile(budgetsPath)
    if budgets.hasKey("metrics"):
      echo ""
      echo "--- Budget Drift ---"
      let metrics = budgets{"metrics"}
      for key in metrics.keys:
        let metric = metrics[key]
        let baseline = metric.getOrDefaultInt("baseline", 0)
        let current = ledgerCurrent.getOrDefault(key, 0)
        let target = metric.getOrDefaultInt("target", 0)
        let drift = current - baseline
        let pct = if baseline > 0: (drift.float / baseline.float * 100.0).formatFloat(ffDecimal, 1) else: "N/A"
        echo "  ", key, ": current=", $current, " baseline=", $baseline,
          " target=", $target, " drift=", $drift, " (", pct, "%)"

    if openCount > 0:
      echo ""
      echo "[WARN] ", $openCount, " open debt entry(ies) remain"
      result = 1
    else:
      echo ""
      echo "[OK] No open debt entries"
      result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt check] failed: " & e.msg)
    result = 1

proc cmdDebtBudget*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Show debt budget status and drift metrics.
  ## `current` values are read from the ledger (derived canonical snapshot),
  ## not from debt_budgets.json which defines only baseline/target.
  echo "=== Axiom Debt Budget ==="
  let budgetsPath = getCurrentDir() / DebtBudgetsPath
  let ledgerPath = getCurrentDir() / DebtLedgerPath
  try:
    let budgets = loadJsonFile(budgetsPath)
    if budgets.isNil or not budgets.hasKey("metrics"):
      echo "[ERROR] No debt budgets found at " & budgetsPath
      return 1

    let ledgerCurrent = loadLedgerCurrentByMetric(ledgerPath)

    echo "Budget baseline date: ", budgets.getOrDefaultStr("baseline_date", "unknown")
    echo "Weekly reduction target: ", budgets.getOrDefaultStr("weekly_reduction_pct", "unknown"), "%"
    echo ""

    let metrics = budgets{"metrics"}
    for key in metrics.keys:
      let metric = metrics[key]
      let current = ledgerCurrent.getOrDefault(key, 0)
      let baseline = metric.getOrDefaultInt("baseline", 0)
      let target = metric.getOrDefaultInt("target", 0)
      let description = metric.getOrDefaultStr("description", "")
      let drift = current - baseline
      let pct = if baseline > 0: (drift.float / baseline.float * 100.0).formatFloat(ffDecimal, 1) else: "N/A"
      echo key & ":"
      echo "  description: ", description
      echo "  baseline: ", $baseline, "  current: ", $current, "  target: ", $target
      echo "  drift: ", $drift, " (", pct, "%)"
      echo ""

    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt budget] failed: " & e.msg)
    result = 1

proc cmdDebtLedger*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Show the debt ledger (proc→func migration candidates).
  echo "=== Axiom Debt Ledger ==="
  let ledgerPath = getCurrentDir() / DebtLedgerPath
  try:
    let ledger = loadJsonFile(ledgerPath)
    if ledger.isNil or not ledger.hasKey("records"):
      echo "[INFO] Debt ledger is empty or not found at " & ledgerPath
      echo "Total records: 0"
      return 0

    let total = ledger.getOrDefaultInt("totalRecords", 0)
    echo "Total records: ", $total
    echo ""

    let records = ledger{"records"}
    if records.isNil or records.kind != JArray:
      echo "[INFO] No records in ledger"
      return 0

    for record in records:
      let id = record.getOrDefaultStr("id", "?")
      let category = record.getOrDefaultStr("category", "?")
      let severity = record.getOrDefaultStr("severity", "?")
      let message = record.getOrDefaultStr("message", "")
      let count = record.getOrDefaultInt("count", 0)
      let filesIn = record.getOrDefaultStr("files_in", "")
      echo "  [", id, "] ", category, " (", severity, ") — ", message
      if filesIn.len > 0:
        echo "    files: ", filesIn
      echo "  count: ", $count
      echo ""

    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt ledger] failed: " & e.msg)
    result = 1

# ---------------------------------------------------------------------------
# observe — convert registry entries to DebtObservation and append to journal
# ---------------------------------------------------------------------------

proc cmdDebtObserve*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Convert each debt registry entry into a DebtObservation, compute its
  ## content-addressable digest, and append to the evidence journal.
  ## Deterministic: same registry entries produce the same digests.
  ## Only appends — never modifies existing journal content.
  echo "=== Axiom Debt Observe ==="
  let cwd = getCurrentDir()
  let registryPath = cwd / DebtRegistryPath
  let journalPath = cwd / observationsJournalPath
  try:
    let data = loadJsonFile(registryPath)
    if data.isNil or not data.hasKey("entries"):
      echo "[ERROR] No debt registry found at " & registryPath
      return 1

    let entries = data{"entries"}
    if entries.isNil or entries.kind != JArray:
      echo "[ERROR] Debt registry has no entries array"
      return 1

    # Ensure the journal directory exists
    let journalDir = parentDir(journalPath)
    if not dirExists(journalDir):
      createDir(journalDir)

    let commitSha = getGitCommitSha()
    var appendedCount = 0
    var digests: seq[string] = @[]

    for entry in entries:
      let id = entry.getOrDefaultStr("id", "")
      let category = entry.getOrDefaultStr("category", "")
      let description = entry.getOrDefaultStr("description", "")
      let source = entry.getOrDefaultStr("source", "")
      let severity = entry.getOrDefaultStr("severity", "")
      let status = entry.getOrDefaultStr("status", "")

      # Derive subject from first file entry, or fall back to id
      var subject = id
      if entry.hasKey("files"):
        let filesNode = entry["files"]
        if filesNode.kind == JArray and filesNode.len > 0:
          subject = normalizeFilePath(filesNode[0].getStr())

      # Derive ObservationKind from source field
      let kind: ObservationKind =
        if source.toLowerAscii().contains("gate"): okGateDeclaration
        elif source.toLowerAscii().contains("cert") or source.toLowerAscii().contains("proof"): okCertificate
        elif source.toLowerAscii().contains("metric"): okMetric
        else: okSourceMarker

      # Build observedAt timestamp
      let dt = now().utc()
      let observedAt = dt.format("yyyy-MM-dd") & "T" & dt.format("HH:mm:ss") & "Z"

      var obs = DebtObservation(
        kind: kind,
        subject: subject,
        semanticIdentity: id,
        snapshotId: commitSha,
        source: source,
        payload: description & " | severity=" & severity & " | status=" & status,
        observedAt: observedAt,
        toolchainContext: "nim-2.2.10"
      )

      let digest = observationDigest(obs)
      let ok = appendObservation(obs, journalPath)
      if ok:
        inc appendedCount
        digests.add(digest)

    echo "Journal: " & journalPath
    echo "Appended observations: " & $appendedCount
    echo "Total digests: " & $digests.len
    for d in digests:
      echo "  " & d
    echo ""
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt observe] failed: " & e.msg)
    result = 1

# ---------------------------------------------------------------------------
# evolve — full evidence-first classification pipeline with provenance
# ---------------------------------------------------------------------------

proc cmdEvolve*(args: seq[string]): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run the full evidence-first classification pipeline:
  ## registry entry → DebtObservation → classifyDebt → ClassificationEvent.
  ## Supports --explain <candidateId> for provenance replay and --json for
  ## structured output.
  echo "=== Axiom Debt Evolve ==="
  let cwd = getCurrentDir()
  let registryPath = cwd / DebtRegistryPath
  try:
    let data = loadJsonFile(registryPath)
    if data.isNil or not data.hasKey("entries"):
      echo "[ERROR] No debt registry found"
      return 1

    let entries = data{"entries"}
    if entries.isNil or entries.kind != JArray:
      echo "[ERROR] Debt registry has no entries array"
      return 1

    # Parse flags
    var jsonOutput = false
    var explainCandidateId = ""
    var i = 0
    while i < args.len:
      if args[i] == "--json":
        jsonOutput = true
      elif args[i] == "--explain" and i + 1 < args.len:
        explainCandidateId = args[i + 1]
        inc i
      inc i

    let commitSha = getGitCommitSha()
    let ruleSetHash = debtRuleSetHash()          # deterministic digest of rule text
    let classifierVersion = DebtClassifierVersion
    let taxonomyVersion = DebtTaxonomyVersion
    let recordedAt = now().utc().format("yyyy-MM-dd") & "T" & now().utc().format("HH:mm:ss") & "Z"

    # Classify each entry
    var events: seq[ClassificationEvent] = @[]
    var openCount = 0
    var resolvedCount = 0
    var unverifiedCount = 0
    var quirkCount = 0
    var staleCount = 0
    var budgetDriftCount = 0

    for entry in entries:
      let id = entry.getOrDefaultStr("id", "")
      let category = entry.getOrDefaultStr("category", "")
      let description = entry.getOrDefaultStr("description", "")
      let source = entry.getOrDefaultStr("source", "")
      let severity = entry.getOrDefaultStr("severity", "")
      let status = entry.getOrDefaultStr("status", "")

      var subject = id
      if entry.hasKey("files"):
        let filesNode = entry["files"]
        if filesNode.kind == JArray and filesNode.len > 0:
          subject = normalizeFilePath(filesNode[0].getStr())

      let kind: ObservationKind =
        if source.toLowerAscii().contains("gate"): okGateDeclaration
        elif source.toLowerAscii().contains("cert") or source.toLowerAscii().contains("proof"): okCertificate
        elif source.toLowerAscii().contains("metric"): okMetric
        else: okSourceMarker

      let dt = now().utc()
      let observedAt = dt.format("yyyy-MM-dd") & "T" & dt.format("HH:mm:ss") & "Z"

      var obs = DebtObservation(
        kind: kind,
        subject: subject,
        semanticIdentity: id,
        snapshotId: commitSha,
        source: source,
        payload: description & " | severity=" & severity & " | status=" & status,
        observedAt: observedAt,
        toolchainContext: "nim-2.2.10"
      )

      let ev = classifyDebt(obs, ruleSetHash, classifierVersion, taxonomyVersion, commitSha, recordedAt)
      events.add(ev)

      case ev.result
      of dcOpenDebt: inc openCount
      of dcResolved: inc resolvedCount
      of dcUnverified: inc unverifiedCount
      of dcQuirk: inc quirkCount
      of dcStale: inc staleCount
      of dcBudgetDrift: inc budgetDriftCount

    # Build provenance graph for --explain
    var provenanceNodes: seq[ProvenanceNode] = @[]
    var provenanceEdges: seq[ProvenanceEdge] = @[]
    var candidateIdToEventId: Table[string, string]

    for ev in events:
      candidateIdToEventId[ev.candidateId] = ev.eventId
      let classNode = ProvenanceNode(nodeId: ev.eventId, kind: pnkClassification, payloadRef: ev.candidateId)
      provenanceNodes.add(classNode)
      # Edge from observation to classification
      let obsNode = ProvenanceNode(nodeId: "obs:" & ev.candidateId, kind: pnkObservation, payloadRef: ev.candidateId)
      provenanceNodes.add(obsNode)
      provenanceEdges.add(ProvenanceEdge(edgeKind: peObservedIn, fromNode: "obs:" & ev.candidateId, toNode: ev.eventId))
      # Edge from parent event to child event (event sourcing chain)
      if ev.parentEventId.len > 0:
        provenanceEdges.add(ProvenanceEdge(edgeKind: peDerivedFrom, fromNode: ev.parentEventId, toNode: ev.eventId))

    let graph = buildGraph(provenanceNodes, provenanceEdges)

    # Handle --explain
    if explainCandidateId.len > 0:
      let eventId = candidateIdToEventId.getOrDefault(explainCandidateId, "")
      if eventId.len > 0:
        let chain = evidenceChainFor(graph, eventId)
        echo "Evidence chain for candidate " & explainCandidateId & ":"
        echo "  Chain length: " & $chain.len
        for node in chain:
          echo "  [" & $node.kind & "] " & node.nodeId & " -> " & node.payloadRef
        echo ""
      else:
        echo "[ERROR] No classification found for candidate " & explainCandidateId
        echo "  Available candidates: " & $candidateIdToEventId.len
        echo ""

    if jsonOutput:
      var resultObj = %*{}
      resultObj["command"] = %"evolve"
      resultObj["repository"] = %cwd.splitFile().name
      resultObj["commitSha"] = %commitSha
      resultObj["classifierVersion"] = %classifierVersion
      resultObj["ruleSetHash"] = %ruleSetHash
      resultObj["taxonomyVersion"] = %taxonomyVersion
      resultObj["universeDigest"] = %computeUniverseDigest(events, ruleSetHash, taxonomyVersion)

      var classifications = %*[]
      for ev in events:
        var obj = %*{}
        obj["candidateId"] = %ev.candidateId
        obj["eventId"] = %ev.eventId
        obj["result"] = %debtClassToStr(ev.result)
        obj["recordedAt"] = %ev.recordedAt
        obj["repositorySnapshot"] = %ev.repositorySnapshot
        classifications.add(obj)
      resultObj["classifications"] = %classifications

      var summary = %*{}
      summary["openDebt"] = %openCount
      summary["resolved"] = %resolvedCount
      summary["unverified"] = %unverifiedCount
      summary["quirk"] = %quirkCount
      summary["stale"] = %staleCount
      summary["budgetDrift"] = %budgetDriftCount
      resultObj["summary"] = %summary

      echo resultObj.pretty()
    else:
      echo "Classification Summary:"
      echo "  OPEN_DEBT:    " & $openCount
      echo "  RESOLVED:     " & $resolvedCount
      echo "  UNVERIFIED:   " & $unverifiedCount
      echo "  QUIRK:        " & $quirkCount
      echo "  STALE:        " & $staleCount
      echo "  BUDGET_DRIFT: " & $budgetDriftCount
      echo "  Total events: " & $events.len
      echo "  Classifier:   " & classifierVersion
      echo "  Rule set:     " & ruleSetHash
      echo "  Snapshot:     " & commitSha
      echo ""

    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt evolve] failed: " & e.msg)
    result = 1

# ---------------------------------------------------------------------------
# drift — classify budget metrics as drift, never auto-promote to debt
# ---------------------------------------------------------------------------

proc cmdDrift*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Classify each budget metric as drift, explicitly showing that drift
  ## never auto-promotes to debt (driftIsAutoDebt is always false).
  ## Also reports debt_registry open/closed counts and effect_violations.
  ## `current` values are read from the ledger (derived canonical snapshot),
  ## not from debt_budgets.json which defines only baseline/target.
  echo "=== Axiom Debt Drift ==="
  let cwd = getCurrentDir()
  let budgetsPath = cwd / DebtBudgetsPath
  let ledgerPath = cwd / DebtLedgerPath
  try:
    let budgets = loadJsonFile(budgetsPath)
    if budgets.isNil or not budgets.hasKey("metrics"):
      echo "[ERROR] No debt budgets found at " & budgetsPath
      return 1

    let ledgerCurrent = loadLedgerCurrentByMetric(ledgerPath)
    let metrics = budgets{"metrics"}
    let commitSha = getGitCommitSha()

    var metricResults: seq[(string, DriftKind, bool)] = @[]

    for key in metrics.keys:
      let metric = metrics[key]
      let baseline = metric.getOrDefaultInt("baseline", 0).float
      let current = ledgerCurrent.getOrDefault(key, 0).float
      let description = metric.getOrDefaultStr("description", "")

      let mo = MetricObservation(
        metricId: key,
        value: current,
        definitionHash: "",
        measurementMethodHash: "",
        scope: "debt_budget",
        baselineRef: baseline,
        repoSnapshot: commitSha,
        toolchainContext: "nim-2.2.10"
      )

      let drift = classifyDrift(mo, false, false)
      let autoDebt = driftIsAutoDebt(drift)
      metricResults.add((key, drift, autoDebt))

    # Output drift results
    echo "--- Drift Classification ---"
    for (key, drift, autoDebt) in metricResults:
      let metric = metrics[key]
      let current = ledgerCurrent.getOrDefault(key, 0).float
      let baseline = metric.getOrDefaultInt("baseline", 0).float
      echo "  " & key & ":"
      echo "    value=" & $current & " baseline=" & $baseline
      echo "    drift=" & $drift
      echo "    driftIsAutoDebt=" & $autoDebt & " (drift never auto-promotes to debt)"
      echo ""

    # Report registry open/closed counts
    let registryPath = cwd / DebtRegistryPath
    let registry = loadJsonFile(registryPath)
    var openCount = 0
    var closedCount = 0
    if registry.hasKey("entries"):
      let entries = registry{"entries"}
      if entries.kind == JArray:
        for entry in entries:
          let status = entry.getOrDefaultStr("status", "").toLowerAscii()
          if status == "open": inc openCount
          elif status == "closed" or status == "accepted": inc closedCount

    echo "--- Registry Status ---"
    echo "  debt_registry_open: " & $openCount
    echo "  debt_registry_closed: " & $closedCount
    echo ""

    # Report effect_violations — current from the ledger
    let effectViolations = metrics.getOrDefaultStr("effect_violations", "N/A")
    if effectViolations != "N/A":
      let evMetric = metrics["effect_violations"]
      let evBaseline = evMetric.getOrDefaultInt("baseline", 0)
      let evCurrent = ledgerCurrent.getOrDefault("effect_violations", 0)
      echo "  effect_violations: current=" & $evCurrent
      echo "  effect_violations: baseline=" & $evBaseline
    echo ""

    # Summary: drift never auto-promotes
    echo "Policy: driftIsAutoDebt is always false. Drift is a measurement claim,"
    echo "not a debt assertion. Promotion requires a separate policy decision."
    echo ""

    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt drift] failed: " & e.msg)
    result = 1

const AuditRunsJournalPath* = "data/debt/audits/runs.journal"

proc computeEvidenceRoot*(): string =
  ## Content-address over the sorted digests of all observation records.
  ## I/O (reads the observations journal), so it may raise.
  var digests: seq[string] = @[]
  for line in readObservations():
    let obs = parseObservationLine(line)
    if obs.isSome:
      digests.add(observationDigest(obs.get()))
  digests.sort()
  sha256Ref("evidence-root:", digests.join("\x1e"))

proc cmdDebtAuditRun*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## v8 canonical commit stream: build decisions+events from the evidence
  ## pipeline, then call S3 runAudit to commit and project.
  ## Usage: ax debt audit-run <journal-path> <projection-version> [input-root]
  echo "=== Axiom Debt Audit Run (v8) ==="
  if args.len < 2:
    echo "usage: ax debt audit-run <journal-path> <projection-version> [input-root]"
    return 1
  let journalPath = args[1]
  let projectionVersion = args[2]
  let inputRoot = if args.len >= 4: args[3] else: ""
  try:
    let cwd = getCurrentDir()
    let fullPath = cwd / journalPath
    createDir(parentDir(fullPath))

    # --- Step 1: build AuditRun via legacy path ---
    let evRoot = ContentDigest(computeEvidenceRoot())
    let manifest = buildAuditInput(evRoot, debtRuleSetHash(), "nim-2.2.10")
    let resultRoot = ContentDigest(sha256Ref("result:", debtRuleSetHash()))
    let run = recordAuditRun(manifest, resultRoot, "cli", fullPath)

    # --- Step 2: read observations from evidence journal ---
    let obsLines = readObservations()
    var observations: seq[DebtObservation]
    for line in obsLines:
      let stripped = line.strip(chars = {' ', '\t', '\r'})
      if stripped.len == 0: continue
      let obsOpt = parseObservationLine(stripped)
      if obsOpt.isSome:
        observations.add(obsOpt.get())

    if observations.len == 0:
      echo "[ERROR] no observations found — seed evidence first: ax debt observe"
      return 1

    # --- Step 3: classify each observation → ClassificationEvent ---
    let ruleSetHash = debtRuleSetHash()
    let classifierVersion = DebtClassifierVersion
    let taxonomyVersion = DebtTaxonomyVersion
    let repoSnapshot = getGitCommitSha()
    let recordedAt = now().utc().format("yyyy-MM-dd") & "T" & now().utc().format("HH:mm:ss") & "Z"

    var events: seq[ClassificationEvent] = @[]
    var seenCandidates: Table[string, Option[ClassificationEvent]]
    for obs in observations:
      let prev = seenCandidates.getOrDefault(obs.subject & "\x1e" & obs.semanticIdentity, none(ClassificationEvent))
      var ev = classifyDebt(obs, ruleSetHash, classifierVersion, taxonomyVersion, repoSnapshot, recordedAt, prev)
      ev.auditRunId = raw(run.auditRunId)  # required for orderedEvents → commit matching (I16)
      events.add(ev)
      seenCandidates[obs.subject & "\x1e" & obs.semanticIdentity] = some(ev)

    if events.len == 0:
      echo "[ERROR] classification produced zero events — seed evidence first: ax debt observe"
      return 1

    # --- Step 4: build PolicyDecision per unique candidate ---
    var decisions: seq[PolicyDecision] = @[]
    var candToResult: Table[string, DebtClass]
    for ev in events:
      if not candToResult.hasKey(ev.candidateId):
        candToResult[ev.candidateId] = ev.result
    for (candId, dc) in candToResult.pairs:
      let verdict: IntegrityPolicyVerdict =
        case dc
        of dcOpenDebt:    ipvViolation
        of dcUnverified:  ipvUnverified
        of dcStale:       ipvWarning
        of dcResolved:    ipvAcceptable
        of dcQuirk:       ipvAcceptable
        of dcBudgetDrift: ipvWarning
      let rationale = "candidate=" & candId & " classified as " & debtClassToStr(dc)
      let policyDig = ContentDigest(sha256Ref("policy:", ruleSetHash))
      let evidRoot = ContentDigest("")
      let dId = policyDecisionDigest(candId, raw(evidRoot), raw(policyDig), verdict, rationale)
      decisions.add(PolicyDecision(
        decisionId: dId,
        candidateId: candId,
        evidenceRoot: evidRoot,
        policyDigest: policyDig,
        verdict: verdict,
        rationale: rationale))

    # --- Step 5: runAudit (S3) → write journal + compute projection ---
    let auditRes = runAudit(fullPath, run, decisions, events, projectionVersion, inputRoot)
    if auditRes.isErr:
      echo "[ERROR] audit failed: " & auditRes.error
      return 1
    let ar = auditRes.get
    echo "commitId:       " & raw(ar.commit.get.commitId)
    echo "eventRoot:      " & raw(ar.eventRoot)
    echo "decisionDigest: " & raw(ar.decisionDigest)
    echo "universeDigest: " & universeDigestOf(ar.projection)
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt audit-run] failed: " & e.msg)
    result = 1

proc cmdDebtReplay*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## v8 canonical commit stream: replay a committed run and verify
  ## all digests match.  Usage:
  ##   ax debt replay <journal-path> <run-id> <projection-version>
  echo "=== Axiom Debt Replay (v8) ==="
  if args.len < 4:
    echo "usage: ax debt replay <journal-path> <run-id> <projection-version>"
    return 1
  let journalPath = args[1]
  let runId = AuditRunId(args[2])
  let projectionVersion = args[3]
  try:
    let cwd = getCurrentDir()
    let fullPath = cwd / journalPath
    let reportRes = replayAuditRun(fullPath, runId, projectionVersion, "")
    if reportRes.isErr:
      echo "[ERROR] replay failed: " & reportRes.error
      return 1
    let report = reportRes.get
    echo "allMatch:            " & $report.allMatch
    echo "decisionDigestMatch: " & $report.decisionDigestMatch
    echo "eventRootMatch:      " & $report.eventRootMatch
    echo "projectionDigest:    " & report.projectionDigest
    echo "eventDigest:         " & raw(report.eventDigest)
    if not report.allMatch:
      echo "[FAIL] digest mismatch"
      return 1
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt replay] failed: " & e.msg)
    result = 1

proc cmdDebtReevaluate*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Re-evaluate the most recent audit input under a NEW rule set hash (past
  ## evidence preserved, AuditInputId changes).
  echo "=== Axiom Debt Re-evaluate ==="
  if not fileExists(AuditRunsJournalPath):
    echo "[ERROR] no audit runs journal at " & AuditRunsJournalPath
    return 1
  let newRules = if args.len >= 2: args[1] else: debtRuleSetHash()
  try:
    var latest: Option[(AuditRun, AuditInputManifest, int, string)] = none((AuditRun, AuditInputManifest, int, string))
    for line in readFile(AuditRunsJournalPath).splitLines():
      if line.strip.len == 0: continue
      let node = parseJson(line)
      let rec = auditRunRecordFromJson(node)
      if rec.isSome:
        latest = some(rec.get())
    if latest.isNone:
      echo "[ERROR] no recorded audit runs to re-evaluate"
      return 1
    let (_, prevManifest, _, _) = latest.get()
    let newManifest = reevaluate(prevManifest, newRules)
    echo "previous ruleSetHash: " & prevManifest.ruleSetHash
    echo "new ruleSetHash:      " & newManifest.ruleSetHash
    echo "previous auditInputId: " & raw(manifestInputId(prevManifest))
    echo "new auditInputId:      " & raw(manifestInputId(newManifest))
    echo "roots preserved:       evidence=" & raw(newManifest.evidenceRoot) &
         " provenance=" & raw(newManifest.provenanceRoot) &
         " artifact=" & raw(newManifest.artifactRoot) &
         " execution=" & raw(newManifest.executionRoot)
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt re-evaluate] failed: " & e.msg)
    result = 1

# ---------------------------------------------------------------------------
# reconstruct — rebuild last committed projection from journal
# ---------------------------------------------------------------------------

proc cmdDebtReconstruct*(args: seq[string]): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read all committed transactions, fold events into a canonical
  ## UniverseProjection, and print universeDigest + candidate count.
  ## Usage: ax debt reconstruct <journal-path> [--at <commit-id|time>]
  echo "=== Axiom Debt Reconstruct ==="
  if args.len < 2:
    echo "usage: ax debt reconstruct <journal-path> [--at <commit-id|time>]"
    return 1
  let journalPath = args[1]
  # Parse optional --at flag
  var atTs: string
  var i = 2
  while i < args.len:
    if args[i] == "--at" and i + 1 < args.len:
      atTs = args[i + 1]
      inc i
    inc i
  try:
    let cwd = getCurrentDir()
    let fullPath = cwd / journalPath
    let txsRes = readTransactions(fullPath)
    if txsRes.isErr:
      echo "[ERROR] cannot read journal: " & txsRes.error
      return 1
    let txs = txsRes.get
    if txs.len == 0:
      echo "[INFO] no committed transactions in journal"
      echo "universeDigest: (empty)"
      echo "candidates:     0"
      return 0
    # Collect all commits; optionally filter by time.
    var commits = txs.mapIt(it.commit)
    if atTs.len > 0:
      let report = readCommitHistory(fullPath)
      let filtered = report.valid
      let opt = latestValidCommitAtOrBefore(filtered, atTs)
      if opt.isNone:
        echo "[WARN] no commit found at or before " & atTs
        echo "universeDigest: (empty)"
        echo "candidates:     0"
        return 0
      let cutoffSeq = opt.get.commitSequence
      commits = filtered.filterIt(it.commitSequence <= cutoffSeq)
    # Collect all events from matching transactions.
    var allEvents: seq[ClassificationEvent]
    for tx in txs:
      if atTs.len > 0:
        let matched = commits.anyIt(it.commitSequence == tx.commit.commitSequence)
        if matched:
          allEvents.add(tx.events)
      else:
        allEvents.add(tx.events)
    let ordered = orderedEvents(allEvents, commits)
    let proj = projectAtCommit(ordered, "v8", "")
    echo "universeDigest: " & proj.universeDigest
    echo "candidates:     " & $proj.candidates.len
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt reconstruct] failed: " & e.msg)
    result = 1

# ---------------------------------------------------------------------------
# explain — show candidate classification and leading events
# ---------------------------------------------------------------------------

proc cmdDebtExplain*(args: seq[string]): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read all committed transactions, fold events per candidate, and print
  ## the candidate's classification/status/active/firstSeen/lastSeen plus
  ## the events that led there.
  ## Usage: ax debt explain <journal-path> <candidate-id>
  echo "=== Axiom Debt Explain ==="
  if args.len < 3:
    echo "usage: ax debt explain <journal-path> <candidate-id>"
    return 1
  let journalPath = args[1]
  let candidateId = args[2]
  try:
    let cwd = getCurrentDir()
    let fullPath = cwd / journalPath
    let txsRes = readTransactions(fullPath)
    if txsRes.isErr:
      echo "[ERROR] cannot read journal: " & txsRes.error
      return 1
    let txs = txsRes.get
    if txs.len == 0:
      echo "[INFO] no committed transactions in journal"
      return 0
    let commits = txs.mapIt(it.commit)
    var allEvents: seq[ClassificationEvent]
    for tx in txs:
      allEvents.add(tx.events)
    let ordered = orderedEvents(allEvents, commits)
    let proj = projectAtCommit(ordered, "v8", "")
    # Find the candidate
    var found: Option[CandidateProjection] = none(CandidateProjection)
    for c in proj.candidates:
      if c.candidateId == candidateId:
        found = some(c)
        break
    if found.isNone:
      echo "[ERROR] candidate " & candidateId & " not found"
      echo "  available candidates (" & $proj.candidates.len & "):"
      for c in proj.candidates:
        echo "    " & c.candidateId
      return 1
    let cand = found.get
    echo "candidateId:   " & cand.candidateId
    echo "classification:" & debtClassToStr(cand.classification)
    let statusStr = if cand.active: "active" else: "resolved"
    echo "status:        " & statusStr
    echo "category:      " & cand.category
    echo "severity:      " & cand.severity
    echo "firstSeen:     " & cand.firstSeen
    echo "lastSeen:      " & cand.lastSeen
    echo ""
    echo "Leading events:"
    for oe in ordered:
      if oe.ev.candidateId == candidateId:
        echo "  [" & $oe.ev.auditSequence & "] " & oe.ev.eventId &
             " -> " & debtClassToStr(oe.ev.result) & " (seq=" & $oe.ev.auditSequence & ")"
    result = 0
  except CatchableError as e:
    logError("debt_cli", "[debt explain] failed: " & e.msg)
    result = 1

proc cmdBudgetSync*(args: seq[string]): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Sync budget metrics using the Phase 2 separated pipeline:
  ##   1. projectBudgetState() — load budgets + ledger
  ##   2. recordMetricObservations() — run evaluators, write observations journal
  ##   3. reconcileBaseline() — update ledger current/status/resolution
  ## Supports --dry-run (0-write guarantee).
  echo "=== Axiom Budget Sync ==="
  var dryRun = false
  for arg in args:
    if arg == "--dry-run":
      dryRun = true
  try:
    let updated = syncBudget(dryRun)
    result = updated
  except CatchableError as e:
    logError("debt_cli", "[budget sync] failed: " & e.msg)
    result = 1
  except Exception as e:
    logError("debt_cli", "[budget sync] failed: " & e.msg)
    result = 1

proc runDebtCli*(args: seq[string]): int {.axiomDecision.} =
  ## Entry point for `ax debt` subcommands.
  let cmd = if args.len > 0: args[0] else: ""
  case cmd
  of "sync":
    result = cmdDebtSync(if args.len > 1: args[1 .. ^1] else: @[])
  of "check":
    result = cmdDebtCheck()
  of "budget":
    result = cmdDebtBudget()
  of "budget-sync":
    result = cmdBudgetSync(args[1..^1])
  of "ledger":
    result = cmdDebtLedger()
  of "audit":
    result = cmdDebtAudit()
  of "fingerprint":
    result = cmdDebtFingerprint()
  of "classify":
    result = cmdDebtClassify()
  of "universe":
    result = cmdDebtUniverse(args)
  of "observe":
    result = cmdDebtObserve()
  of "evolve":
    result = cmdEvolve(args)
  of "drift":
    result = cmdDrift()
  of "audit-run":
    result = cmdDebtAuditRun(args)
  of "replay":
    result = cmdDebtReplay(args)
  of "re-evaluate":
    result = cmdDebtReevaluate(args)
  of "reconstruct":
    result = cmdDebtReconstruct(args)
  of "explain":
    result = cmdDebtExplain(args)
  else:
    echo "Usage: ax debt <sync|check|budget|budget-sync|ledger|audit|fingerprint|classify|universe|observe|evolve|drift|audit-run|replay|re-evaluate|reconstruct|explain>"
    echo "  sync        Sync debt registry entries (status migration, hash refresh)"
    echo "  check       Check debt registry integrity (entry count, open count, budget drift)"
    echo "  budget      Show debt budget status and drift metrics"
    echo "  budget-sync Sync budget metrics using Phase 2 separated pipeline (--dry-run supported)"
    echo "  ledger      Show the debt ledger (proc→func migration candidates)"
    echo "  audit       Canonical current-debt universe audit with classification"
    echo "  fingerprint Deterministic identity fingerprints for registry entries"
    echo "  classify    Classify each entry using the canonical classifier"
    echo "  universe    Emit a deterministic CanonicalCurrentDebtUniverse JSON document"
    echo "  observe     Convert registry entries to DebtObservation and append to evidence journal"
    echo "  evolve      Run full evidence-first classification pipeline with provenance"
    echo "  drift       Classify budget metrics as drift, never auto-promote to debt"
    echo "  audit-run   Commit decisions+events to the canonical journal and project (v8)"
    echo "              ax debt audit-run <journal-path> <projection-version> [input-root]"
    echo "  replay      Replay a committed run and verify all digests (v8)"
    echo "              ax debt replay <journal-path> <run-id> <projection-version>"
    echo "  re-evaluate Re-evaluate the latest audit input under a new rule-set hash"
    echo "  reconstruct Rebuild the last (or historical) committed projection (v8)"
    echo "              ax debt reconstruct <journal-path> [--at <commit-id|time>]"
    echo "  explain     Show candidate classification and leading events (v8)"
    echo "              ax debt explain <journal-path> <candidate-id>"
    result = 1

{.pop.}