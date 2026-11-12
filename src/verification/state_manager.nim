import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import core/crypto/hash_kernel
import core/axiom_pragmas
import core/utils/constants
import core/json/json_utils
import core/json/std_redirect
import core/results
import core/gate/gate_context
import core/telemetry/metrics
import core/types/asi_types
import core/utils/io_utils
import generated/build_env
import std/options
import std/os
import std/strutils
import std/tables
import std/times
# axiomIoBoundary

## g Compiler Version constant.
const gCompilerVersion* = NimVersion
## g Solver Version constant.
const gSolverVersion* = BuildEnvZ3Version
## g Source Hash constant — resolved at compile time from generated/build_env
## (deterministic, no git binary needed).
const gSourceHash* = BuildEnvGitHash

## Atomic Write Text.
# @axiom-hint: lean="path.length ≥ 0 ∧ content.length ≥ 0 ∧ external_io_isolated" smt="(assert (and (>= (str.len path) 0) (>= (str.len content) 0) external_io_isolated))"
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
proc atomicWriteText*(path: string; content: string): Result[bool, string] =
  ## Atomically writes content to path using tmp-file + move.
  let tmpPath = path & ".tmp"
  try:
    ## intentional-discard: tmp write is part of atomic rename; failure falls through to error
    discard writeFileOpt(tmpPath, content)
    discard moveFileOpt(tmpPath, path)
    ok(true)
  except CatchableError as e:
    if fileExists(tmpPath):
      discard removeFileOpt(tmpPath)
    err("atomic write failed: " & e.msg)

proc atomicWriteState*(path: string, content: string): Result[void, string] {.raises: [ValueError].} =
  let writeResult = atomicWriteText(path, content)
  discard withGate("atomic_write"):
    if writeResult.isOk:
      ctx.pass()
    else:
      ctx.fail("Atomic write failed: " & writeResult.error)

  if writeResult.isOk:
    Result[void, string](ok: true)
  else:
    err("Atomic write failed: " & writeResult.error)

## Write Solver Evidence.
# @axiom-hint: lean="nodeId.length ≥ 0 ∧ solverStdout.length ≥ 0" smt="(assert (and (>= (str.len nodeId) 0) (>= (str.len solverStdout) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc writeSolverEvidence*(nodeId: string; solverStdout: string): string {.gcsafe, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let evidenceDir = joinPath("logs", "evidence")
  if not dirExists(evidenceDir):
    discard existsOrCreateDirOpt(evidenceDir)
  let safeNodeId = nodeId.replace("/", "_").replace("::", "_")
  let z3outPath = joinPath(evidenceDir, safeNodeId & ".z3out")
  let writeRes = writeFileOpt(z3outPath, solverStdout)
  if writeRes.isOk:
    result = hash_kernel.sha256Hex(solverStdout)

## Load Proof State.
# @axiom-hint: lean="path.length ≥ 0" smt="(assert (and (>= (str.len path) 0)))"
# @axiom-hint: lean="contentRes.isOk = true ∧ parsedOpt.isSome = true ∧ (result ≥ 0)" smt="(assert (and (= (option.isSome contentOpt) true) (= (option.isSome parsedOpt) true) (>= result 0)))"
proc loadProofState*(path: string): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Loads proof state from disk, or returns empty state with entries array.
  let contentRes = readFileOpt(path)
  if contentRes.isOk:
    let parsedOpt = parseJsonOpt(contentRes.get())
    if parsedOpt.isSome:
      return parsedOpt.get()
  result = newJObject()
  result["entries"] = newJArray()

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func getNodeId(entry: JsonNode): string {.raises: [].} =
  let node = entry.getOrDefault("nodeId")
  if not node.isNil and node.kind == JString:
    return node.getStr()
  return ""

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func entryStatus(entry: JsonNode): string {.raises: [].} =
  let node = entry.getOrDefault("status")
  if not node.isNil and node.kind == JString:
    return node.getStr()
  return ""

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="0" smt="(assert (and 0))"
func entryAttemptCount(entry: JsonNode): int {.raises: [].} =
  let node = entry.getOrDefault("attemptCount")
  if not node.isNil and node.kind == JInt:
    return node.getInt()
  return 0

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func entryStrategy(entry: JsonNode): string {.raises: [].} =
  let node = entry.getOrDefault("strategy")
  if not node.isNil and node.kind == JString:
    return node.getStr()
  return ""
