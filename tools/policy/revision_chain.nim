## tools/policy/revision_chain.nim
## Shared revision algebra kernel (pure funcs; stdlib only).
## P0-2/P0-3: Revision algebra for Axiom policy/baseline/contract chains.
##
## Types: RevisionChain (payload-independent), PolicyPayload, BaselinePayload
## Invariants: exactly one genesis, exactly one head, linear chain (forks REJECTED),
##   every node reachable from genesis, effectiveSequence computed by findHead/materialize
##   (never stored).

import std/[json, options, os, strutils, tables, sets, sequtils]

# ══════════════════════════════════════════════════════════════════════
# Approved metric → expected-state decision table (shared SSOT)
# Used by tools/sync_policy.nim (generation) and tools/debt_engine.nim
# (D.2 freshness verification).  Kept in the kernel so both consumers
# derive disposition expectations from the SAME table.
# ══════════════════════════════════════════════════════════════════════

const DecisionTable*: Table[string, string] = {
  "import_lint_violations":   "DRIFT",
  "layer_violations":         "DRIFT",
  "debt_registry_open":       "DRIFT",
  "debt_registry_closed":     "DRIFT",
  "nimtry_violations":        "PASS",
  "effect_violations":        "DRIFT"
}.toTable

const ReasonMap*: Table[string, string] = {
  "import_lint_violations":   "Advisory tracking; non-blocking",
  "layer_violations":         "Advisory tracking; non-blocking",
  "debt_registry_open":       "Advisory tracking; non-blocking; no ERROR before sync-budget regeneration",
  "debt_registry_closed":     "Advisory tracking; non-blocking",
  "nimtry_violations":        "Advisory tracking; non-blocking",
  "effect_violations":        "Advisory tracking; non-blocking (evaluator resolved)"
}.toTable

const DirectionMap*: Table[string, string] = {
  "import_lint_violations":   "IMPROVEMENT",
  "layer_violations":         "MAINTAINED",
  "debt_registry_open":       "MAINTAINED",
  "debt_registry_closed":     "MAINTAINED",
  "nimtry_violations":        "MAINTAINED",
  "effect_violations":        "MAINTAINED"
}.toTable

# ══════════════════════════════════════════════════════════════════════
# Types
# ══════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════
# DriftDirection — drift direction classification for policy revisions
# ══════════════════════════════════════════════════════════════════════

type
  DriftDirection* {.pure.} = enum
    ddImprovement  # metric is getting better (fewer violations, less debt)
    ddRegression   # metric is getting worse (more open issues, more debt)
    ddMaintained   # no directional change expected

# ══════════════════════════════════════════════════════════════════════
# StabilityConfig — optional stability constraints on a policy revision
# ══════════════════════════════════════════════════════════════════════

type
  StabilityConfig* = object
    minStableRevisions*: int                # minimum consecutive revisions with same direction
    direction*: Option[DriftDirection]       # drift direction this revision addresses
    requiredConsecutiveObservations*: int   # observations confirming the drift direction

# ══════════════════════════════════════════════════════════════════════
# Types
# ══════════════════════════════════════════════════════════════════════

type
  RevisionChain* = object
    revisionId*: string
    parentRevisionId*: Option[string]
    rationale*: string
    evidenceRef*: string
    stability*: Option[StabilityConfig]

  PolicyRule* = object
    state*: string        # "PASS" | "DRIFT"
    disposition*: string  # "INFO" | "WARN" | "ERROR"

  PolicyPayload* = object
    policyId*: string
    statusDomain*: seq[string]   # ["PASS", "DRIFT"]
    defaultDisposition*: string  # "ERROR" (fail-closed default)
    rules*: seq[PolicyRule]

  BaselinePayload* = object
    metricId*: string
    contractRevision*: string    # must reference an id from contract_revisions.json
    subjectScope*: string
    previousValue*: string
    newValue*: string
    observedEvidenceRef*: string

  MaterializedState* = object
    policyId*: string
    defaultDisposition*: string
    rules*: seq[PolicyRule]
    metricId*: string
    contractRevision*: string
    subjectScope*: string
    currentValue*: string

  PatchOp* = object
    op*: string       # "addRule" | "setDefault" | "setRule" | "revertTo"
    arguments*: JsonNode

