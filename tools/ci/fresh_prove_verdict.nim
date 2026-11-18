import core/trusted/layer_declaration
axiomLayer "tools"

## fresh_prove_verdict.nim — independent four-state projection of one
## `ax prove` state document (VS-AUTH-FRESH observation lane).
##
## This tool is NOT a verdict authority. It never changes the run's exit code,
## never mints a certificate, and never promotes a check. It re-derives the
## four states from the RAW persisted rows so an observation lane can publish
## what actually happened — including "cannot conclude".
##
## State semantics (docs/spec/fresh_prove_contract.md):
##   PROVED       every REQUIRED unit SATISFIED with a FRESH invocation
##                witness, no anomalies, closure complete, and the declared
##                scope fully classified.
##   REFUTED      a REQUIRED unit carries a machine-readable refutation
##                witness. A bare `failed` row is NOT a refutation: the
##                current engine records unsupported syntax as `failed` with
##                no witness, which is UNKNOWN, never REFUTED.
##   OUT_OF_SCOPE a unit is explicitly listed in `scopeContract.outOfScope`.
##                NOT_REQUIRED alone is not an exclusion — it is UNKNOWN.
##   UNKNOWN      everything else (unsupported syntax, timeout, pending,
##                reuse-satisfied, missing marker, incomplete closure/scope).
##
## Canonical binding: `canonicalEvidence` is the deterministic payload
## (subject, scope lock digest, verifier identity, freshness declaration,
## sorted unit rows, closure/coverage facts). `provenance` holds runId /
## attempt / URL / timestamps and is deliberately NOT hashed, so two runs over
## identical inputs produce the same `canonicalEvidenceDigest`.
##
## Usage:
##   bin/fresh_prove_verdict --state <ax_proof_state.json>
##     [--scope-lock data/verification_scope.lock] [--out <file>]
##     [--subject-sha <sha>] [--subject-tree <tree>]
##     [--run-id <id>] [--attempt <n>] [--run-url <url>] [--runner <name>]
##
## Exit: 0 = PROVED · 1 = REFUTED · 3 = UNKNOWN/OUT_OF_SCOPE · 2 = usage or
## unreadable input (fail-closed, never a silent skip).

import std/[algorithm, json, os, parseopt, sets, strutils, times]
import core/crypto/hash_kernel
import core/results

const
  VerdictContract* = "axiom.fresh-verdict.v1"
  FreshContract* = "axiom.fresh-prove.v1"
  ExitProved* = 0
  ExitRefuted* = 1
  ExitError* = 2
  ExitUnknown* = 3

type
  Options* = object
    statePath*: string
    scopeLockPath*: string
    outPath*: string
    subjectSha*: string
    subjectTree*: string
    runId*: string
    attempt*: string
    runUrl*: string
    runner*: string
    hasOut*: bool

func jNil(n: JsonNode): bool {.raises: [].} =
  n.isNil or n.kind == JNull

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

func hasObj(n: JsonNode): bool {.raises: [].} =
  not n.isNil and n.kind == JObject

func hasRefutationWitness(row: JsonNode): bool {.raises: [].} =
  ## A witness must be machine-readable and non-empty. The current engine
  ## emits none, so `failed` rows project to UNKNOWN by construction.
  if not hasObj(row):
    return false
  for field in ["refutationWitness", "counterexample", "witness"]:
    let v = row{field}
    if v.isNil:
      continue
    case v.kind
    of JObject, JArray:
      if v.len > 0:
        return true
    of JString:
      if v.getStr().strip().len > 0:
        return true
    else:
      discard

func nodeIdOf(row: JsonNode): string {.raises: [].} =
  if not hasObj(row):
    return ""
  result = jStr(row, "nodeId")
  if result.len == 0:
    result = jStr(row, "unitId")

func witnessFor(nodeReports: JsonNode; unitId: string): bool {.raises: [].} =
  if nodeReports.isNil or nodeReports.kind != JArray:
    return false
  for row in nodeReports.elems:
    if nodeIdOf(row) == unitId and hasRefutationWitness(row):
      return true

func outOfScopeSet(state: JsonNode): HashSet[string] {.raises: [].} =
  result = initHashSet[string]()
  let contract = jObj(state, "scopeContract")
  if contract.isNil:
    return
  for key in ["outOfScope", "excluded"]:
    let arr = jArr(contract, key)
    if arr.isNil:
      continue
    for item in arr.elems:
      if item.kind == JString:
        result.incl(item.getStr())

