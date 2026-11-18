import core/trusted/layer_declaration
axiomLayer "tools"

## proof_ratchet.nim — exact-inventory lock over one fresh full-scope
## `ax prove` state document (DEBT#549 B′).
##
## This tool owns exactly ONE projection: `buildInventory`. `--emit-baseline`
## and `--compare` both use it, so a baseline can never be derived from a
## different shape than the comparison that consumes it.
##
## Semantics — `exact-inventory-lock`:
##   Every unit row, every runAccounting count, and the scope-lock digest must
##   be byte-identical to the committed baseline. Improvement is a MISMATCH,
##   not a pass: a state change is only legitimate through an approved
##   baseline update. This is deliberately conservative — a monotonic ratchet
##   would need a partial order over outcomes that this contract does not
##   claim.
##
## What the ratchet verdict means:
##   MATCH    the observed inventory equals the committed baseline. It says
##            NOTHING about whether the proof succeeded — `runOutcome.verdict`
##            is carried separately so a FAIL inventory can be locked as-is.
##   MISMATCH the inventory drifted; `diff` names the units and fields.
##   UNKNOWN  the baseline or state could not be read, or the contract version
##            is unsupported. Fail closed: never a silent skip.
##
## Normalization (documented, closed):
##   Unit rows are projected to exactly six fields — unitId,
##   requirementDecision, verificationOutcome, consistency, executionEvidence,
##   satisfactionSource — and sorted by unitId (UTF-8 byte order). Every other
##   state path is excluded and listed in `normalization.excludedStatePaths`:
##   runtimeMeta, executionStats, executionIdentity, gates[].timestamp,
##   nodeReports[].vaultPath, canonicalRunDigest, schemaVersion,
##   evidenceLogJson, closure (scope lock is independent of closure).
##
## Usage:
##   proof_ratchet --emit-baseline --state <ax_proof_state.json>
##     --scope-lock <data/verification_scope.lock>
##     [--subject-sha <sha>] [--subject-tree <tree>] [--out <file>]
##     [--run-id <id>] [--run-url <url>]
##   proof_ratchet --compare --baseline <baseline.json>
##     --state <ax_proof_state.json> --scope-lock <...>
##     [--subject-sha <sha>] [--out <verdict.json>]
##
## Exit: 0 = MATCH · 1 = MISMATCH · 3 = UNKNOWN · 2 = usage/unreadable input.

import std/[algorithm, json, os, parseopt, strutils, tables]
import core/crypto/hash_kernel
import core/results
import ./fresh_prove_verdict

const
  BaselineContract* = "axiom.proof-ratchet-baseline.v1"
  VerdictContract* = "axiom.proof-ratchet-verdict.v1"
  LockSemantics* = "exact-inventory-lock"
  ExitMatch* = 0
  ExitMismatch* = 1
  ExitError* = 2
  ExitUnknown* = 3

  UnitFields* = [
    "unitId",
    "requirementDecision",
    "verificationOutcome",
    "consistency",
    "executionEvidence",
    "satisfactionSource",
  ]

  ExcludedStatePaths* = [
    "runtimeMeta",
    "executionStats",
    "executionIdentity",
    "gates[].timestamp",
    "nodeReports[].vaultPath",
    "canonicalRunDigest",
    "schemaVersion",
    "evidenceLogJson",
    "closure",
  ]

  AccountingIntFields* = [
    "requiredCount",
    "notRequiredCount",
    "unresolvedDecisionCount",
    "satisfiedCount",
    "unsatisfiedCount",
    "pendingCount",
    "contestedCount",
    "satisfiedByFresh",
    "satisfiedByReused",
    "preSievedCount",
    "attemptedCount",
    "notAttemptedCount",
    "freshExecutionCount",
    "executedCount",
    "proofFailedCount",
    "timeoutUnsatCount",
    "reuseEligibleRowCount",
    "reuseRejectedRowCount",
  ]

  AccountingBoolFields* = ["planComplete", "executionComplete", "verificationComplete"]

