## adversarial_suite_runner.nim — R8c adversarial harness
##
## Constructs each of the 8 adversarial classes and asserts the
## gate-level outcome by wiring through the real engine path
## (computeSelection / verifyPlanDigest / fromJson / checkCompleteness).
##
## Exit codes mirror selection_report.nim:
##   0 — all cases pass (outcome matches expected)
##   1 — one or more cases failed (or general error)
##
## Usage:
##   adversarial-suite-runner                    # run all 8 cases
##   adversarial-suite-runner --case unresolved-edge
##   adversarial-suite-runner --case stale-graph
##   adversarial-suite-runner --case incomplete-graph
##   adversarial-suite-runner --case tampered-plan
##   adversarial-suite-runner --case corrupted-json
##   adversarial-suite-runner --case integrity-insert
##   adversarial-suite-runner --case integrity-remove
##   adversarial-suite-runner --case provenance-tamper
##
## See: docs/spec/ci_execution_plan_rollout.md §10.6
##      plans/ravager-jericho-amadeus-cho.md (contract)

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, json, strutils, strformat, tables, sequtils, sets, algorithm,
            options, parseopt]

import core/types/canonical_change_set
import core/types/graph_artifact
import core/types/selection_derivation
import core/types/execution_plan
import core/types/request_id
import core/topology/topology_types
import verification/selection/selection_engine
import verification/selection/selection_digests
import verification/selection/request_derivation
import verification/selection/request_oracle
import verification/selection/request_completeness
import core/types/request_derivation_types

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

proc makeCanonicalChangeSet*(
  baseCommit = "base_sha_aaa"
; headCommit = "head_sha_bbb"
; mergeBase: seq[string] = @["merge_sha_ccc"]
; diffDigest = "diff_hash_123"
): CanonicalChangeSet =
  CanonicalChangeSet(
    baseCommit: baseCommit,
    headCommit: headCommit,
    mergeBase: mergeBase,
    canonicalDiffDigest: diffDigest,
    diffInterpretationPolicy: DiffInterpretationPolicy())

proc makeGraphArtifact*(
  structureDigest = "struct_digest_1"
; constructionInputsDigest = "inputs_digest_2"
; policyDigest = "policy_digest_3"
; unresolvedEdges: seq[TopologyUnresolvedEdge] = @[]
; builderVersion = "2"
): GraphArtifact =
  GraphArtifact(
    structureDigest: structureDigest,
    constructionInputsDigest: constructionInputsDigest,
    interpretationPolicyDigest: policyDigest,
    unresolvedEdges: unresolvedEdges.map(toGraphUnresolvedEdge),
    builderVersion: builderVersion)

proc makeSelectorInputs*(
  universe: seq[string] = @["A", "B"]
; changedSymbolSeeds: seq[string] = @["A"]
; unresolvedEdges: seq[TopologyUnresolvedEdge] = @[]
; builderVersion: string = "2"
; policyDigest: string = "policy_1"
; symbolDeps: Table[string, seq[string]] = initTable[string, seq[string]]()
; symbolDependents: Table[string, seq[string]] = initTable[string, seq[string]]()
): SelectorInputs =
  let changeSet = makeCanonicalChangeSet()
  let graph = makeGraphArtifact(
    unresolvedEdges = unresolvedEdges,
    builderVersion = builderVersion)

  # Ensure all universe symbols have entries in deps tables
  var deps = symbolDeps
  var dependents = symbolDependents
  for sym in universe:
    if sym notin deps:
      deps[sym] = @[]
    if sym notin dependents:
      dependents[sym] = @[]

  SelectorInputs(
    changeSet: changeSet,
    graph: graph,
    symbolDeps: deps,
    symbolDependents: dependents,
    universe: universe,
    policyDigest: policyDigest,
    changedSymbolSeeds: changedSymbolSeeds)

# ---------------------------------------------------------------------------
# FULL-group cases (→ FALLBACK_REQUIRED → umFull → exit 2)
# ---------------------------------------------------------------------------

type AdversarialResult = object
  caseName*: string
  expectedStatus*: SelectionStatus
  expectedMode*: UniverseMode
  actualStatus*: SelectionStatus
  actualMode*: UniverseMode
  passed*: bool
  detail*: string