func classifyUnit*(unit: JsonNode; freshDeclared: bool;
                  nodeReports: JsonNode;
                  outOfScope: HashSet[string]): tuple[state, reason: string]
    {.raises: [].} =
  let unitId = jStr(unit, "unitId")
  let decision = jStr(unit, "requirementDecision")
  let outcome = jStr(unit, "verificationOutcome")
  let source = jStr(unit, "satisfactionSource")
  let consistency = jStr(unit, "consistency")

  if decision == "NOT_REQUIRED":
    if unitId.len > 0 and outOfScope.contains(unitId):
      return ("OUT_OF_SCOPE", "explicit-scope-contract-exclusion")
    return ("UNKNOWN", "not-required-without-scope-contract")

  if outcome == "SATISFIED":
    if source == "FRESH" and freshDeclared:
      return ("PROVED", "fresh-invocation-witness")
    if source == "FRESH":
      return ("UNKNOWN", "freshness-not-declared")
    if source == "REUSED":
      return ("UNKNOWN", "satisfied-by-reuse")
    return ("UNKNOWN", "satisfied-without-invocation-witness")

  if outcome == "UNSATISFIED":
    if witnessFor(nodeReports, unitId):
      return ("REFUTED", "machine-readable-refutation-witness")
    return ("UNKNOWN", "unsatisfied-without-refutation-witness")

  if outcome == "PENDING":
    if consistency == "CONTESTED":
      return ("UNKNOWN", "pending-contested")
    return ("UNKNOWN", "pending")

  if decision == "UNRESOLVED":
    return ("UNKNOWN", "unresolved-requirement-decision")

  ("UNKNOWN", "unclassified-unit")

func coverageProjection*(state: JsonNode; scope: JsonNode): JsonNode
    {.raises: [].} =
  ## Every symbol in the declared scope lock must be accounted for by one of:
  ## declaredRequired, run units, census candidates, eligibility map, or an
  ## explicit scopeContract exclusion. Anything else is an unclassified gap
  ## and blocks PROVED.
  var accounted = initHashSet[string]()
  let declared = jArr(state, "declaredRequired")
  if not declared.isNil:
    for item in declared.elems:
      if item.kind == JString:
        accounted.incl(item.getStr())

  let units = jArr(jObj(state, "runAccounting"), "units")
  if not units.isNil:
    for unit in units.elems:
      let id = jStr(unit, "unitId")
      if id.len > 0:
        accounted.incl(id)

  let candidates = jArr(jObj(state, "census"), "candidates")
  if not candidates.isNil:
    for cand in candidates.elems:
      let modulePath = jStr(cand, "modulePath")
      let functionName = jStr(cand, "functionName")
      if modulePath.len > 0 and functionName.len > 0:
        accounted.incl(modulePath & "::" & functionName)

  let eligibility = jObj(state, "eligibility")
  if not eligibility.isNil:
    for symbol, value in eligibility.pairs:
      if value.kind == JString and symbol.len > 0:
        accounted.incl(symbol)

  for symbol in outOfScopeSet(state):
    accounted.incl(symbol)

  var symbols: seq[string] = @[]
  let scopeSymbols = jArr(scope, "kernel_symbols")
  if not scopeSymbols.isNil:
    for item in scopeSymbols.elems:
      if item.kind == JString:
        symbols.add(item.getStr())
  sort(symbols)

  var missing: seq[string] = @[]
  for symbol in symbols:
    if not accounted.contains(symbol):
      missing.add(symbol)

  result = newJObject()
  result["scopeSymbolCount"] = %symbols.len
  result["accountedCount"] = %(symbols.len - missing.len)
  result["missingCount"] = %missing.len
  result["missing"] = %missing
  result["complete"] = %(symbols.len > 0 and missing.len == 0)

func sortedUnitRows(state: JsonNode): seq[JsonNode] {.raises: [].} =
  let units = jArr(jObj(state, "runAccounting"), "units")
  if not units.isNil:
    for unit in units.elems:
      if hasObj(unit):
        result.add(unit)
  result.sort(proc(a, b: JsonNode): int {.raises: [].} =
    cmp(jStr(a, "unitId"), jStr(b, "unitId")))