type
  Mode* = enum
    mNone,
    mEmitBaseline,
    mCompare

  Options* = object
    mode*: Mode
    statePath*: string
    scopeLockPath*: string
    baselinePath*: string
    outPath*: string
    subjectSha*: string
    subjectTree*: string
    runId*: string
    runUrl*: string
    hasOut*: bool

func jStr(n: JsonNode; key: string; default: string = ""): string {.raises: [].} =
  if n.isNil or n.kind != JObject:
    return default
  let v = n{key}
  if v.isNil or v.kind != JString:
    return default
  v.getStr()

func jInt(n: JsonNode; key: string; default: int = 0): int {.raises: [].} =
  if n.isNil or n.kind != JObject:
    return default
  let v = n{key}
  if v.isNil or v.kind != JInt:
    return default
  v.getInt()

func jBool(n: JsonNode; key: string; default: bool = false): bool {.raises: [].} =
  if n.isNil or n.kind != JObject:
    return default
  let v = n{key}
  if v.isNil or v.kind != JBool:
    return default
  v.getBool()

func jObj(n: JsonNode; key: string): JsonNode {.raises: [].} =
  if n.isNil or n.kind != JObject:
    return nil
  let v = n{key}
  if v.isNil or v.kind != JObject:
    return nil
  v

func jArr(n: JsonNode; key: string): JsonNode {.raises: [].} =
  if n.isNil or n.kind != JObject:
    return nil
  let v = n{key}
  if v.isNil or v.kind != JArray:
    return nil
  v

func sha256OfString*(data: string): string {.raises: [].} =
  sha256Hex(data)

proc scopeLockDigest*(path: string): string =
  ## Digest of the tracked scope-lock bytes. A missing lock is the empty
  ## string — the caller reports it, this function never invents a value.
  if not fileExists(path):
    return ""
  sha256OfString(readFile(path))

func projectAccounting(state: JsonNode): JsonNode {.raises: [].} =
  let accounting = jObj(state, "runAccounting")
  var counts = newJObject()
  for field in AccountingIntFields:
    counts[field] = %jInt(accounting, field)
  result = counts

func projectRunOutcome(state: JsonNode): JsonNode {.raises: [].} =
  let outcome = jObj(jObj(state, "runAccounting"), "runOutcome")
  result = newJObject()
  for field in AccountingBoolFields:
    result[field] = %jBool(outcome, field)
  let verdict = jStr(jObj(state, "runOutcome"), "verdict")
  result["verdict"] = %verdict

func buildInventory*(state: JsonNode; scope: JsonNode; lockDigest: string;
                     subjectSha, subjectTree: string): JsonNode {.raises: [].} =
  ## The canonical, deterministic payload. Provenance (runId, timestamps) is
  ## deliberately outside it, so two runs over identical inputs hash equal.
  ##
  ## Unit rows and scope coverage are taken from `fresh_prove_verdict`'s
  ## exported canonical projection; neither is re-derived here, so the ratchet
  ## and the observation lane cannot disagree about what was observed.
  let canonical = buildCanonicalEvidence(state, scope, lockDigest,
                                        subjectSha, subjectTree)
  let scopeBinding = jObj(canonical, "scope")
  let coverage = jObj(scopeBinding, "coverage")

  var scopeBlock = newJObject()
  scopeBlock["lockDigest"] = %lockDigest
  scopeBlock["lockSchemaVersion"] = %jInt(scope, "schema_version")
  scopeBlock["declaredSymbolCount"] = %jInt(scopeBinding, "symbolCount")
  scopeBlock["accountedCount"] = %jInt(coverage, "accountedCount")
  scopeBlock["missingCount"] = %jInt(coverage, "missingCount")
  scopeBlock["complete"] = %jBool(coverage, "complete")
  scopeBlock["missing"] =
    if coverage.isNil: newJArray() else: coverage{"missing"}

  result = newJObject()
  result["contract"] = %BaselineContract
  result["semantics"] = %LockSemantics
  result["subject"] = %*{"sha": subjectSha, "tree": subjectTree}
  result["scope"] = scopeBlock
  result["counts"] = projectAccounting(state)
  result["runOutcome"] = projectRunOutcome(state)
  result["units"] =
    if canonical.isNil: newJArray() else: canonical{"units"}