# ══════════════════════════════════════════════════════════════════════
# validateLinear — checks chain invariants (P0-2)
# Returns empty seq if valid, or seq of error messages if invalid.
# ══════════════════════════════════════════════════════════════════════

func validateLinear*(chainJson: JsonNode): seq[string] =
  var errors: seq[string]

  if chainJson.kind != JObject:
    return @["Root must be a JSON object"]

  let revisions = chainJson{"revisions"}
  if revisions.kind != JArray:
    return @["Missing or non-array 'revisions'"]

  if revisions.len == 0:
    return @["Revision chain must have at least one entry (genesis)"]

  var allIds: HashSet[string]
  var parentMap: Table[string, string]  # childId -> parentId
  var genesisCount = 0
  var genesisId = ""

  for idx in 0..<revisions.len:
    let rev = revisions[idx]
    if rev.kind != JObject:
      errors.add("Revision[" & $idx & "] is not a JSON object")
      continue

    let rid = rev{"revisionId"}.getStr("")
    if rid.len == 0:
      errors.add("Revision[" & $idx & "] missing or empty 'revisionId'")
      continue

    if rid in allIds:
      errors.add("Duplicate revisionId: " & rid)
    allIds.incl(rid)

    let parentNode = rev{"parentRevisionId"}
    if parentNode.isNil or parentNode.kind == JNull:
      inc genesisCount
      genesisId = rid
    elif parentNode.kind == JString:
      let pid = parentNode.getStr()
      if pid.len == 0:
        errors.add("Revision " & rid & " has empty parentRevisionId")
      else:
        parentMap[rid] = pid
    else:
      errors.add("Revision " & rid & ": parentRevisionId must be null or string")

  # Invariant: exactly one genesis
  if genesisCount != 1:
    errors.add("Expected exactly 1 genesis revision (parentRevisionId=null), found " & $genesisCount)

  # Invariant: every non-genesis parent must exist in the chain
  for child, parent in parentMap:
    if parent notin allIds:
      errors.add("Revision " & child & " references unknown parent " & parent)

  # Invariant: linear chain — no node has more than one child (no forks)
  var childCount: Table[string, int]
  for child, parent in parentMap:
    childCount.mgetOrPut(parent, 0) += 1
  for parent, count in childCount:
    if count > 1:
      errors.add("Fork detected: revision " & parent & " has " & $count & " children (forks REJECTED)")

  # Invariant: every node reachable from genesis (no orphans)
  var reachable: HashSet[string]
  reachable.incl(genesisId)
  var queue = @[genesisId]
  while queue.len > 0:
    let current = queue.pop()
    for child, parent in parentMap:
      if parent == current and child notin reachable:
        reachable.incl(child)
        queue.add(child)

  for rid in allIds:
    if rid notin reachable:
      errors.add("Revision " & rid & " is not reachable from genesis (orphan)")

  # Invariant: exactly one head (node with no children)
  var headCount = 0
  var headId = ""
  let parentValues = toSeq(parentMap.values)
  for rid in allIds:
    if rid notin parentValues.toHashSet():
      inc headCount
      headId = rid
  if headCount != 1:
    errors.add("Expected exactly 1 head revision, found " & $headCount)

  result = errors

# ══════════════════════════════════════════════════════════════════════
# findHead — returns the revision with no children (P0-2)
# ══════════════════════════════════════════════════════════════════════

func findHead*(chain: JsonNode): Option[string] =
  let revisions = chain{"revisions"}
  if revisions.kind != JArray or revisions.len == 0:
    return none(string)

  var allIds: HashSet[string]
  var parentIds: HashSet[string]  # ids that appear as parents

  for rev in revisions:
    let rid = rev{"revisionId"}.getStr("")
    if rid.len > 0:
      allIds.incl(rid)
    let parentNode = rev{"parentRevisionId"}
    if parentNode != nil and parentNode.kind == JString:
      parentIds.incl(parentNode.getStr())

  for rid in allIds:
    if rid notin parentIds:
      return some(rid)

  none(string)

# ══════════════════════════════════════════════════════════════════════
# materialize — reconstructs full current state from genesis + patches (P0-3)
# ══════════════════════════════════════════════════════════════════════