proc runFullGroup*(caseName: string; inputs: SelectorInputs): AdversarialResult =
  let outcome = computeSelection(inputs)
  AdversarialResult(
    caseName: caseName,
    expectedStatus: ssFallbackRequired,
    expectedMode: umFull,
    actualStatus: outcome.derivation.status,
    actualMode: outcome.plan.mode,
    passed: outcome.derivation.status == ssFallbackRequired and
            outcome.plan.mode == umFull,
    detail: &"status={outcome.derivation.status} mode={outcome.plan.mode} fallbackReason={outcome.derivation.fallbackReason}")

# Case 1: unresolved graph edge
proc caseUnresolvedEdge*(): AdversarialResult =
  let edge = TopologyUnresolvedEdge(
    fromNodeId: sorterNodeId("0"),
    targetName: "unknown_target",
    modulePath: "src/core/unknown.nim",
    resolutionKind: rrUnresolved)
  let inputs = makeSelectorInputs(unresolvedEdges = @[edge])
  runFullGroup("unresolved-edge", inputs)

# Case 2: stale graph (empty builderVersion)
proc caseStaleGraph*(): AdversarialResult =
  let inputs = makeSelectorInputs(builderVersion = "")
  runFullGroup("stale-graph", inputs)

# Case 3: valid-but-incomplete graph (changed seed not in universe or graph)
proc caseIncompleteGraph*(): AdversarialResult =
  let inputs = makeSelectorInputs(
    universe = @["A", "B"]
  , changedSymbolSeeds = @["A", "unknown_seed"])
  runFullGroup("incomplete-graph", inputs)

# ---------------------------------------------------------------------------
# REJECT-group cases (→ ERROR → exit 1 / no partial execution)
# ---------------------------------------------------------------------------

type RejectResult = object
  caseName*: string
  passed*: bool
  detail*: string

# Case 4: malformed witness (verifyPlanDigest fail)
proc caseTamperedPlan*(): RejectResult =
  let deriv = SelectionDerivation(
    inputDigests: SelectionInputs(
      changeSetDigest: "cs", graphDigest: "g",
      universeDigest: "u", policyDigest: "p"),
    status: ssValid, selected: @[], excluded: @[],
    fallbackReason: "", witnessDigest: "")
  var plan = makeExecutionPlan(deriv, umSelected, @["m::f"])
  # Tamper: change a selected unit after plan signing
  plan.selectedUnitIds = @["m::f", "m::injected"]
  let digestOk = verifyPlanDigest(plan)
  RejectResult(
    caseName: "tampered-plan",
    passed: not digestOk,
    detail: &"verifyPlanDigest={digestOk} " &
            "(expected false = tampering detected)")

# Case 5: corrupted plan (invalid JSON)
proc caseCorruptedJson*(): RejectResult =
  # A non-object JSON node is rejected by ExecutionPlan.fromJson
  let badJson = %*"not a plan"
  let planOpt = execution_plan.fromJson(badJson)
  RejectResult(
    caseName: "corrupted-json",
    passed: planOpt.isNone,
    detail: &"fromJson-none={planOpt.isNone} " &
            "(expected true = corrupted JSON rejected)")

# Case 6: integrity-insert (unauthorized request appended)
proc caseIntegrityInsert*(): RejectResult =
  let required = @[makeRequestId(@["unit_a"])]
  let derived = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]
  let dispositions: seq[Disposition] = @[]
  let checkResult = checkCompleteness(required, derived, dispositions)
  RejectResult(
    caseName: "integrity-insert",
    passed: not checkResult.ok and checkResult.unauthorized.len > 0,
    detail: &"ok={checkResult.ok} unauthorized={checkResult.unauthorized.len} " &
            "(expected unauthorized request detected)")

# Case 7: integrity-remove (required request missing)
proc caseIntegrityRemove*(): RejectResult =
  let required = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]
  let derived = @[makeRequestId(@["unit_a"])]
  let dispositions: seq[Disposition] = @[]
  let checkResult = checkCompleteness(required, derived, dispositions)
  RejectResult(
    caseName: "integrity-remove",
    passed: not checkResult.ok and checkResult.missing.len > 0,
    detail: &"ok={checkResult.ok} missing={checkResult.missing.len} " &
            "(expected missing required request detected)")