func inventoryDigest*(inventory: JsonNode): string {.raises: [].} =
  ## Hashed over the INVENTORY only. `subject` is provenance — a merge-group
  ## SHA or an advanced main tree would otherwise make every run a MISMATCH
  ## for a reason that has nothing to do with what was verified.
  ##
  ## `$` on a JsonNode built in fixed key order is deterministic; unit rows are
  ## pre-sorted, so the digest is stable across runs and machines.
  var payload = newJObject()
  for key, value in inventory.pairs:
    if key != "subject":
      payload[key] = value
  sha256OfString($payload)

func stringArray(items: openArray[string]): JsonNode {.raises: [].} =
  result = newJArray()
  for item in items:
    result.add(%item)

func normalizationBlock(): JsonNode =
  result = newJObject()
  result["unitFields"] = stringArray(UnitFields)
  result["ordering"] = %"unitId:utf8-asc"
  result["excludedStatePaths"] = stringArray(ExcludedStatePaths)

proc readJsonFile(path: string): Result[JsonNode, string] =
  if not fileExists(path):
    return err("missing file: " & path)
  try:
    return ok(parseFile(path))
  except CatchableError as e:
    return err("unreadable JSON in " & path & ": " & e.msg)

proc emitBaseline(opts: Options): int =
  let stateRes = readJsonFile(opts.statePath)
  if stateRes.isErr:
    stderr.writeLine("proof_ratchet: " & stateRes.error)
    return ExitError
  let scopeRes = readJsonFile(opts.scopeLockPath)
  if scopeRes.isErr:
    stderr.writeLine("proof_ratchet: " & scopeRes.error)
    return ExitError

  let state = stateRes.get
  let scope = scopeRes.get
  let digest = scopeLockDigest(opts.scopeLockPath)
  let inventory = buildInventory(state, scope, digest,
                                 opts.subjectSha, opts.subjectTree)

  var baseline = newJObject()
  baseline["contract"] = %BaselineContract
  baseline["semantics"] = %LockSemantics
  baseline["inventoryDigest"] = %inventoryDigest(inventory)
  baseline["inventory"] = inventory
  var provenance = newJObject()
  provenance["workflow"] = %"fresh-prove-observation"
  provenance["runId"] = %opts.runId
  provenance["runUrl"] = %opts.runUrl
  baseline["provenance"] = provenance
  baseline["normalization"] = normalizationBlock()

  let text = pretty(baseline, 2) & "\n"
  if opts.hasOut:
    writeFile(opts.outPath, text)
    echo opts.outPath
  else:
    stdout.write(text)
  return ExitMatch

func fieldDiff(baselineRow, currentRow: JsonNode): JsonNode {.raises: [].} =
  var changed = newJObject()
  for field in UnitFields:
    let before = jStr(baselineRow, field)
    let after = jStr(currentRow, field)
    if before != after:
      changed[field] = %*{"baseline": before, "current": after}
  if changed.len == 0:
    return nil
  changed

