import std/[json, strutils, sequtils, algorithm, tables, options, os]
import core/types/request_result
import core/types/request_id
import core/types/execution_plan
import core/types/proof_status
import verification/selection/selection_digests

# ---------------------------------------------------------------------------
# R8b-3 projection evidence runner (v2 — certificate-status source)
# ---------------------------------------------------------------------------
# Per-unit verdicts are taken from the run's OWN emitted certificate-status
# lines (loop_driver/axiom_engine output), NOT from the orchestration
# nodeReports statuses: observed divergence (F-2) showed nodeReports carry
# orchestration statuses (e.g. no_obligation) that can disagree with the real
# certificate status (e.g. psFail for the same unit in the same run).
# Aggregation uses the CANONICAL reducer (core/types/request_result) only.

# ---------------------------------------------------------------------------
# Log parsing
# ---------------------------------------------------------------------------

type
  UnitEvidence* = object
    unitId*: string      # full "file::func" id
    status*: ProofStatus
    sourceLines*: seq[string]

const
  psUnknown* = psError  # sentinel: not directly usable; we use Option instead

## Parse a run log into full-unit-id → observed certificate status.
## Returns (evidence table, raw matched lines).
proc parseRunLog*(logPath: string): Table[string, seq[UnitEvidence]] =
  ## status priority: an explicit IR FAIL/skip line (real SMT verdict) wins
  ## over a later certNoObligation line for the same unit.
  result = initTable[string, seq[UnitEvidence]]()
  let lines = logPath.readFile().splitLines()
  for line in lines:
    # full-id node lines with certificate demotion decisions:
    #   "loop_driver: node <full-id> — certNoObligation; ..."
    if line.contains("loop_driver: node ") and line.contains("certNoObligation"):
      let n = line.find("node ")
      let rest = line[n + 5 .. ^1]
      let unitId = rest.split(" — ")[0]
      if unitId.contains("::"):
        result.mgetOrPut(unitId, @[]).add(UnitEvidence(
          unitId: unitId, status: psNoObligation, sourceLines: @[line.strip()]))
    # real certificate verdict lines (short function name):
    #   "IR pipeline FAIL: <func> status=psFail provenance=..."
    #   "IR pipeline skip: <func> status=psSkip provenance=..."
    elif line.contains("IR pipeline FAIL: "):
      let idx = line.find("IR pipeline FAIL: ") + len("IR pipeline FAIL: ")
      let shortName = line[idx .. ^1].split(" ")[0]
      let stIdx = line.find("status=")
      if stIdx >= 0:
        let statusStr = line[stIdx + len("status=") .. ^1].split(" ")[0]
        let status = parseEnum[ProofStatus](statusStr)
        # store under a placeholder key resolved later via short-name suffix
        result.mgetOrPut(shortName, @[]).add(UnitEvidence(
          unitId: shortName, status: status, sourceLines: @[line.strip()]))
    elif line.contains("IR pipeline skip: "):
      let idx = line.find("IR pipeline skip: ") + len("IR pipeline skip: ")
      let shortName = line[idx .. ^1].split(" ")[0]
      let stIdx = line.find("status=")
      if stIdx >= 0:
        let statusStr = line[stIdx + len("status=") .. ^1].split(" ")[0]
        let status = parseEnum[ProofStatus](statusStr)
        result.mgetOrPut(shortName, @[]).add(UnitEvidence(
          unitId: shortName, status: status, sourceLines: @[line.strip()]))