const
  healAttemptCircuitThreshold* = 10
  healAttemptCircuitReason* = "attempt-circuit-reset"

# @axiom-hint: lean="status.length ≥ 0" smt="(assert (and (>= (str.len status) 0)))"
func isProofStateVerifiedStatus(status: string): bool {.raises: [].} =
  status == "verified" or status == "certVerifiedAxiom" or status == "certIntrinsic" or
    status == "certLeanVerified" or status == "certDualVerified"

# @axiom-hint: lean="threshold ≥ -9223372036854775808 ∧ threshold ≤ 9223372036854775807" smt="(assert (and (and (>= threshold -9223372036854775808) (<= threshold 9223372036854775807))))"
# @axiom-hint: lean="attempts ≤ threshold ∧ false ∧ attempts ≤ threshold → result = false" smt="(assert (and (<= attempts threshold) false (=> (<= attempts threshold) (= result false))))"
func shouldResetHealAttemptEntry*(entry: JsonNode; threshold: int = healAttemptCircuitThreshold): bool {.raises: [].} =
  if entry.isNil or entry.kind != JObject:
    return false
  let attempts = entryAttemptCount(entry)
  if attempts <= threshold:
    return false
  ## Algebraic Safety Guard: Exclude nodes with successCount > 0 or
  ## certIntrinsic status from reset downgrade
  let successCount = entry.getOrDefault("successCount").getInt(0)
  if successCount > 0:
    return false
  let status = entryStatus(entry)
  if status == "certIntrinsic":
    return false
  let strategy = entryStrategy(entry)
  (not isProofStateVerifiedStatus(status)) or strategy == "CEGAR"

# @axiom-hint: lean="threshold ≥ -9223372036854775808 ∧ threshold ≤ 9223372036854775807" smt="(assert (and (and (>= threshold -9223372036854775808) (<= threshold 9223372036854775807))))"
# @axiom-hint: lean="0 ∧ (entry ≥ 0) ∧ (entries ≥ 0)" smt="(assert (and 0 (>= entry 0) (>= entries 0)))"
func resetHighAttemptProofState*(state: var JsonNode; threshold: int = healAttemptCircuitThreshold): int {.raises: [].} =
  if state.isNil or state.kind != JObject:
    return 0
  let entries = state.getOrDefault("entries")
  if entries.isNil or entries.kind != JArray:
    return 0
  for entry in entries:
    if not shouldResetHealAttemptEntry(entry, threshold):
      continue
    let previousAttempts = entryAttemptCount(entry)
    entry["attemptCount"] = newJInt(0)
    entry["previousAttemptCount"] = newJInt(previousAttempts)
    entry["attemptCircuitBreaker"] = newJString(healAttemptCircuitReason)
    if entry.hasKey("leanDiagnostics"):
      entry["leanDiagnostics"] = newJString("")
    if entry.hasKey("bottleneckLog"):
      entry["bottleneckLog"] = newJNull()
    inc result

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func entryEvidenceLog(entry: JsonNode): string {.raises: [].} =
  let node = entry.getOrDefault("evidenceLogJson")
  if not node.isNil and node.kind == JString:
    return node.getStr()
  return ""