func compareInventories(baselineInv, currentInv: JsonNode): JsonNode =
  let baselineUnits = jArr(baselineInv, "units")
  let currentUnits = jArr(currentInv, "units")
  var byId = initTable[string, JsonNode]()
  if not baselineUnits.isNil:
    for row in baselineUnits.elems:
      byId[jStr(row, "unitId")] = row
  var currentById = initTable[string, JsonNode]()
  var currentIds: seq[string]
  if not currentUnits.isNil:
    for row in currentUnits.elems:
      let id = jStr(row, "unitId")
      currentById[id] = row
      currentIds.add(id)
  var baselineIds: seq[string]
  if not baselineUnits.isNil:
    for row in baselineUnits.elems:
      baselineIds.add(jStr(row, "unitId"))

  var added = newJArray()
  var removed = newJArray()
  var changedRows = newJArray()
  for id in currentIds:
    if not byId.hasKey(id):
      added.add(%id)
  for id in baselineIds:
    if not currentById.hasKey(id):
      removed.add(%id)
  for id in baselineIds:
    if currentById.hasKey(id):
      let delta = fieldDiff(byId[id], currentById[id])
      if not delta.isNil:
        var row = newJObject()
        row["unitId"] = %id
        row["fields"] = delta
        changedRows.add(row)

  var countsDelta = newJObject()
  let baseCounts = jObj(baselineInv, "counts")
  let curCounts = jObj(currentInv, "counts")
  for field in AccountingIntFields:
    let before = jInt(baseCounts, field)
    let after = jInt(curCounts, field)
    if before != after:
      countsDelta[field] = %*{"baseline": before, "current": after}

  var outcomeDelta = newJObject()
  let baseOutcome = jObj(baselineInv, "runOutcome")
  let curOutcome = jObj(currentInv, "runOutcome")
  for field in AccountingBoolFields:
    let before = jBool(baseOutcome, field)
    let after = jBool(curOutcome, field)
    if before != after:
      outcomeDelta[field] = %*{"baseline": before, "current": after}
  if jStr(baseOutcome, "verdict") != jStr(curOutcome, "verdict"):
    outcomeDelta["verdict"] = %*{"baseline": jStr(baseOutcome, "verdict"),
                                "current": jStr(curOutcome, "verdict")}

  var scopeDelta = newJObject()
  let baseScope = jObj(baselineInv, "scope")
  let curScope = jObj(currentInv, "scope")
  for field in ["lockDigest", "lockSchemaVersion", "declaredSymbolCount",
                "accountedCount", "missingCount"]:
    let before = $baseScope{field}
    let after = $curScope{field}
    if before != after:
      scopeDelta[field] = %*{"baseline": before, "current": after}
  let beforeComplete = jBool(baseScope, "complete")
  let afterComplete = jBool(curScope, "complete")
  if beforeComplete != afterComplete:
    scopeDelta["complete"] = %*{"baseline": beforeComplete, "current": afterComplete}

  result = newJObject()
  result["unitsAdded"] = added
  result["unitsRemoved"] = removed
  result["unitsChanged"] = changedRows
  result["counts"] = countsDelta
  result["runOutcome"] = outcomeDelta
  result["scope"] = scopeDelta

func reasonsFor(diff: JsonNode): seq[string] {.raises: [].} =
  if jArr(diff, "unitsAdded").len > 0:
    result.add("units-added")
  if jArr(diff, "unitsRemoved").len > 0:
    result.add("units-removed")
  if jArr(diff, "unitsChanged").len > 0:
    result.add("unit-outcome-changed")
  if jObj(diff, "counts").len > 0:
    result.add("counts-changed")
  if jObj(diff, "runOutcome").len > 0:
    result.add("run-outcome-changed")
  if jObj(diff, "scope").len > 0:
    result.add("scope-changed")