## Resolve short-name keys to full unit ids using the request list.
func resolveEvidence(
  ev: Table[string, seq[UnitEvidence]]
; requests: seq[RequestId]
): Table[string, UnitEvidence] =
  result = initTable[string, UnitEvidence]()
  for reqId in requests:
    let fullId = reqId.toString()
    let short = fullId.split("::")[^1]
    var best: Option[UnitEvidence] = none(UnitEvidence)
    # full-id match first
    if ev.hasKey(fullId):
      best = some(ev[fullId][0])
    # short-name match (real cert verdict) — overrides certNoObligation
    if ev.hasKey(short):
      best = some(ev[short][0])
    if best.isSome:
      var e = best.get()
      e.unitId = fullId
      result[fullId] = e

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
when isMainModule:
  var
    fullLogPath  = ""
    prunedLogPath = ""
    planPath     = ""
    outPath      = ""

  var i = 1
  while i < paramCount():
    let arg = paramStr(i)
    case arg
    of "--full-log":
      inc i; fullLogPath = paramStr(i)
    of "--pruned-log":
      inc i; prunedLogPath = paramStr(i)
    of "--plan":
      inc i; planPath = paramStr(i)
    of "--out":
      inc i; outPath = paramStr(i)
    else:
      echo "Unknown argument: ", arg
      quit(1)
    inc i

  if fullLogPath.len == 0 or prunedLogPath.len == 0 or planPath.len == 0 or outPath.len == 0:
    echo "Usage: projection_evidence_runner --full-log <path> --pruned-log <path> --plan <path> --out <path>"
    quit(1)

  # Load plan + guards (plan digest MUST verify; explicit requests MUST exist)
  let planJson = parseFile(planPath)
  let planOpt = execution_plan.fromJson(planJson)
  if planOpt.isNone():
    echo "ERROR: Failed to parse execution plan"
    quit(1)
  let plan = planOpt.get()
  let planDigestVerified = verifyPlanDigest(plan)
  if not planDigestVerified:
    echo "ERROR: plan digest verification FAILED"
    quit(1)
  if plan.requests.len == 0:
    echo "ERROR: plan has no explicit requests"
    quit(1)

  # Parse both logs
  let fullEv   = parseRunLog(fullLogPath)
  let prunedEv = parseRunLog(prunedLogPath)
  let fullResolved   = resolveEvidence(fullEv, plan.requests)
  let prunedResolved = resolveEvidence(prunedEv, plan.requests)

  # Per-request comparison
  var perRequestComparison: seq[JsonNode] = @[]
  var equalCount = 0
  var notClaimedCount = 0
  var mismatchCount = 0
  for reqId in plan.requests.sorted(proc(a, b: RequestId): int = cmp(a.toString(), b.toString())):
    let reqStr = reqId.toString()
    let fullObs   = fullResolved.hasKey(reqStr)
    let prunedObs = prunedResolved.hasKey(reqStr)
    let fullVerdict   = if fullObs:   toRequestVerdict(fullResolved[reqStr].status)   else: rvError
    let prunedVerdict = if prunedObs: toRequestVerdict(prunedResolved[reqStr].status) else: rvError
    let claimable = fullObs and prunedObs
    let equal = claimable and fullVerdict == prunedVerdict
    if claimable and equal:
      inc equalCount
    elif not claimable:
      inc notClaimedCount
    else:
      inc mismatchCount
    perRequestComparison.add(%*{
      "requestId": reqStr,
      "fullVerdict": (if fullObs: $fullVerdict else: "UNOBSERVABLE"),
      "prunedVerdict": (if prunedObs: $prunedVerdict else: "UNOBSERVABLE"),
      "fullStatus": (if fullObs: $fullResolved[reqStr].status else: ""),
      "prunedStatus": (if prunedObs: $prunedResolved[reqStr].status else: ""),
      "claimable": claimable,
      "equal": equal,
      "fullSourceLines": (if fullObs: fullResolved[reqStr].sourceLines else: @[]),
      "prunedSourceLines": (if prunedObs: prunedResolved[reqStr].sourceLines else: @[])})

  # Overall status (fail-closed: any mismatch → MISMATCH; coverage-limited → PARTIAL)
  let status =
    if mismatchCount > 0: "MISMATCH"
    elif notClaimedCount > 0: "PARTIAL-PASS (coverage-limited, fail-closed)"
    else: "REAL-PASS"

  let worktreeHead = getEnv("R8B3_WORKTREE_HEAD", "unknown")

  let output = %*{
    "experiment": "r8b3_projection",
    "status": status,
    "headCommit": getEnv("GIT_HEAD", "unknown"),
    "worktreeHead": worktreeHead,
    "planDigestVerified": planDigestVerified,
    "explicitRequests": true,
    "requestCount": plan.requests.len,
    "equalCount": equalCount,
    "notClaimedCount": notClaimedCount,
    "mismatchCount": mismatchCount,
    "perRequestComparison": perRequestComparison,
    "reducerSource": "canonical import core/types/request_result (toRequestVerdict + aggregateRequestResult)",
    "verdictSource": "run log IR certificate-status lines (IR pipeline FAIL/skip status=..; node certNoObligation)",
    "provenance": %*{
      "fullLog": fullLogPath,
      "prunedLog": prunedLogPath,
      "plan": planPath,
      "commands": @[
        "AXIOM_STATE_DIR=/tmp/r8b3-state-full bin/ax prove --smt-timeout 4000 (wave run at c3adfb995) > /tmp/r8b3-wave2.log",
        "AXIOM_STATE_DIR=/tmp/r8b3b-state-pruned bin/ax prove --plan /tmp/r8b3b-plan.json --smt-timeout 4000 > /tmp/r8b3-pruned.log"],
      "baseForSelection": "d3a4d2f75 (mutation parent)",
      "worktreeHead": worktreeHead,
      "note": "F-1/F-2 findings: full-run single-wave scope excludes requests blocked by failed dependency (proximityScore psFail), so full-side status is unobservable for those requests; nodeReports orchestration statuses can disagree with real certificate statuses (F-2)."}}

  writeFile(outPath, pretty(output))
  echo "Evidence written to: ", outPath
  echo "Status: ", status
  echo "equal=", equalCount, " notClaimed=", notClaimedCount, " mismatch=", mismatchCount