func buildCanonicalEvidence*(state: JsonNode; scope: JsonNode;
                            scopeLockDigest, subjectSha, subjectTree: string):
                            JsonNode {.raises: [].} =
  ## Deterministic payload only. No runId, no attempt, no timestamps, no
  ## runner identity, no wall-clock counters.
  let identity = jObj(state, "executionIdentity")
  let accounting = jObj(state, "runAccounting")
  let closure = jObj(state, "closure")
  let freshness = jObj(state, "freshness")
  let coverage = coverageProjection(state, scope)
  let units = sortedUnitRows(state)

  var unitRows = newJArray()
  for unit in units:
    var row = newJObject()
    row["unitId"] = %jStr(unit, "unitId")
    row["requirementDecision"] = %jStr(unit, "requirementDecision")
    row["verificationOutcome"] = %jStr(unit, "verificationOutcome")
    row["consistency"] = %jStr(unit, "consistency")
    row["executionEvidence"] = %jStr(unit, "executionEvidence")
    row["satisfactionSource"] = %jStr(unit, "satisfactionSource")
    unitRows.add(row)

  var scopeBinding = newJObject()
  scopeBinding["lockDigest"] = %scopeLockDigest
  scopeBinding["symbolCount"] = %jInt(scope, "kernel_total")
  scopeBinding["coverage"] = coverage

  var verifier = newJObject()
  verifier["verifierBuildId"] = %jStr(identity, "verifierBuildId")
  verifier["toolchainIdentity"] = %jStr(identity, "toolchainIdentity")
  verifier["executionConfigDigest"] = %jStr(identity, "executionConfigDigest")
  verifier["executionBundleFingerprint"] =
    %jStr(identity, "executionBundleFingerprint")
  verifier["executionEpoch"] = %jStr(identity, "executionEpoch")

  var freshnessBinding = newJObject()
  freshnessBinding["contract"] = %(if freshness.isNil: "" else: jStr(freshness, "contract"))
  freshnessBinding["declared"] = %(not freshness.isNil)
  freshnessBinding["fresh"] = %jBool(freshness, "fresh")
  var bypass = newJArray()
  let bypassArr = jArr(freshness, "reuseBypass")
  if not bypassArr.isNil:
    for item in bypassArr.elems:
      if item.kind == JString:
        bypass.add(%item.getStr())
  freshnessBinding["reuseBypass"] = bypass

  var accountingProjection = newJObject()
  for key in ["requiredCount", "satisfiedCount", "unsatisfiedCount",
              "pendingCount", "contestedCount", "notAttemptedCount",
              "notRequiredCount", "proofFailedCount", "freshExecutionCount",
              "satisfiedByFresh", "satisfiedByReused", "unresolvedDecisionCount"]:
    accountingProjection[key] = %jInt(accounting, key)

  var closureProjection = newJObject()
  closureProjection["closureComplete"] = %jBool(closure, "closureComplete")
  closureProjection["requiredCount"] = %jInt(closure, "requiredCount")
  closureProjection["completedCount"] = %jInt(closure, "completedCount")
  closureProjection["kernelScopeSize"] = %jInt(closure, "kernelScopeSize")
  closureProjection["universeCount"] = %jInt(closure, "universeCount")

  result = newJObject()
  result["contract"] = %VerdictContract
  result["schemaVersion"] = %jStr(state, "schemaVersion")
  result["subject"] = %*{"sha": subjectSha, "tree": subjectTree}
  result["scope"] = scopeBinding
  result["verifier"] = verifier
  result["freshness"] = freshnessBinding
  result["runAccounting"] = accountingProjection
  result["closure"] = closureProjection
  result["canonicalRunDigest"] = %jStr(state, "canonicalRunDigest")
  result["units"] = unitRows

func checkConclusionOf*(verdict: string; contractViolations: int): string
    {.raises: [].} =
  case verdict
  of "PROVED": "success"
  of "REFUTED": "failure"
  else: (if contractViolations > 0: "failure" else: "neutral")

func exitCodeOf*(verdict: string): int {.raises: [].} =
  case verdict
  of "PROVED": ExitProved
  of "REFUTED": ExitRefuted
  else: ExitUnknown

