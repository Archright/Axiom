import core/trusted/layer_declaration
axiomLayer "domain"
import core/audit/sad_gate
import core/interfaces/file_io_executor
import core/pure/json_parse
import std/[times, strutils]
import std/json except parseJson
import core/axiom_pragmas
import core/macros/best_effort
# axiomIoBoundary


let fileIo* = SystemFileIoExecutor()
type
  SystemState* = enum
    ssHardening     ## Radius growing, legacy migration active
    ssAutotuning    ## Radius >= 50, Z3 telemetry collection
    ssOptimizing    ## Radius >= 75, CEGAR auto-tuning
    ssEnforced      ## Radius = TargetRadius, all modules enforced

  FacadeEntry = object
    path: string
    deprecationDate: string
    reason: string
const
  AutotuningThreshold* = 50
  OptimizationThreshold* = 75
  AutotuningMinRecords* = 100
  FacadeExpiryWarningDays* = 14  # Warn 14 days before expiry
# ── State Machine Core ───────────────────────────────────────────────

proc evaluateSystemState*(): SystemState {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic: same date → same state.
  let radius = calculateEnforcementRadius()
  if radius >= TargetRadius:
    result = ssEnforced
  elif radius >= OptimizationThreshold:
    result = ssOptimizing
  elif radius >= AutotuningThreshold:
    result = ssAutotuning
  else:
    result = ssHardening
proc formatStateReport*(state: SystemState; radius: int): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Format governance state for CI output.
  let daysLeft = daysUntilEnforcement()
  result = "[Governance] State: " & $state &
           " | Radius: " & $radius & "/" & $TargetRadius &
           " | Days left: " & $daysLeft
proc readTopologyLockModules(): seq[FacadeEntry] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""parse topology.lock — empty result on corrupt json""").} =
  ## Read deprecation_date from topology.lock modules (if present).
  result = @[]
  if not fileIo.fileExists("topology.lock"):
    return
  let content = fileIo.readFile("topology.lock")
  if content.len == 0:
    return
  var node: JsonNode
  try:
    node = pureParseJson(content)
  except CatchableError:
    return
  let modules = node.getOrDefault("modules")
  if modules == nil or modules.kind != JObject:
    return
  for key, val in modules.pairs:
    if val.kind != JObject:
      continue
    let currentPath = val.getOrDefault("currentPath").getStr("")
    let deprecationDate = val.getOrDefault("deprecation_date").getStr("")
    let reason = val.getOrDefault("deprecation_reason").getStr("")
    if deprecationDate.len > 0:
      result.add(FacadeEntry(
        path: currentPath,
        deprecationDate: deprecationDate,
        reason: reason
      ))
proc checkFacadeExpirations*(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""date parse failure — skip malformed facade entry""").} =
  ## Check for expired or soon-to-expire facades.
  ## Returns warning messages for CI output.
  result = @[]
  let today = now()
  let facades = readTopologyLockModules()

  for facade in facades:
    try:
      let expiryDate = parse(facade.deprecationDate, "yyyy-MM-dd")
      let daysUntilExpiry = (expiryDate - today).inDays

      if daysUntilExpiry < 0:
        # Expired — escalate warning to error
        result.add("[FACADE EXPIRED] " & facade.path &
                   " deprecation date passed " & $(-daysUntilExpiry) &
                   " days ago. " & facade.reason &
                   " — Consider removing or migrating.")
      elif daysUntilExpiry <= FacadeExpiryWarningDays:
        # Soon to expire — warning
        result.add("[FACADE WARNING] " & facade.path &
                   " expires in " & $daysUntilExpiry &
                   " days (" & facade.deprecationDate & "). " &
                   facade.reason)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
proc countTelemetryRecords(): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Count records in z3_telemetry.jsonl.
  let path = "logs/z3_telemetry.jsonl"
  if not fileIo.fileExists(path):
    return 0
  let fileLines = fileIo.readLines(path)
  var count = 0
  for line in fileLines:
    if line.strip().len > 0:
      inc count
  result = count
proc shouldTriggerAutotuning*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if autotuning should be triggered.
  ## Conditions: radius >= 50 AND telemetry records >= 100.
  let radius = calculateEnforcementRadius()
  if radius < AutotuningThreshold:
    return false
  let records = countTelemetryRecords()
  result = records >= AutotuningMinRecords
proc runGovernanceCycle*(): tuple[state: SystemState; radius: int; messages: seq[string]] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute a complete governance cycle.
  ## Called from: make audit, CI pre-commit, ax prove.
  let state = evaluateSystemState()
  let radius = calculateEnforcementRadius()
  var messages: seq[string] = @[]

  # State report
  messages.add(formatStateReport(state, radius))

  # 1. Facade expiry check (all states)
  let facadeWarnings = checkFacadeExpirations()
  messages.add(facadeWarnings)

  # 2. Autotuning trigger (ssAutotuning and above)
  if state >= ssAutotuning:
    if shouldTriggerAutotuning():
      messages.add("[Governance] Z3 autotuning triggered — sufficient telemetry data.")
    else:
      let records = countTelemetryRecords()
      messages.add("[Governance] Z3 telemetry: " & $records & "/" & $AutotuningMinRecords & " records.")

  # 3. Optimization status (ssOptimizing and above)
  if state >= ssOptimizing:
    messages.add("[Governance] CEGAR optimization active — data-driven tuning enabled.")

  # 4. Full enforcement (ssEnforced)
  if state == ssEnforced:
    messages.add("[Governance] Full enforcement active — all modules require tests.")

  result = (state: state, radius: radius, messages: messages)