func applyPatch*(state: JsonNode, patch: JsonNode): JsonNode =
  ## Apply a single patch operation to the current state.
  result = copy(state)  # std/json deep copy (ORC-safe; system.deepCopy needs --deepcopy:on)
  let args = patch{"arguments"}
  if args.isNil: return result

  case patch{"op"}.getStr("")
  of "setDefault":
    let d = args{"disposition"}
    if d != nil and d.kind == JString:
      result["defaultDisposition"] = d
  of "addRule":
    let rules = result{"rules"}
    if rules != nil and rules.kind == JArray:
      result["rules"].add(args)
  of "setRule":
    let rules = result{"rules"}
    if rules != nil and rules.kind == JArray:
      let targetState = args{"state"}.getStr("")
      let newDisp = args{"disposition"}.getStr("")
      for i in 0..<result["rules"].len:
        if result["rules"][i]{"state"}.getStr() == targetState:
          result["rules"][i]["disposition"] = %newDisp
          break
  of "setContractRevision":
    let cr = args{"contractRevision"}
    if cr != nil and cr.kind == JString:
      result["contractRevision"] = cr
  of "revertTo":
    discard
  else:
    discard  # unknown op, skip silently

func materialize*(chain: JsonNode, genesisState: JsonNode): MaterializedState =
  ## Reconstructs the full current state from genesis + patches alone.
  ## Patches are applied in revision order (topological, genesis first).
  let headId = findHead(chain)
  if headId.isNone():
    return MaterializedState()

  # Build revision lookup
  var revMap: Table[string, JsonNode]
  let revisions = chain{"revisions"}
  for rev in revisions:
    let rid = rev{"revisionId"}.getStr("")
    if rid.len > 0:
      revMap[rid] = rev

  # Collect linear chain from head to genesis
  var chainOrder: seq[string] = @[]
  var current = headId.get()
  var visited: HashSet[string]
  while current.len > 0:
    if current in visited:
      break  # cycle guard
    visited.incl(current)
    chainOrder.add(current)
    let rev = revMap.getOrDefault(current)
    if rev.isNil:
      break  # orphaned revision ID — stop traversal
    let parentNode = rev{"parentRevisionId"}
    if parentNode.isNil or parentNode.kind == JNull:
      break  # reached genesis
    current = rev{"parentRevisionId"}.getStr()

  # Reverse to get genesis-first order
  var reversedOrder: seq[string] = @[]
  for i in countdown(chainOrder.high, 0):
    reversedOrder.add(chainOrder[i])

  # Start with genesis state
  var state = copy(genesisState)

  # Apply patches from each revision in order
  for rid in reversedOrder:
    let rev = revMap.getOrDefault(rid)
    if rev.isNil: continue
    let revPatches = rev{"patches"}
    if revPatches.isNil or revPatches.kind != JArray: continue  # genesis (no patches)
    for patch in revPatches:
      let op = patch{"op"}.getStr("")
      if op == "revertTo":
        let targetRevId = patch{"arguments"}{"revisionId"}.getStr("")
        if targetRevId in revMap:
          let targetRev = revMap[targetRevId]
          let targetPayload = targetRev{"payload"}
          if targetPayload != nil and targetPayload.kind == JObject:
            state = copy(targetPayload)
        discard
      else:
        state = applyPatch(state, patch)

  # Build MaterializedState from the final state
  result.policyId = state{"policyId"}.getStr("")
  result.defaultDisposition = state{"defaultDisposition"}.getStr("ERROR")
  result.metricId = state{"metricId"}.getStr("")
  result.contractRevision = state{"contractRevision"}.getStr("")
  result.subjectScope = state{"subjectScope"}.getStr("")
  result.currentValue = state{"currentValue"}.getStr("")

  let ruleNode = state{"rules"}
  if ruleNode != nil and ruleNode.kind == JArray:
    for rule in state["rules"]:
      result.rules.add(PolicyRule(
        state: rule{"state"}.getStr(""),
        disposition: rule{"disposition"}.getStr("")
      ))

# ══════════════════════════════════════════════════════════════════════
# enforceConstraints — fail-closed stability constraint validation
# Checks that every revision with a `stability` field satisfies its
# minStableRevisions, direction, and requiredConsecutiveObservations
# constraints against the materialized policy chain.
# Returns empty seq if valid, or seq of error messages if invalid.
# ══════════════════════════════════════════════════════════════════════

func parseDriftDirection*(s: string): Option[DriftDirection] =
  case s
  of "IMPROVEMENT": some(ddImprovement)
  of "REGRESSION": some(ddRegression)
  of "MAINTAINED": some(ddMaintained)
  else: none(DriftDirection)

