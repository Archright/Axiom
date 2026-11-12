import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## inprocess_dispatch.nim — In-process gate dispatch with cgroups bypass
##
## Provides a lightweight dispatch path for gates that have been verified
## safe to run in-process (no external dependencies, no global mutable state).
##
## Phase C-2: InProcessGateContext + lightweight gate dispatch logic
## Phase C-3: cgroups optional bypass via AXIOM_LOW_OVERHEAD=1
##
## Architecture:
##   - Gate proc registry maps gate IDs to verified in-process procs
##   - tryDispatchInProcess() checks allowlist → calls proc directly
##   - Fallback to subprocess when gate not on allowlist
##   - AXIOM_INPROCESS_DISPATCH=off disables the in-process path
##   - AXIOM_LOW_OVERHEAD=1 skips cgroups wrapping (saves systemd-run overhead)
##
## See: docs/spec/precommit_pipeline_optimization.md

import std/times
import std/os
import std/strutils
import std/json
import std/strformat
import core/trusted/env_access
import gate/gate_types
import core/parsers/safe_parsers
import core/results
import gate/utils/gate_safety_macro
import gate/runners/trust_commit_scope_gate as runTrustCommitScopeGate  # DEBT#471 in-process adapter (no cycle: runner does not import this module)
import gate/runners/decision_binding_gate as runDecisionBindingGate  # DEBT#497 follow-up in-process adapter (no cycle: runner does not import this module)
import gate/runners/delegation_enforcer as runDelegationEnforcer  # DEBT#497 follow-up in-process adapter (no cycle: runner does not import this module)
import core/trusted/axiom_pragmas

# ─── In-Process Gate Proc Type ──────────────────────────────────────────────

type InProcessGateProc* = proc(
  ctx: InProcessGateContext
): GateResult {.gcsafe, raises: [].}

## Registry mapping gate IDs to their in-process implementations.
## Gates are added here only after:
##   1. Compile-time assertGateSignature() verification
##   2. Manual review for thread-safety
##   3. Integration test pass
## NOTE: Single-threaded orchestrator — writes only at init, reads during dispatch.
var inProcessRegistry*: seq[tuple[gateId: string, runner: InProcessGateProc]] = @[]

# ─── Registration ───────────────────────────────────────────────────────────

proc registerInProcessGate*(gateId: string; runner: InProcessGateProc) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Register a gate for in-process execution.
  ## Only call at module initialization time (not thread-safe for concurrent writes).
  inProcessRegistry.add((gateId, runner))

# ─── Lookup ─────────────────────────────────────────────────────────────────