func projectVerdict*(state: JsonNode; scope: JsonNode;
                    scopeLockDigest, subjectSha, subjectTree: string):
                    JsonNode {.raises: [].} =
  let freshness = jObj(state, "freshness")
  let freshDeclared = not freshness.isNil and
    (freshness.hasKey("fresh") or jStr(freshness, "contract").len > 0)
  let fresh = jBool(freshness, "fresh")
  let nodeReports = jArr(state, "nodeReports")
  let outOfScope = outOfScopeSet(state)
  let units = sortedUnitRows(state)
  let accounting = jObj(state, "runAccounting")
  let closure = jObj(state, "closure")
  let coverage = coverageProjection(state, scope)

  var unitRows = newJArray()
  var provedCount = 0
  var refutedCount = 0
  var unknownCount = 0
  var outOfScopeCount = 0
  var requiredCount = 0
  var reasons: seq[string] = @[]
  template addReason(reason: string) =
    if reason.len > 0 and reason notin reasons:
      reasons.add(reason)

  for unit in units:
    let (unitState, reason) = classifyUnit(unit, freshDeclared and fresh,
      nodeReports, outOfScope)
    let decision = jStr(unit, "requirementDecision")
    if decision == "REQUIRED":
      inc requiredCount
    case unitState
    of "PROVED": inc provedCount
    of "REFUTED": inc refutedCount
    of "OUT_OF_SCOPE": inc outOfScopeCount
    else:
      inc unknownCount
      addReason(reason)
    var row = newJObject()
    row["unitId"] = %jStr(unit, "unitId")
    row["state"] = %unitState
    row["reason"] = %reason
    row["requirementDecision"] = %decision
    row["verificationOutcome"] = %jStr(unit, "verificationOutcome")
    row["satisfactionSource"] = %jStr(unit, "satisfactionSource")
    row["executionEvidence"] = %jStr(unit, "executionEvidence")
    unitRows.add(row)

  let satisfiedByReused = jInt(accounting, "satisfiedByReused")
  let anomalies = jArr(accounting, "anomalies")
  let anomalyCount = if anomalies.isNil: 0 else: anomalies.len
  let closureComplete = jBool(closure, "closureComplete")
  let verificationComplete = jBool(jObj(state, "runOutcome"), "verificationComplete")
  let runVerdict = jStr(jObj(state, "runOutcome"), "verdict")

  var contractViolations: seq[string] = @[]
  if not freshDeclared:
    contractViolations.add("freshness-marker-absent")
  elif not fresh:
    contractViolations.add("freshness-not-requested")
  if satisfiedByReused != 0:
    contractViolations.add("satisfied-by-reused-nonzero")
  for violation in contractViolations:
    addReason(violation)

  var proved = false
  if requiredCount > 0 and provedCount == requiredCount and
      refutedCount == 0 and unknownCount == 0 and outOfScopeCount == 0 and
      jInt(accounting, "satisfiedCount") == requiredCount and
      jInt(accounting, "unsatisfiedCount") == 0 and
      jInt(accounting, "pendingCount") == 0 and
      jInt(accounting, "contestedCount") == 0 and
      jInt(accounting, "notAttemptedCount") == 0 and
      jInt(accounting, "proofFailedCount") == 0 and
      jInt(accounting, "unresolvedDecisionCount") == 0 and
      contractViolations.len == 0 and anomalyCount == 0 and
      closureComplete and verificationComplete and runVerdict == "PASS" and
      jBool(coverage, "complete") and subjectSha.len > 0:
    proved = true
  else:
    if requiredCount == 0:
      addReason("required-set-empty")
    if not closureComplete:
      addReason("closure-incomplete")
    if not verificationComplete or runVerdict != "PASS":
      addReason("vda-not-pass")
    if not jBool(coverage, "complete"):
      addReason("scope-coverage-incomplete")
    if anomalyCount > 0:
      addReason("accounting-anomalies")
    if subjectSha.len == 0:
      addReason("subject-sha-absent")

  let overall = if refutedCount > 0: "REFUTED"
                elif proved: "PROVED"
                else: "UNKNOWN"

  var freshnessProjection = newJObject()
  freshnessProjection["declared"] = %freshDeclared
  freshnessProjection["fresh"] = %fresh
  freshnessProjection["authoritative"] = %false
  freshnessProjection["satisfiedByReused"] = %satisfiedByReused

  var counts = newJObject()
  counts["units"] = %units.len
  counts["required"] = %requiredCount
  counts["proved"] = %provedCount
  counts["refuted"] = %refutedCount
  counts["unknown"] = %unknownCount
  counts["outOfScope"] = %outOfScopeCount

  let canonicalEvidence = buildCanonicalEvidence(state, scope, scopeLockDigest,
    subjectSha, subjectTree)
  let canonicalDigest = sha256Hex($canonicalEvidence)

  var provenance = newJObject()
  let stateProv = jObj(state, "provenance")
  provenance["runId"] = %jStr(stateProv, "runId")
  provenance["attempt"] = %jStr(stateProv, "attempt")
  provenance["runUrl"] = %jStr(stateProv, "runUrl")
  provenance["runner"] = %jStr(stateProv, "runner")
  provenance["generatedAt"] = %jStr(stateProv, "generatedAt")

  result = newJObject()
  result["contract"] = %VerdictContract
  result["verdict"] = %overall
  result["counts"] = counts
  result["reasons"] = %reasons
  result["freshness"] = freshnessProjection
  result["coverage"] = coverage
  result["closure"] = %*{
    "closureComplete": closureComplete,
    "requiredCount": jInt(closure, "requiredCount"),
    "completedCount": jInt(closure, "completedCount")}
  result["canonicalEvidence"] = canonicalEvidence
  result["canonicalEvidenceDigest"] = %canonicalDigest
  result["provenance"] = provenance
  result["units"] = unitRows
  result["checkConclusion"] = %checkConclusionOf(overall, contractViolations.len)
  result["exitCode"] = %exitCodeOf(overall)