# Case 8: integrity-provenance-tamper (changed RequestId sources)
proc caseProvenanceTamper*(): RejectResult =
  let required = @[makeRequestId(@["unit_a"])]
  let derived = @[makeRequestId(@["unit_x"])]  # different source fields
  let dispositions = @[Disposition(
    kind: dkFallback,
    requestId: makeRequestId(@["unit_x"]),
    evidence: "basis: unit_x",
    basis: "unit_x")]  # INVALID basis for dkFallback → caught by strengthened check
  let checkResult = checkCompleteness(required, derived, dispositions)
  RejectResult(
    caseName: "provenance-tamper",
    passed: not checkResult.ok,
    detail: &"ok={checkResult.ok} missing={checkResult.missing.len} " &
            "(expected provenance mismatch / basis mismatch detected)")

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

proc printHelp() =
  echo ""
  echo "  adversarial-suite-runner — R8c adversarial 8-class outcome harness"
  echo ""
  echo "  Usage:"
  echo "    adversarial-suite-runner [--case <name>]"
  echo ""
  echo "  Cases:"
  echo "    unresolved-edge      FULL-group: unresolved graph edge"
  echo "    stale-graph          FULL-group: empty builderVersion"
  echo "    incomplete-graph     FULL-group: valid but incomplete graph"
  echo "    tampered-plan        REJECT-group: verifyPlanDigest fail"
  echo "    corrupted-json       REJECT-group: invalid JSON plan"
  echo "    integrity-insert     REJECT-group: unauthorized request appended"
  echo "    integrity-remove     REJECT-group: required request missing"
  echo "    provenance-tamper    REJECT-group: changed RequestId sources"
  echo ""
  echo "  Exit codes:"
  echo "    0 — all cases pass"
  echo "    1 — one or more cases failed"
  echo ""

proc main() =
  var caseFilter = ""
  var showHelp = false

  var p = initOptParser(commandLineParams(),
                        shortNoVal = {'h'},
                        longNoVal = @["help"])
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "case", "c":
        caseFilter = p.val
      of "help", "h":
        showHelp = true
      else:
        echo &"[adversarial-suite-runner] Unknown option: {p.key}"
        showHelp = true
    of cmdArgument:
      if caseFilter.len == 0:
        caseFilter = p.key

  if showHelp:
    printHelp()
    if caseFilter.len == 0 and not showHelp:
      quit(1)
    return

  var allPassed = true
  var results: seq[string] = @[]

  # Define all 8 cases: FULL-group first, then REJECT-group
  let fullCases: seq[(string, proc(): AdversarialResult)] = @[
    ("unresolved-edge", caseUnresolvedEdge),
    ("stale-graph", caseStaleGraph),
    ("incomplete-graph", caseIncompleteGraph),
  ]

  let rejectCases: seq[(string, proc(): RejectResult)] = @[
    ("tampered-plan", caseTamperedPlan),
    ("corrupted-json", caseCorruptedJson),
    ("integrity-insert", caseIntegrityInsert),
    ("integrity-remove", caseIntegrityRemove),
    ("provenance-tamper", caseProvenanceTamper),
  ]

  # Run FULL-group cases
  echo "[adversarial-suite-runner] Running FULL-group cases (→ FALLBACK_REQUIRED / umFull / exit 2):"
  for (name, runner) in fullCases:
    if caseFilter.len > 0 and caseFilter != name:
      continue
    let r = runner()
    let status = if r.passed: "PASS" else: "FAIL"
    echo &"[adversarial-suite-runner]   [{status}] {name}: {r.detail}"
    if not r.passed:
      allPassed = false
    results.add(&"{name}: {status}")

  # Run REJECT-group cases
  echo "[adversarial-suite-runner] Running REJECT-group cases (→ ERROR / exit 1 / no partial execution):"
  for (name, runner) in rejectCases:
    if caseFilter.len > 0 and caseFilter != name:
      continue
    let r = runner()
    let status = if r.passed: "PASS" else: "FAIL"
    echo &"[adversarial-suite-runner]   [{status}] {name}: {r.detail}"
    if not r.passed:
      allPassed = false
    results.add(&"{name}: {status}")

  echo ""
  echo &"[adversarial-suite-runner] Summary:"
  for r in results:
    echo &"  {r}"

  if allPassed:
    echo &"[adversarial-suite-runner] All 8 adversarial cases passed."
    quit(0)
  else:
    echo &"[adversarial-suite-runner] One or more cases FAILED."
    quit(1)

when isMainModule:
  main()
{.pop.}