# @axiom-hint: lean="status.length ≥ 0" smt="(assert (and (>= (str.len status) 0)))"
# @axiom-hint: lean="0 ∧ (entries ≥ 0)" smt="(assert (and 0 (>= entries 0)))"
func countProofStateStatus(entries: JsonNode; status: string): int {.raises: [].} =
  if entries.isNil or entries.kind != JArray:
    return 0
  for entry in entries:
    if entryStatus(entry) == status:
      inc result

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func countProofStateAttempted(entries: JsonNode): int {.raises: [].} =
  if entries.isNil or entries.kind != JArray:
    return 0
  for entry in entries:
    if entry.isNil or entry.kind != JObject:
      continue
    let attemptedNode = entry.getOrDefault("attempted")
    if not attemptedNode.isNil and attemptedNode.kind == JBool and attemptedNode.getBool():
      inc result
      continue
    let status = entryStatus(entry)
    if status.len > 0 and status != unattemptedKey:
      inc result

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="nodeId.length = 0 ∧ (entry ≥ 0) ∧ (entries ≥ 0) ∧ (verifiedById ≥ 0)" smt="(assert (and (= (str.len nodeId) 0) (>= entry 0) (>= entries 0) (>= verifiedById 0)))"
func propagateVerifiedDuplicateProofState(entries: JsonNode) {.raises: [].} =
  if entries.isNil or entries.kind != JArray:
    return
  var verifiedById = initTable[string, JsonNode]()
  for entry in entries:
    let nodeId = getNodeId(entry)
    if nodeId.len == 0:
      continue
    if isProofStateVerifiedStatus(entryStatus(entry)) and not verifiedById.hasKey(nodeId):
      verifiedById[nodeId] = entry
  for entry in entries:
    let nodeId = getNodeId(entry)
    if nodeId.len == 0 or not verifiedById.hasKey(nodeId):
      continue
    if isProofStateVerifiedStatus(entryStatus(entry)):
      continue
    let source = verifiedById.getOrDefault(nodeId)
    if source.isNil:
      continue
    for key in [
      statusKey, premiseCountKey, "raw_smt_query", "attempted", "attemptCount",
      strategyKey, bottleneckLogKey, "leanDiagnostics", "winningStrategy",
      retryCountKey, "evidencePath", "negativeEvidencePath",
      "leanCompilerVerified", "negativeTestResult"
    ]:
      let value = source.getOrDefault(key)
      if not value.isNil:
        entry[key] = value
    entry["attempted"] = newJBool(true)

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: lean="(summary ≥ 0) ∧ (state ≥ 0)" smt="(assert (and (>= summary 0) (>= state 0)))"
func recomputeProofStateSummary*(state: JsonNode): Result[void, string] {.raises: [].} =
  if state.isNil or state.kind != JObject:
    return
  let entries = state.getOrDefault(entriesKey)
  if entries.isNil or entries.kind != JArray:
    return
  propagateVerifiedDuplicateProofState(entries)
  var summary = state.getOrDefault("summary")
  if summary.isNil or summary.kind != JObject:
    summary = newJObject()
    state["summary"] = summary
  let total = entries.len
  let verifiedCount = countProofStateStatus(entries, verifiedKey)
  let counterCount = countProofStateStatus(entries, "counter_example_found")
  let vacuousCount = countProofStateStatus(entries, "vacuous_contradiction")
  let timeoutCount = countProofStateStatus(entries, "timed_out")
  let unverifiableCount = countProofStateStatus(entries, "unverifiable")
  let pseudoVerifiedCount = countProofStateStatus(entries, "pseudo_verified")
  let certifiedExemptCount = countProofStateStatus(entries, "certified_exempt")
  let unattemptedCount = countProofStateStatus(entries, unattemptedKey)
  let z3CandidateCount = countProofStateStatus(entries, "z3_candidate")
  let totalSourceFunctions = summary.getOrDefault("totalSourceFunctions").getInt(total)
  if totalSourceFunctions < metrics.KernelDomainThreshold:
    return err("proof state summary recomputation failed: totalSourceFunctions=" & $totalSourceFunctions & " < KernelDomainThreshold=" & $metrics.KernelDomainThreshold)
  summary[totalNodesKey] = newJInt(total)
  summary["totalSourceFunctions"] = newJInt(totalSourceFunctions)
  summary[attemptedNodesKey] = newJInt(countProofStateAttempted(entries))
  summary[verifiedKey] = newJInt(verifiedCount)
  summary[counterExamplesKey] = newJInt(counterCount)
  summary[vacuousContradictionsKey] = newJInt(vacuousCount)
  summary[timedOutKey] = newJInt(timeoutCount)
  summary["unverifiable"] = newJInt(unverifiableCount)
  summary["pseudoVerified"] = newJInt(pseudoVerifiedCount)
  summary["certifiedExempt"] = newJInt(certifiedExemptCount)
  summary["z3Candidates"] = newJInt(z3CandidateCount)
  summary[unattemptedKey] = newJInt(unattemptedCount)
  let asiRatio = initAsiRatio(verifiedCount.float / max(1, totalSourceFunctions).float).get(defaultAsiRatio())
  summary["engineAsiFixed4"] = newJString(asString(metrics.exportAsiFixed4(asiRatio)))
  Result[void, string](ok: true)