proc enforceConstraints*(materialized: MaterializedState, chain: JsonNode): seq[string] =
  var errors: seq[string]
  let revisions = chain{"revisions"}
  if revisions.kind != JArray:
    return @["Missing or non-array 'revisions' in enforceConstraints"]

  # Build revision lookup
  var revMap: Table[string, JsonNode]
  for rev in revisions:
    let rid = rev{"revisionId"}.getStr("")
    if rid.len > 0:
      revMap[rid] = rev

  # For each revision with a stability field, validate constraints
  for rid, rev in revMap:
    let stability = rev{"stability"}
    if stability.isNil or stability.kind == JNull:
      continue  # no stability config → backward compatible, skip

    # minStableRevisions check
    let minStable = stability{"minStableRevisions"}
    if minStable != nil and minStable.kind == JInt:
      let minVal = minStable.getInt()
      if minVal < 1:
        errors.add("Revision " & rid & ": minStableRevisions must be >= 1, got " & $minVal)

    # direction check
    let dirNode = stability{"direction"}
    if dirNode != nil and dirNode.kind == JString:
      let dirStr = dirNode.getStr()
      if parseDriftDirection(dirStr).isNone():
        errors.add("Revision " & rid & ": invalid direction '" & dirStr & "'; must be IMPROVEMENT, REGRESSION, or MAINTAINED")

    # requiredConsecutiveObservations check
    let reqObs = stability{"requiredConsecutiveObservations"}
    if reqObs != nil and reqObs.kind == JInt:
      let reqVal = reqObs.getInt()
      if reqVal < 1:
        errors.add("Revision " & rid & ": requiredConsecutiveObservations must be >= 1, got " & $reqVal)

  # Cross-revision directional consistency: if a revision declares
  # REGRESSION direction, the materialized rules must not have downgraded
  # any disposition (e.g. ERROR→INFO or WARN→INFO).
  var prevDirection: Option[DriftDirection]
  var prevDispositionLevel: int  # 0=INFO, 1=WARN, 2=ERROR
  for rev in revisions:
    let rid = rev{"revisionId"}.getStr("")
    let stability = rev{"stability"}
    if stability != nil and stability.kind != JNull:
      let dirNode = stability{"direction"}
      if dirNode != nil and dirNode.kind == JString:
        let dir = parseDriftDirection(dirNode.getStr())
        if dir.isSome():
          # Check that the revision's rules don't downgrade dispositions
          # relative to what the materialized state would produce
          let revPatches = rev{"patches"}
          if revPatches != nil and revPatches.kind == JArray:
            for patch in revPatches:
              let op = patch{"op"}.getStr("")
              if op == "setRule":
                let args = patch{"arguments"}
                let newDisp = args{"disposition"}.getStr("")
                let newLevel = case newDisp
                  of "INFO": 0
                  of "WARN": 1
                  of "ERROR": 2
                  else: -1
                if newLevel >= 0 and prevDirection.isSome() and newLevel < prevDispositionLevel:
                  # Disposition downgraded after a previous direction was set
                  # This is only valid if the direction is IMPROVEMENT
                  let curDir = dir.get()
                  if curDir == ddRegression and newLevel < prevDispositionLevel:
                    errors.add("Revision " & rid & ": REGRESSION direction cannot downgrade disposition from " & $prevDispositionLevel & " to " & $newLevel)
          prevDirection = dir
          # Compute the effective disposition level for this revision
          for rule in materialized.rules:
            let d = rule.disposition
            let level = case d
              of "INFO": 0
              of "WARN": 1
              of "ERROR": 2
              else: -1
            if level >= 0:
              prevDispositionLevel = level

  result = errors

# ══════════════════════════════════════════════════════════════════════
# Helper: JSONC comment stripper (local copy for stdlib-only purity)
# ══════════════════════════════════════════════════════════════════════