proc findInProcessRunner(gateId: string): InProcessGateProc {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Look up an in-process runner by gate ID.
  ## Returns nil if not registered.
  for entry in inProcessRegistry:
    if entry.gateId == gateId:
      return entry.runner
  return nil

# ─── Pure helper procs for approved light gates ─────────────────────────────

const
  DebtArchitecturePath = "data/architecture_debt.json"
  DebtRegistryPath = "data/debt_registry.json"
  DebtLedgerPath = "data/debt_ledger.json"
  DebtDefaultCriticalThreshold = 20
  DocAgmdPath = "AGENTS.md"
  DocRequiredSections = ["§0.", "§1.", "§2.", "§3."]
  DocRequiredDocs = [
    "docs/agents/architecture.md",
    "docs/agents/core_rules.md",
    "docs/agents/rules_workflow.md",
  ]
  DocHistoryDir = "docs/history/"

proc readFileAt*(repoRoot, relPath, label: string): string {.gcsafe, raises: [].} =
  try:
    result = readFile(repoRoot / relPath)
  except CatchableError:
    result = ""

proc jsonString*(node: JsonNode): string {.gcsafe, raises: [].} =
  if node == nil or node.kind != JString:
    return ""
  result = node.getStr("")

proc jsonInt*(node: JsonNode): int {.gcsafe, raises: [].} =
  if node == nil or node.kind != JInt:
    return 0
  result = node.getInt(0)

proc jsonField*(node: JsonNode; key: string): JsonNode {.gcsafe, raises: [].} =
  if node == nil or not node.hasKey(key):
    return nil
  try:
    result = node[key]
  except CatchableError:
    return nil

proc allAsciiDigit*(s: string): bool {.gcsafe, raises: [].} =
  if s.len == 0:
    return false
  for c in s:
    if c notin {'0'..'9'}:
      return false
  true

proc validateDebtArchitectureImpl(content: string; relPath: string; findings: var seq[string]) {.gcsafe, raises: [].} =
  var json: JsonNode
  try:
    json = parseJson(content)
  except CatchableError:
    findings.add(relPath & ": Invalid JSON")
    return

  let versionNode = jsonField(json, "version")
  if versionNode == nil:
    findings.add(relPath & ": Missing required key: 'version'")
  elif versionNode.kind != JInt:
    findings.add(relPath & ": 'version' must be int")

  let entriesNode = jsonField(json, "entries")
  if entriesNode == nil:
    findings.add(relPath & ": Missing required key: 'entries'")
  elif entriesNode.kind != JArray:
    findings.add(relPath & ": 'entries' must be array")
  else:
    for idx in 0..<entriesNode.len:
      let entry = entriesNode[idx]
      if entry.kind != JObject:
        findings.add(&"{relPath}: entries[{idx}] must be object")
        continue
      if jsonString(entry{"file"}).len == 0:
        findings.add(&"{relPath}: entries[{idx}].file must be non-empty string")
      if jsonInt(entry{"count"}) <= 0:
        findings.add(&"{relPath}: entries[{idx}].count must be > 0")
      if jsonString(entry{"firstSeen"}).len == 0:
        findings.add(&"{relPath}: entries[{idx}].firstSeen must be string")
      if jsonString(entry{"lastSeen"}).len == 0:
        findings.add(&"{relPath}: entries[{idx}].lastSeen must be string")
      if jsonString(entry{"contentHash"}).len == 0:
        findings.add(&"{relPath}: entries[{idx}].contentHash must be string")

proc validateDebtRegistryImpl(content: string; relPath: string; findings: var seq[string]) {.gcsafe, raises: [].} =
  var json: JsonNode
  try:
    json = parseJson(content)
  except CatchableError:
    findings.add(relPath & ": Invalid JSON")
    return

  let entriesNode = jsonField(json, "entries")
  if entriesNode == nil:
    findings.add(relPath & ": Missing required key: 'entries'")
    return
  if entriesNode.kind != JArray:
    findings.add(relPath & ": 'entries' must be array")
    return

  for idx in 0..<entriesNode.len:
    let entry = entriesNode[idx]
    if entry.kind != JObject:
      findings.add(&"{relPath}: entries[{idx}] must be object")
      continue
    let id = jsonString(entry{"id"})
    if id.len == 0 or not id.startsWith("DEBT#") or not allAsciiDigit(id[5 .. ^1]):
      findings.add(&"{relPath}: entries[{idx}].id must be DEBT#digits")
    let severity = jsonString(entry{"severity"})
    if severity notin ["critical", "high", "medium", "low"]:
      findings.add(&"{relPath}: entries[{idx}].severity must be critical|high|medium|low")
    let status = jsonString(entry{"status"})
    if status notin ["open", "closed", "deferred", "resolved"]:
      findings.add(&"{relPath}: entries[{idx}].status must be open|closed|deferred|resolved")
    if jsonString(entry{"category"}).len == 0:
      findings.add(&"{relPath}: entries[{idx}].category must be non-empty string")
    if jsonString(entry{"description"}).len == 0:
      findings.add(&"{relPath}: entries[{idx}].description must be non-empty string")

proc validateDebtLedgerImpl(content: string; relPath: string; findings: var seq[string]) {.gcsafe, raises: [].} =
  var json: JsonNode
  try:
    json = parseJson(content)
  except CatchableError:
    findings.add(relPath & ": Invalid JSON")
    return

  # Version: must be exactly "1.1.0" — fail-closed
  let versionNode = jsonField(json, "version")
  if versionNode == nil or versionNode.kind != JString:
    findings.add(relPath & ": 'version' must be string")
    return
  if versionNode.getStr() != "1.1.0":
    findings.add(relPath & ": version must be '1.1.0', got '" & versionNode.getStr() & "'")
    return

  # Records array: required
  let recordsNode = jsonField(json, "records")
  if recordsNode == nil or recordsNode.kind != JArray:
    findings.add(relPath & ": Missing or invalid 'records' array")
    return

  for idx in 0..<recordsNode.len:
    let entry = recordsNode[idx]
    if entry.kind != JObject:
      findings.add(&"{relPath}: records[{idx}] must be object")
      continue

    # id: BUDGET#NNN
    let idStr = jsonString(entry{"id"})
    if idStr.len == 0:
      findings.add(&"{relPath}: records[{idx}].id must be non-empty string")
    elif not idStr.startsWith("BUDGET#") or idStr.len != 10 or not allAsciiDigit(idStr[7 .. ^1]):
      findings.add(&"{relPath}: records[{idx}].id: invalid format '{idStr}', expected BUDGET#NNN")

    # category: must be "BudgetCategory"
    let category = jsonString(entry{"category"})
    if category != "BudgetCategory":
      findings.add(&"{relPath}: records[{idx}].category must be 'BudgetCategory'")

    # description: non-empty string
    if jsonString(entry{"description"}).len == 0:
      findings.add(&"{relPath}: records[{idx}].description must be non-empty string")

    # budgetCategory: enum membership
    let budgetCategory = jsonString(entry{"budgetCategory"})
    if budgetCategory notin ["bcImportLint", "bcLayerViolation", "bcEffectViolation",
                                 "bcNimtryViolation", "bcDebtRegistryOpen", "bcDebtRegistryClosed"]:
      findings.add(&"{relPath}: records[{idx}].budgetCategory: invalid value '{budgetCategory}'")

    # metric: non-empty string
    if jsonString(entry{"metric"}).len == 0:
      findings.add(&"{relPath}: records[{idx}].metric must be non-empty string")

    # baseline: int ≥ 0
    if entry{"baseline"}.kind != JInt:
      findings.add(&"{relPath}: records[{idx}].baseline must be int")
    elif jsonInt(entry{"baseline"}) < 0:
      findings.add(&"{relPath}: records[{idx}].baseline must be ≥ 0")

    # target: int ≥ 0
    if entry{"target"}.kind != JInt:
      findings.add(&"{relPath}: records[{idx}].target must be int")
    elif jsonInt(entry{"target"}) < 0:
      findings.add(&"{relPath}: records[{idx}].target must be ≥ 0")

    # current: int ≥ 0
    if entry{"current"}.kind != JInt:
      findings.add(&"{relPath}: records[{idx}].current must be int")
    elif jsonInt(entry{"current"}) < 0:
      findings.add(&"{relPath}: records[{idx}].current must be ≥ 0")

    # severity: low|medium|high
    let severity = jsonString(entry{"severity"})
    if severity notin ["low", "medium", "high"]:
      findings.add(&"{relPath}: records[{idx}].severity must be low|medium|high")

    # source: non-empty string
    if jsonString(entry{"source"}).len == 0:
      findings.add(&"{relPath}: records[{idx}].source must be non-empty string")

    # status: open|closed
    let status = jsonString(entry{"status"})
    if status notin ["open", "closed"]:
      findings.add(&"{relPath}: records[{idx}].status must be open|closed")

    # resolution: WONT_FIX|FIXED
    let resolution = jsonString(entry{"resolution"})
    if resolution notin ["WONT_FIX", "FIXED"]:
      findings.add(&"{relPath}: records[{idx}].resolution must be WONT_FIX|FIXED")

    # lastVerifiedAt: non-empty string
    if jsonString(entry{"lastVerifiedAt"}).len == 0:
      findings.add(&"{relPath}: records[{idx}].lastVerifiedAt must be non-empty string")

proc collectArchDebtPaths(registryJson: JsonNode): seq[string] {.gcsafe, raises: [].} =
  let entriesNode = jsonField(registryJson, "entries")
  if entriesNode == nil:
    return
  for entry in entriesNode:
    if entry.kind == JObject:
      let file = jsonString(entry{"file"})
      if file.len > 0:
        result.add(file)

proc collectOpenCriticalFiles(registryJson: JsonNode): seq[string] {.gcsafe, raises: [].} =
  let entriesNode = jsonField(registryJson, "entries")
  if entriesNode == nil:
    return
  for entry in entriesNode:
    if entry.kind != JObject:
      continue
    if jsonString(entry{"status"}) == "open" and jsonString(entry{"severity"}) == "critical":
      let files = entry{"files"}
      if files.kind == JArray:
        for fileNode in files:
          let raw = jsonString(fileNode)
          for part in raw.split(","):
            var p = part.strip()
            let parenStart = p.find('(')
            if parenStart >= 0:
              p = p[0 ..< parenStart].strip()
            if p.endsWith("."):
              p = p[0 ..< ^1].strip()
            if p.len > 0 and not p.endsWith(".nim") and not p.contains('.'):
              p.add("/")
            if p.len > 0:
              result.add(p)

proc fileMatchesDebtRef(archPath, refPath: string): bool {.gcsafe, raises: [].} =
  if archPath.len == 0 or refPath.len == 0:
    return false
  if archPath == refPath:
    return true
  if archPath.endsWith(refPath) or refPath.endsWith(archPath):
    return true
  archPath.contains(refPath) or refPath.contains(archPath)

proc validateDebtAllImpl(archContent, registryContent, ledgerContent: string;
                         criticalThreshold: int): seq[string] {.gcsafe, raises: [].} =
  var findings: seq[string] = @[]
  validateDebtArchitectureImpl(archContent, DebtArchitecturePath, findings)
  validateDebtRegistryImpl(registryContent, DebtRegistryPath, findings)
  validateDebtLedgerImpl(ledgerContent, DebtLedgerPath, findings)

  if findings.len > 0:
    return findings

  var archJson: JsonNode
  var registryJson: JsonNode
  try:
    archJson = parseJson(archContent)
    registryJson = parseJson(registryContent)
  except CatchableError:
    findings.add("Cross-file debt validation failed to parse JSON")
    return findings

  let openCriticalFiles = collectOpenCriticalFiles(registryJson)
  let archFiles = collectArchDebtPaths(registryJson)

  for critRef in openCriticalFiles:
    var found = false
    for archPath in archFiles:
      if fileMatchesDebtRef(archPath, critRef):
        found = true
        break
    if not found:
      findings.add(&"Open critical registry ref '{critRef}' has no matching file in {DebtArchitecturePath}")

  if openCriticalFiles.len > criticalThreshold:
    findings.add(&"Open critical count {openCriticalFiles.len} exceeds threshold {criticalThreshold}")

  findings

proc runDebtCtGateInProcess*(ctx: InProcessGateContext): GateResult {.gcsafe, raises: [].} =
  ## Debt CT validation using the fixed data-file slice.
  ## No git subprocess, no quit(), no global mutation.
  result = GateResult(
    ok: true,
    name: "debt-ct-gate",
    stdout: "",
    duration: initDuration(),
    failureReason: "")

  var findings: seq[string] = @[]
  var archContent = ""
  var registryContent = ""
  var ledgerContent = ""

  for relPath in [DebtArchitecturePath, DebtRegistryPath, DebtLedgerPath]:
    let absPath = ctx.repoRoot / relPath
    if not fileExists(absPath):
      findings.add("Missing required file: " & relPath)
      continue
    let content = readFileAt(ctx.repoRoot, relPath, "debt-ct-gate")
    if content.len == 0:
      findings.add("Empty required file: " & relPath)
      continue
    case relPath
    of DebtArchitecturePath: archContent = content
    of DebtRegistryPath: registryContent = content
    of DebtLedgerPath: ledgerContent = content

  if findings.len == 0:
    var criticalThreshold = DebtDefaultCriticalThreshold
    let envThreshold = getAxiomEnv(evCriticalDebtThreshold, "")
    if envThreshold.len > 0:
      let thresholdRes = safeParseInt(envThreshold)
      if thresholdRes.isOk:
        criticalThreshold = thresholdRes.get

    let errors = validateDebtAllImpl(archContent, registryContent, ledgerContent, criticalThreshold)
    for err in errors:
      findings.add(err)

  if findings.len > 0:
    result.ok = false
    result.stdout = findings.join("\n")
    result.failureReason = "Debt CT validation failed"
  else:
    result.stdout = "All debt JSON validation checks passed."

proc hasRecentDocHistory(repoRoot: string): bool {.gcsafe, raises: [].} =
  let historyDir = repoRoot / DocHistoryDir
  if not dirExists(historyDir):
    return false
  try:
    for entry in walkDir(historyDir):
      if entry.kind == pcFile and entry.path.endsWith(".md"):
        return true
  except OSError:
    return false
  false

proc runDocCompletenessGateInProcess*(ctx: InProcessGateContext): GateResult {.gcsafe, raises: [].} =
  ## Documentation completeness gate using direct file reads.
  ## No git subprocess, no quit(), no global mutation.
  result = GateResult(
    ok: true,
    name: "doc-completeness-gate",
    stdout: "",
    duration: initDuration(),
    failureReason: "")

  var findings: seq[string] = @[]
  let agmdPath = ctx.repoRoot / DocAgmdPath
  if not fileExists(agmdPath):
    findings.add("Missing required documentation: AGENTS.md")
  else:
    let content = readFileAt(ctx.repoRoot, DocAgmdPath, "doc-completeness-gate")
    for section in DocRequiredSections:
      if section notin content:
        findings.add("AGENTS.md missing section: " & section)

  for docPath in DocRequiredDocs:
    let absPath = ctx.repoRoot / docPath
    if not fileExists(absPath):
      findings.add("Missing required documentation: " & docPath)

  if fileExists(ctx.repoRoot / ".git/MERGE_HEAD"):
    findings.add("Merge commit in progress; local-sync discipline requires ax git sync (main landing is the GitHub native MERGE actuator)")

  var changedNim = false
  for f in ctx.stagedFiles:
    if f.endsWith(".nim"):
      changedNim = true
      break

  if changedNim and not hasRecentDocHistory(ctx.repoRoot):
    result.stdout = "WARN: src/*.nim changed but no recent docs/history was found"
  else:
    result.stdout = "Documentation completeness checks passed."

  if findings.len > 0:
    result.ok = false
    result.stdout = findings.join("\n")
    result.failureReason = "Documentation completeness failed"

proc runGateInProcess*(ctx: InProcessGateContext): GateResult {.gcsafe, raises: [].} =
  ## Dispatch an allowlisted light gate without spawning a subprocess.
  case ctx.gateId
  of "debt-ct-gate":
    return runDebtCtGateInProcess(ctx)
  of "doc-completeness-gate":
    return runDocCompletenessGateInProcess(ctx)
  of "trust-commit-scope":
    # DEBT#471: delegate to the runner's single judgment SSOT. A standalone AOT
    # link of a registerGate-only runner produces an empty binary, so this
    # in-process path is the enforcement path for this gate.
    return runTrustCommitScopeGate.runInProcess(ctx)
  of "decision-binding-gate":
    # DEBT#497 follow-up: same closure shape as trust-commit-scope — the
    # runner module has no standalone main (registerGate-only shape), so the
    # subprocess CAS binary is an empty exit-0 shell. Delegate to the runner's
    # single judgment SSOT via its in-process adapter.
    return runDecisionBindingGate.runInProcess(ctx)
  of "delegation-enforcer":
    # DEBT#497 follow-up: main() was never invoked at top level (hollow
    # standalone link). judgeWireLogs is the same judgment main() runs,
    # value-returning instead of quit()-coded.
    return runDelegationEnforcer.runInProcess(ctx)
  else:
    return GateResult(
      ok: false,
      name: "",
      stdout: "Gate not registered for in-process dispatch: " & ctx.gateId,
      stderr: "",
      duration: initDuration())

# ─── Dispatch ───────────────────────────────────────────────────────────────

proc isInProcessDispatchEnabled*(): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## AXIOM_INPROCESS_DISPATCH controls the fast path.
  ## Default is enabled; set "off", "0", "false", or "no" to force subprocess fallback.
  let mode = getAxiomEnv(evInProcessDispatch, "1").toLowerAscii()
  case mode
  of "1", "true", "yes", "on":
    return true
  of "0", "false", "no", "off":
    return false
  else:
    return true

proc tryDispatchInProcess*(
  gate: GateConfig;
  ctx: InProcessGateContext
): tuple[dispatched: bool; gateResult: GateResult] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Attempt in-process dispatch for a gate.
  ## Returns (true, result) if the gate was dispatched in-process.
  ## Returns (false, default) if the gate must fall back to subprocess.
  ## NOTE: Single-threaded orchestrator — no gcsafe annotation needed.
  if not isInProcessDispatchEnabled():
    return (false, default(GateResult))

  if not isLightGateAllowed(gate.id):
    return (false, default(GateResult))

  let runner = findInProcessRunner(gate.id)
  if runner != nil:
    let start = getTime()
    var gr = runner(ctx)
    gr.duration = getTime() - start
    return (true, gr)

  let start = getTime()
  var gr = runGateInProcess(ctx)
  gr.duration = getTime() - start
  return (true, gr)

# ─── cgroups Bypass ─────────────────────────────────────────────────────────

proc isLowOverheadMode*(): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if low-overhead mode is active.
  ## When active, cgroups wrapping is skipped to avoid systemd-run overhead.
  ## Activate via: AXIOM_LOW_OVERHEAD=1
  try:
    return getAxiomEnv(evLowOverhead) == "1"
  except CatchableError:
    return false

proc wrapWithCgroupsIfNeeded*(cmd: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Conditionally wrap a command with cgroups.
  ## Returns the original command unchanged if low-overhead mode is active
  ## or if systemd-run is unavailable.
  if isLowOverheadMode():
    return cmd
  # Delegate to the existing cgroups wrapper
  try:
    let systemdRun = findExe("systemd-run")
    if systemdRun.len == 0:
      return cmd
    return systemdRun &
      " --user --scope --slice=axiom-gate" &
      " --property=CPUQuota=50%" &
      " --property=IOWeight=10" &
      " --property=MemoryHigh=6G" &
      " --property=MemoryMax=8G" &
      " --property=RuntimeMaxSec=300s" &
      " --quiet --collect" &
      " -- " & cmd
  except CatchableError:
    return cmd

{.pop.}