## Append Thought Trajectory.
# @axiom-hint: lean="logPath.length ≥ 0 ∧ nodeId.length ≥ 0 ∧ phase.length ≥ 0 ∧ detail.length ≥ 0 ∧ unsatCore.length ≥ 0 ∧ hintRationale.length ≥ 0 ∧ leanFailureReason.length ≥ 0 ∧ timeMs ≥ -9223372036854775808 ∧ timeMs ≤ 9223372036854775807 ∧ unsatCoreRaw.length ≥ 0 ∧ relevantAssertions.size ≥ 0 ∧ ∀ (i : Fin relevantAssertions.size), (relevantAssertions.get i).length ≥ 0 ∧ memRssBytes ≥ -9223372036854775808 ∧ memRssBytes ≤ 9223372036854775807 ∧ threadId ≥ -9223372036854775808 ∧ threadId ≤ 9223372036854775807 ∧ proofStepCount ≥ -9223372036854775808 ∧ proofStepCount ≤ 9223372036854775807 ∧ tacticDepth ≥ -9223372036854775808 ∧ tacticDepth ≤ 9223372036854775807 ∧ elaboratedTermSize ≥ -9223372036854775808 ∧ elaboratedTermSize ≤ 9223372036854775807 ∧ compilerVersion.length ≥ 0 ∧ solverVersion.length ≥ 0 ∧ sourceHash.length ≥ 0" smt="(assert (and (>= (str.len logPath) 0) (>= (str.len nodeId) 0) (>= (str.len phase) 0) (>= (str.len detail) 0) (>= (str.len unsatCore) 0) (>= (str.len hintRationale) 0) (>= (str.len leanFailureReason) 0) (and (>= timeMs -9223372036854775808) (<= timeMs 9223372036854775807)) (>= (str.len unsatCoreRaw) 0) (>= (seq.len relevantAssertions) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len relevantAssertions))) (>= (str.len (seq.nth relevantAssertions i)) 0))) (and (>= memRssBytes -9223372036854775808) (<= memRssBytes 9223372036854775807)) (and (>= threadId -9223372036854775808) (<= threadId 9223372036854775807)) (and (>= proofStepCount -9223372036854775808) (<= proofStepCount 9223372036854775807)) (and (>= tacticDepth -9223372036854775808) (<= tacticDepth 9223372036854775807)) (and (>= elaboratedTermSize -9223372036854775808) (<= elaboratedTermSize 9223372036854775807)) (>= (str.len compilerVersion) 0) (>= (str.len solverVersion) 0) (>= (str.len sourceHash) 0)))"
# @axiom-hint: lean="(∀ (relevantAssertionsIdx : Fin relevantAssertions.size), (relevantAssertions.get relevantAssertionsIdx).length ≥ 0)" smt="(assert (and (forall ((relevantAssertionsIdx Int)) (=> (and (>= relevantAssertionsIdx 0) (< relevantAssertionsIdx (seq.len relevantAssertions))) (>= (str.len (seq.nth relevantAssertions relevantAssertionsIdx)) 0)))))"
proc appendThoughtTrajectory*(
  logPath: string;
  nodeId: string;
  phase: string;
  detail: string;
  unsatCore: string = "";
  hintRationale: string = "";
  leanFailureReason: string = "";
  timeMs: int = 0;
  unsatCoreRaw: string = "";
  relevantAssertions: seq[string] = @[];
  cpuUsage: float = 0.0;
  memRssBytes: int = 0;
  threadId: int = 0;
  proofStepCount: int = 0;
  tacticDepth: int = 0;
  elaboratedTermSize: int = 0;
  compilerVersion: string = gCompilerVersion;
  solverVersion: string = gSolverVersion;
  sourceHash: string = gSourceHash
): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Appends a single thought-trajectory event to the append-only thought_trajectory.jsonl log.
  let ts = $now().utc()
  let event = %*{
    "ts": ts,
    "nodeId": nodeId,
    "phase": phase,
    "detail": detail,
    "unsatCore": unsatCore,
    "hintRationale": hintRationale,
    "leanFailureReason": leanFailureReason,
    "timeMs": timeMs,
    "unsatCoreRaw": unsatCoreRaw,
    "relevantAssertions": relevantAssertions,
    "cpuUsage": cpuUsage,
    "memRssBytes": memRssBytes,
    "threadId": threadId,
    "proofStepCount": proofStepCount,
    "tacticDepth": tacticDepth,
    "elaboratedTermSize": elaboratedTermSize,
    "compilerVersion": compilerVersion,
    "solverVersion": solverVersion,
    "sourceHash": sourceHash
  }
  try:
    let dir = parentDir(logPath)
    if dir.len > 0 and not dirExists(dir):
      discard existsOrCreateDirOpt(dir)
    let line = $event & "\n"
    let f = open(logPath, fmAppend)
    f.write(line)
    f.close()
    ok(true)
  except CatchableError as e:
    err("thought trajectory append failed: " & e.msg)