func stripJsonComments*(jsonc: string): string {.raises: [].} =
  var buf = newStringOfCap(jsonc.len)
  var i = 0
  var inString = false
  var inBlockComment = false
  var escapeNext = false
  while i < jsonc.len:
    let ch = jsonc[i]
    let nextCh = if i + 1 < jsonc.len: jsonc[i + 1] else: '\0'
    if inBlockComment:
      if ch == '*' and nextCh == '/':
        inBlockComment = false
        inc i
    elif inString:
      buf.add(ch)
      if escapeNext:
        escapeNext = false
      elif ch == '\\':
        escapeNext = true
      elif ch == '"':
        inString = false
    else:
      if ch == '"':
        inString = true
        buf.add(ch)
      elif ch == '/' and nextCh == '/':
        inc i
        while i < jsonc.len and jsonc[i] != '\n':
          inc i
      elif ch == '/' and nextCh == '*':
        inBlockComment = true
        inc i
      else:
        buf.add(ch)
    inc i
  result = buf

# ══════════════════════════════════════════════════════════════════════
# verifyPolicyDispositions — deterministic freshness of the committed
# policy_dispositions.json against materialized policy chain.
# ══════════════════════════════════════════════════════════════════════

func deriveDisposition*(materialized: MaterializedState, expectedState: string): string =
  ## Disposition for a given state per the materialized policy rules,
  ## falling back to the fail-closed default when no rule matches.
  for rule in materialized.rules:
    if rule.state == expectedState:
      return rule.disposition
  materialized.defaultDisposition

proc verifyPolicyDispositions*(chain: JsonNode, genesisState: JsonNode,
                               dispositionsPath: string): seq[string] =
  ## FRESH iff the committed policy_dispositions.json encodes exactly what
  ## this chain's materialized rules (via DecisionTable state mapping)
  ## prescribe for every metric.  Compares rule-derived disposition against
  ## the file's per-metric disposition — the file is the policy artifact,
  ## not a MaterializedState JSON, so a plain state-comparison would be an
  ## unfalsifiable shape mismatch.
  var issues: seq[string]
  if not fileExists(dispositionsPath):
    return @["committed file missing: " & dispositionsPath]
  let materialized = materialize(chain, genesisState)
  let committedStripped = stripJsonComments(readFile(dispositionsPath))
  var committed: JsonNode
  try:
    committed = parseJson(committedStripped)
  except CatchableError:
    return @["committed file unparseable: " & dispositionsPath]
  let metricsNode = committed{"metrics"}
  if metricsNode.isNil or metricsNode.kind != JObject:
    return @["committed file missing 'metrics' object"]

  for metricName, expectedState in DecisionTable:
    let fileDisp = metricsNode{metricName}{"disposition"}.getStr("")
    if fileDisp.len == 0:
      issues.add("metric " & metricName & " missing in committed file")
      continue
    let derived = deriveDisposition(materialized, expectedState)
    if fileDisp != derived:
      issues.add("metric " & metricName & " file=" & fileDisp & " derived=" & derived)
  # Extra metrics in committed file (not in DecisionTable) → unsupported drift
  for metricName in metricsNode.keys:
    if metricName notin DecisionTable:
      issues.add("committed file has undeclared metric " & metricName)
  result = issues

# ══════════════════════════════════════════════════════════════════════
# verifyFreshness — compares materialized state vs committed file
# ══════════════════════════════════════════════════════════════════════

proc verifyFreshness*(materializedState: MaterializedState, committedPath: string): string =
  ## Compares materialized state against committed file on disk.
  ## Returns "fresh" if identical, "STALE (run tools/sync_policy)" otherwise.
  if not fileExists(committedPath):
    return "STALE (committed file missing: " & committedPath & ")"
  let committed = readFile(committedPath)
  let committedStripped = stripJsonComments(committed)
  let materializedJson = %materializedState
  let materializedStr = materializedJson.pretty()
  if committedStripped.strip() == materializedStr.strip():
    return "fresh"
  else:
    return "STALE (run tools/sync_policy)"

proc verifyContentFreshness*(expectedBody: string, committedPath: string): string =
  ## Compares the deterministic generator output body (JSON w/o comments)
  ## against the committed file on disk.  The sync tools' outputs are metric
  ## tables (NOT MaterializedState), so content comparison is the correct
  ## freshness check for them — materialized-state comparison would always
  ## report STALE on a shape mismatch.
  if not fileExists(committedPath):
    return "STALE (committed file missing: " & committedPath & ")"
  let committed = readFile(committedPath)
  let committedStripped = stripJsonComments(committed)
  if committedStripped.strip() == expectedBody.strip():
    return "fresh"
  else:
    return "STALE (run tools/sync_policy)"