proc compare(opts: Options): int =
  let baselineRes = readJsonFile(opts.baselinePath)
  if baselineRes.isErr:
    # Baseline absent is not a pass: a ratchet with no reference cannot assert.
    var verdict = newJObject()
    verdict["contract"] = %VerdictContract
    verdict["verdict"] = %"UNKNOWN"
    verdict["exitCode"] = %ExitUnknown
    verdict["reasons"] = %*["baseline-missing"]
    verdict["detail"] = %baselineRes.error
    let text = pretty(verdict, 2) & "\n"
    if opts.hasOut:
      writeFile(opts.outPath, text)
    stdout.write(text)
    return ExitUnknown
  let stateRes = readJsonFile(opts.statePath)
  let scopeRes = readJsonFile(opts.scopeLockPath)
  if stateRes.isErr or scopeRes.isErr:
    stderr.writeLine("proof_ratchet: " &
      (if stateRes.isErr: stateRes.error else: scopeRes.error))
    return ExitError

  let baseline = baselineRes.get
  if jStr(baseline, "contract") != BaselineContract or
     jStr(baseline, "semantics") != LockSemantics:
    var verdict = newJObject()
    verdict["contract"] = %VerdictContract
    verdict["verdict"] = %"UNKNOWN"
    verdict["exitCode"] = %ExitUnknown
    verdict["reasons"] = %*["baseline-contract-unsupported"]
    verdict["detail"] = %("found contract=" & jStr(baseline, "contract") &
                          " semantics=" & jStr(baseline, "semantics"))
    let text = pretty(verdict, 2) & "\n"
    if opts.hasOut:
      writeFile(opts.outPath, text)
    stdout.write(text)
    return ExitUnknown

  let baselineInv = jObj(baseline, "inventory")
  let currentInv = buildInventory(stateRes.get, scopeRes.get,
                                  scopeLockDigest(opts.scopeLockPath),
                                  opts.subjectSha, opts.subjectTree)
  let diff = compareInventories(baselineInv, currentInv)
  let reasons = reasonsFor(diff)
  let currentDigest = inventoryDigest(currentInv)
  let baselineDigest = jStr(baseline, "inventoryDigest")
  let digestMatches = currentDigest == baselineDigest
  var verdictName = "MATCH"
  var code = ExitMatch
  if not digestMatches or reasons.len > 0:
    verdictName = "MISMATCH"
    code = ExitMismatch

  var verdict = newJObject()
  verdict["contract"] = %VerdictContract
  verdict["semantics"] = %LockSemantics
  verdict["verdict"] = %verdictName
  verdict["exitCode"] = %code
  verdict["reasons"] = %reasons
  verdict["baselineDigest"] = %baselineDigest
  verdict["currentDigest"] = %currentDigest
  verdict["digestMatches"] = %digestMatches
  verdict["baselineSubjectSha"] = %jStr(jObj(baselineInv, "subject"), "sha")
  verdict["subjectSha"] = %opts.subjectSha
  verdict["subjectChanged"] =
    %(jStr(jObj(baselineInv, "subject"), "sha") != opts.subjectSha)
  verdict["counts"] = %jObj(currentInv, "counts")
  verdict["runOutcome"] = %jObj(currentInv, "runOutcome")
  verdict["scope"] = %jObj(currentInv, "scope")
  verdict["diff"] = diff
  verdict["normalization"] = normalizationBlock()

  let text = pretty(verdict, 2) & "\n"
  if opts.hasOut:
    writeFile(opts.outPath, text)
  echo opts.outPath
  return code

proc parseOptions(args: seq[string]): Result[Options, string] {.raises: [].} =
  var opts = Options(mode: mNone)
  var pending = ""
  template assignFlag(key: string) =
    case key
    of "emit-baseline": opts.mode = mEmitBaseline
    of "compare": opts.mode = mCompare
    else: discard
  template assignOpt(key, val: string) =
    case key
    of "state": opts.statePath = val
    of "scope-lock": opts.scopeLockPath = val
    of "baseline": opts.baselinePath = val
    of "out": opts.outPath = val; opts.hasOut = true
    of "subject-sha": opts.subjectSha = val
    of "subject-tree": opts.subjectTree = val
    of "run-id": opts.runId = val
    of "run-url": opts.runUrl = val
    else: discard
  var p = initOptParser(args)
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      let key = p.key
      let val = p.val
      if key in ["emit-baseline", "compare"]:
        assignFlag(key)
      elif val.len > 0:
        assignOpt(key, val)
      else:
        pending = key
    of cmdArgument:
      if pending.len == 0:
        return err("unexpected argument: " & p.key)
      assignOpt(pending, p.key)
      pending = ""
  if pending.len > 0:
    return err("missing value for --" & pending)
  if opts.mode == mNone:
    return err("one of --emit-baseline or --compare is required")
  if opts.statePath.len == 0:
    return err("--state is required")
  if opts.scopeLockPath.len == 0:
    return err("--scope-lock is required")
  if opts.mode == mCompare and opts.baselinePath.len == 0:
    return err("--baseline is required with --compare")
  ok(opts)

proc main(args: seq[string]): int =
  let parsed = parseOptions(args)
  if parsed.isErr:
    stderr.writeLine("proof_ratchet: " & parsed.error)
    return ExitError
  let opts = parsed.get
  case opts.mode
  of mEmitBaseline: emitBaseline(opts)
  of mCompare: compare(opts)
  of mNone: ExitError

when isMainModule:
  quit(main(commandLineParams()))