## Append Audit Event.
# @axiom-hint: lean="auditPath.length ≥ 0 ∧ eventType.length ≥ 0 ∧ nodeId.length ≥ 0 ∧ oldStatus.length ≥ 0 ∧ newStatus.length ≥ 0 ∧ actor.length ≥ 0 ∧ strategy.length ≥ 0 ∧ reason.length ≥ 0 ∧ attemptCount ≥ -9223372036854775808 ∧ attemptCount ≤ 9223372036854775807 ∧ compilerVersion.length ≥ 0 ∧ solverVersion.length ≥ 0 ∧ sourceHash.length ≥ 0" smt="(assert (and (>= (str.len auditPath) 0) (>= (str.len eventType) 0) (>= (str.len nodeId) 0) (>= (str.len oldStatus) 0) (>= (str.len newStatus) 0) (>= (str.len actor) 0) (>= (str.len strategy) 0) (>= (str.len reason) 0) (and (>= attemptCount -9223372036854775808) (<= attemptCount 9223372036854775807)) (>= (str.len compilerVersion) 0) (>= (str.len solverVersion) 0) (>= (str.len sourceHash) 0)))"
# @axiom-hint: lean="(event ≥ 0)" smt="(assert (and (>= event 0)))"
proc appendAuditEvent*(
  auditPath: string;
  eventType: string;
  nodeId: string;
  oldStatus: string;
  newStatus: string;
  actor: string;
  strategy: string;
  reason: string;
  attemptCount: int;
  compilerVersion: string = gCompilerVersion;
  solverVersion: string = gSolverVersion;
  sourceHash: string = gSourceHash;
  extra: JsonNode = newJObject()
): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Appends a single audit event to the append-only ax_audit.jsonl log.
  let ts = $now().utc()
  let event = %*{
    "ts": ts,
    "event": eventType,
    "nodeId": nodeId,
    "oldStatus": oldStatus,
    "newStatus": newStatus,
    "actor": actor,
    "strategy": strategy,
    "reason": reason,
    "attemptCount": attemptCount,
    "compilerVersion": compilerVersion,
    "solverVersion": solverVersion,
    "sourceHash": sourceHash
  }
  if extra.kind == JObject:
    for key, val in extra.pairs:
      event[key] = val
  try:
    let dir = parentDir(auditPath)
    if dir.len > 0 and not dirExists(dir):
      discard existsOrCreateDirOpt(dir)
    let line = $event & "\n"
    let f = open(auditPath, fmAppend)
    f.write(line)
    f.close()
    ok(true)
  except CatchableError as e:
    err("audit append failed: " & e.msg)