proc parseOptions(args: seq[string]): Result[Options, string] {.raises: [].} =
  var opts = Options(scopeLockPath: "data/verification_scope.lock")
  var pending = ""
  template assignOpt(key, val: string) =
    case key
    of "state": opts.statePath = val
    of "scope-lock", "scope": opts.scopeLockPath = val
    of "out": opts.outPath = val; opts.hasOut = true
    of "subject-sha": opts.subjectSha = val
    of "subject-tree": opts.subjectTree = val
    of "run-id": opts.runId = val
    of "attempt": opts.attempt = val
    of "run-url": opts.runUrl = val
    of "runner": opts.runner = val
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
      if key in ["help", "h"]:
        return err("usage: fresh_prove_verdict --state <file> [--scope-lock <file>] [--out <file>] [--subject-sha <sha>] [--subject-tree <tree>] [--run-id <id>] [--attempt <n>] [--run-url <url>] [--runner <name>]")
      if val.len > 0:
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
  if opts.statePath.len == 0:
    return err("--state is required")
  ok(opts)

proc main(args: seq[string]): int {.raises: [CatchableError].} =
  let parsed = parseOptions(args)
  if parsed.isErr():
    stderr.writeLine("[fresh-verdict] " & parsed.error)
    return ExitError
  let opts = parsed.get()

  if not fileExists(opts.statePath):
    stderr.writeLine("[fresh-verdict] state file not found: " & opts.statePath)
    return ExitError
  if not fileExists(opts.scopeLockPath):
    stderr.writeLine("[fresh-verdict] scope lock not found: " & opts.scopeLockPath)
    return ExitError

  var state: JsonNode
  var scope: JsonNode
  try:
    state = parseFile(opts.statePath)
    scope = parseFile(opts.scopeLockPath)
  except CatchableError as e:
    stderr.writeLine("[fresh-verdict] unreadable input: " & e.msg)
    return ExitError

  let scopeLockDigest = sha256Hex(readFile(opts.scopeLockPath))
  let verdict = projectVerdict(state, scope, scopeLockDigest,
    opts.subjectSha, opts.subjectTree)

  # Provenance is attached AFTER the canonical digest is computed — it must
  # never influence the digest.
  var provenance = verdict{"provenance"}
  if provenance.isNil or provenance.kind != JObject:
    provenance = newJObject()
  if opts.runId.len > 0: provenance["runId"] = %opts.runId
  if opts.attempt.len > 0: provenance["attempt"] = %opts.attempt
  if opts.runUrl.len > 0: provenance["runUrl"] = %opts.runUrl
  if opts.runner.len > 0: provenance["runner"] = %opts.runner
  if jStr(provenance, "generatedAt").len == 0:
    provenance["generatedAt"] = %now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  verdict["provenance"] = provenance

  var violationCount = 0
  let reasons = verdict{"reasons"}
  if not reasons.isNil:
    for reason in reasons.elems:
      if reason.kind == JString and reason.getStr() in [
          "freshness-marker-absent", "freshness-not-requested",
          "satisfied-by-reused-nonzero"]:
        inc violationCount
  let finalVerdict = jStr(verdict, "verdict")
  verdict["checkConclusion"] = %checkConclusionOf(finalVerdict, violationCount)
  verdict["exitCode"] = %exitCodeOf(finalVerdict)

  let rendered = pretty(verdict, indent = 2) & "\n"
  if opts.hasOut:
    let parent = parentDir(opts.outPath)
    if parent.len > 0 and not dirExists(parent):
      createDir(parent)
    writeFile(opts.outPath, rendered)
  stdout.write(rendered)
  exitCodeOf(jStr(verdict, "verdict"))

when isMainModule:
  quit(main(commandLineParams()))