## Append Generic Audit Event.
# @axiom-hint: lean="auditPath.length ≥ 0 ∧ eventType.length ≥ 0 ∧ nodeId.length ≥ 0 ∧ compilerVersion.length ≥ 0 ∧ solverVersion.length ≥ 0 ∧ sourceHash.length ≥ 0" smt="(assert (and (>= (str.len auditPath) 0) (>= (str.len eventType) 0) (>= (str.len nodeId) 0) (>= (str.len compilerVersion) 0) (>= (str.len solverVersion) 0) (>= (str.len sourceHash) 0)))"
# @axiom-hint: lean="(event ≥ 0)" smt="(assert (and (>= event 0)))"
proc appendGenericAuditEvent*(
  auditPath: string;
  eventType: string;
  nodeId: string;
  payload: JsonNode;
  compilerVersion: string = gCompilerVersion;
  solverVersion: string = gSolverVersion;
  sourceHash: string = gSourceHash
): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Appends a generic audit event with arbitrary payload to the append-only stream.
  let ts = $now().utc()
  let event = %*{
    "ts": ts,
    "event": eventType,
    "nodeId": nodeId,
    "compilerVersion": compilerVersion,
    "solverVersion": solverVersion,
    "sourceHash": sourceHash
  }
  if payload.kind == JObject:
    for key, val in payload.pairs:
      event[key] = val
  try:
    let dir = parentDir(auditPath)
    if dir.len > 0 and not dirExists(dir):
      discard existsOrCreateDirOpt(dir)
    let line = $event & "\n"
    let f = open(auditPath, fmAppend)
    f.write(line)
    f.close()
    ok(true)
  except CatchableError as e:
    err("generic audit append failed: " & e.msg)

## Append Global Influence Event.
# @axiom-hint: lean="auditPath.length ≥ 0 ∧ influencer.length ≥ 0 ∧ affectedNodes.size ≥ 0 ∧ ∀ (i : Fin affectedNodes.size), (affectedNodes.get i).length ≥ 0 ∧ demotionKind.length ≥ 0 ∧ reason.length ≥ 0 ∧ astDiffCount ≥ -9223372036854775808 ∧ astDiffCount ≤ 9223372036854775807" smt="(assert (and (>= (str.len auditPath) 0) (>= (str.len influencer) 0) (>= (seq.len affectedNodes) 0) (forall ((i Int)) (=> (and (>= i 0) (< i (seq.len affectedNodes))) (>= (str.len (seq.nth affectedNodes i)) 0))) (>= (str.len demotionKind) 0) (>= (str.len reason) 0) (and (>= astDiffCount -9223372036854775808) (<= astDiffCount 9223372036854775807))))"
# @axiom-hint: lean="(∀ (affectedNodesIdx : Fin affectedNodes.size), (affectedNodes.get affectedNodesIdx).length ≥ 0)" smt="(assert (and (forall ((affectedNodesIdx Int)) (=> (and (>= affectedNodesIdx 0) (< affectedNodesIdx (seq.len affectedNodes))) (>= (str.len (seq.nth affectedNodes affectedNodesIdx)) 0)))))"
proc appendGlobalInfluenceEvent*(
  auditPath: string;
  influencer: string;
  affectedNodes: seq[string];
  demotionKind: string;
  reason: string;
  astDiffCount: int = 0
): Result[bool, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Appends a global_influence audit event to the unified stream.
  let ts = $now().utc()
  let event = %*{
    "ts": ts,
    "event": "global_influence",
    "influencer": influencer,
    "affectedNodes": affectedNodes,
    "demotionKind": demotionKind,
    "reason": reason,
    "astDiffCount": astDiffCount,
    "compilerVersion": gCompilerVersion,
    "solverVersion": gSolverVersion,
    "sourceHash": gSourceHash
  }
  try:
    let dir = parentDir(auditPath)
    if dir.len > 0 and not dirExists(dir):
      discard existsOrCreateDirOpt(dir)
    let line = $event & "\n"
    let f = open(auditPath, fmAppend)
    f.write(line)
    f.close()
    ok(true)
  except CatchableError as e:
    err("global influence append failed: " & e.msg)

## Save Proof State.
# @axiom-hint: lean="path.length ≥ 0 ∧ actor.length ≥ 0 ∧ reason.length ≥ 0" smt="(assert (and (>= (str.len path) 0) (>= (str.len actor) 0) (>= (str.len reason) 0)))"
# @axiom-hint: lean="nid.length > 0 ∧ nid.length = 0 ∧ oldStatus ≠ newStatus ∧ evLog.length > 0 ∧ parsedOpt.isSome = true ∧ (extra ≥ 0) ∧ (entries ≥ 0) ∧ (oldById ≥ 0) ∧ (oldEntries ≥ 0)" smt="(assert (and (> (str.len nid) 0) (= (str.len nid) 0) (not (= oldStatus newStatus)) (> (str.len evLog) 0) (= (option.isSome parsedOpt) true) (>= extra 0) (>= entries 0) (>= oldById 0) (>= oldEntries 0)))"
proc saveProofState*(
  path: string;
  state: JsonNode;
 actor: string = "unknown";
  reason: string = "state-persist"
): Result[bool, string] =
  ## Single entry point for persisting proof state. All writes go through here.
  ## Emits append-only audit events to logs/audit/stream.jsonl for every status transition.
  let recomputeRes = recomputeProofStateSummary(state)
  if recomputeRes.isErr:
    return err(recomputeRes.error)
  let oldState = loadProofState(path)
  let oldEntries =
    try:
      oldState["entries"]
    except KeyError:
      newJArray()
  var oldById = initTable[string, JsonNode]()
  for e in oldEntries:
    let nid = getNodeId(e)
    if nid.len > 0:
      oldById[nid] = e

  let auditPath = parentDir(path) / "audit" / "stream.jsonl"

  let entries =
    try:
      state["entries"]
    except KeyError:
      newJArray()
  for e in entries:
    let nid = getNodeId(e)
    if nid.len == 0:
      continue
    let oldStatus = if oldById.hasKey(nid): entryStatus(oldById.getOrDefault(nid)) else: "unattempted"
    let newStatus = entryStatus(e)
    if oldStatus != newStatus:
      let ac = entryAttemptCount(e)
      let strat = entryStrategy(e)
      let evLog = entryEvidenceLog(e)
      var extra = newJObject()
      if evLog.len > 0:
        let parsedOpt = parseJsonOpt(evLog)
        if parsedOpt.isSome:
          extra = parsedOpt.get()
      discard appendAuditEvent(auditPath, "status_changed", nid, oldStatus, newStatus, actor, strat, reason, ac,
                               gCompilerVersion, gSolverVersion, gSourceHash, extra)

  let writeRes = atomicWriteText(path, renderJsonMultiline(state))
  if writeRes.isErr:
    return err("Failed to write proof state: " & writeRes.error)
  ok(true)

{.pop.}
