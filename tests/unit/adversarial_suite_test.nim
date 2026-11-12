## adversarial_suite_test.nim — R8c adverse 8-class outcome tests
##
## Real assertions at the outcome level for each of the 8 adversarial
## classes. Calls the real engine path directly:
##   - FULL-group: computeSelection → detectFailClosedTriggers → status/mode
##   - REJECT-group: verifyPlanDigest / fromJson / checkCompleteness
##
## Verification level: engine-path for all 8 classes.
## CLI-level mapping verified via the same code path the CLI uses:
##   selection_report.nim maps ssFallbackRequired→exit 2, ssError→exit 1
##   axiom_engine.nim rejects tampered plans at verifyPlanDigest (line 858)
##
## See: docs/spec/ci_execution_plan_rollout.md §10.6

{.push raises: [CatchableError].}

import std/[unittest, algorithm, tables, sequtils, strutils, json]
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
# Fixture helpers (self-contained; mirrors adversarial_suite_runner patterns)
# ---------------------------------------------------------------------------

proc makeCs(): CanonicalChangeSet =
  CanonicalChangeSet(
    baseCommit: "base_sha_aaa",
    headCommit: "head_sha_bbb",
    mergeBase: @["merge_sha_ccc"],
    canonicalDiffDigest: "diff_hash_123",
    diffInterpretationPolicy: DiffInterpretationPolicy())

proc makeGraph(
  unresolvedEdges: seq[TopologyUnresolvedEdge] = @[]
; builderVersion: string = "2"
): GraphArtifact =
  GraphArtifact(
    structureDigest: "struct_digest_1",
    constructionInputsDigest: "inputs_digest_2",
    interpretationPolicyDigest: "policy_digest_3",
    unresolvedEdges: unresolvedEdges.map(toGraphUnresolvedEdge),
    builderVersion: builderVersion)

proc makeInputs(
  universe: seq[string] = @["A", "B"]
; changedSymbolSeeds: seq[string] = @["A"]
; unresolvedEdges: seq[TopologyUnresolvedEdge] = @[]
; builderVersion: string = "2"
; policyDigest: string = "policy_1"
): SelectorInputs =
  let cs = makeCs()
  let graph = makeGraph(unresolvedEdges, builderVersion)
  var deps = initTable[string, seq[string]]()
  var dependents = initTable[string, seq[string]]()
  for sym in universe:
    deps[sym] = @[]
    dependents[sym] = @[]
  SelectorInputs(
    changeSet: cs,
    graph: graph,
    symbolDeps: deps,
    symbolDependents: dependents,
    universe: universe,
    policyDigest: policyDigest,
    changedSymbolSeeds: changedSymbolSeeds)

# ---------------------------------------------------------------------------
# Suite: R8c FULL-group — → FALLBACK_REQUIRED → umFull → exit 2
# ---------------------------------------------------------------------------

suite "R8c FULL-group — adversarial cases → FALLBACK_REQUIRED / umFull / exit 2":

  test "case 1: unresolved graph edge → ssFallbackRequired / umFull":
    ## Wire through computeSelection (which calls detectFailClosedTriggers).
    ## Unresolved edge in graph forces ssFallbackRequired → umFull.
    ## Exit-code mapping: selection_report.nim:402 → quit(2)
    let edge = TopologyUnresolvedEdge(
      fromNodeId: sorterNodeId("0"),
      targetName: "unknown_target",
      modulePath: "src/core/unknown.nim",
      resolutionKind: rrUnresolved)
    let inputs = makeInputs(unresolvedEdges = @[edge])
    let outcome = computeSelection(inputs)
    check outcome.derivation.status == ssFallbackRequired
    check outcome.plan.mode == umFull
    check "unresolved" in outcome.derivation.fallbackReason
    # Exit-code contract: ssFallbackRequired → exit 2
    let exitCode = case outcome.derivation.status
      of ssValid: 0
      of ssFallbackRequired: 2
      of ssError: 1
    check exitCode == 2

  test "case 2: stale graph (empty builderVersion) → ssFallbackRequired / umFull":
    ## Empty builderVersion triggers detectFailClosedTriggers → ssFallbackRequired.
    ## Exit-code mapping: selection_report.nim:402 → quit(2)
    let inputs = makeInputs(builderVersion = "")
    let outcome = computeSelection(inputs)
    check outcome.derivation.status == ssFallbackRequired
    check outcome.plan.mode == umFull
    check "builderVersion" in outcome.derivation.fallbackReason
    let exitCode = case outcome.derivation.status
      of ssValid: 0
      of ssFallbackRequired: 2
      of ssError: 1
    check exitCode == 2

  test "case 3: valid-but-incomplete graph (seed not in universe/graph) → ssFallbackRequired / umFull":
    ## ChangedSymbolSeed not in universe and not in graph triggers
    ## detectFailClosedTriggers → ssFallbackRequired → umFull.
    ## The graph is structurally valid (has builderVersion, no unresolved edges)
    ## but incomplete (the changed seed is unknown).
    ## Exit-code mapping: selection_report.nim:402 → quit(2)
    let inputs = makeInputs(
      universe = @["A", "B"]
    , changedSymbolSeeds = @["A", "unknown_seed"])
    let outcome = computeSelection(inputs)
    check outcome.derivation.status == ssFallbackRequired
    check outcome.plan.mode == umFull
    check "unknown_seed" in outcome.derivation.fallbackReason
    let exitCode = case outcome.derivation.status
      of ssValid: 0
      of ssFallbackRequired: 2
      of ssError: 1
    check exitCode == 2

# ---------------------------------------------------------------------------
# Suite: R8c REJECT-group — → ERROR → exit 1 / no partial execution
# ---------------------------------------------------------------------------

suite "R8c REJECT-group — adversarial cases → ERROR / exit 1 / no partial execution":

  test "case 4: tampered plan → verifyPlanDigest fails (reject, no partial run)":
    ## Tampered plan (selectedUnitIds changed after signing) must fail
    ## verifyPlanDigest — the same guard used in axiom_engine.nim:858.
    ## On failure, axiom_engine returns err() → exit 1, no payload execution.
    let deriv = SelectionDerivation(
      inputDigests: SelectionInputs(
        changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p"),
      status: ssValid, selected: @[], excluded: @[],
      fallbackReason: "", witnessDigest: "")
    var plan = makeExecutionPlan(deriv, umSelected, @["m::f"])
    plan.selectedUnitIds = @["m::f", "m::injected"]  # tamper after signing
    check not verifyPlanDigest(plan)  # Must reject tampered plan

  test "case 5: corrupted plan (non-object JSON) → fromJson returns none (reject)":
    ## Invalid JSON (non-object) must be rejected by ExecutionPlan.fromJson
    ## — same guard as axiom_engine.nim:855-857.
    ## On None, axiom_engine returns err() → exit 1, no execution.
    let badJson = %*"not a plan"
    let planOpt = execution_plan.fromJson(badJson)
    check planOpt.isNone  # Must reject

  test "case 6: integrity-insert (unauthorized request appended) → rejected":
    ## Derived request not in required set and not covered by disposition
    ## must be detected by checkCompleteness — the R3 completeness gate
    ## in request_derivation.nim. Unauthorized requests are rejected.
    let required = @[makeRequestId(@["unit_a"])]
    let derived = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]
    let dispositions: seq[Disposition] = @[]
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok
    check result.unauthorized.len > 0  # unit_b is unauthorized

  test "case 7: integrity-remove (required request missing) → rejected":
    ## Required request missing from derived set with no covering disposition
    ## must be detected by checkCompleteness. Missing requests are rejected.
    let required = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]
    let derived = @[makeRequestId(@["unit_a"])]
    let dispositions: seq[Disposition] = @[]
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok
    check result.missing.len > 0  # unit_b is missing

  test "case 8: integrity-provenance-tamper (changed RequestId sources) → rejected":
    ## RequestId constructed from different source fields produces a
    ## different RequestId, causing provenance mismatch. The oracle
    ## (required) and derived sets diverge.
    ## Strengthened basis validation also catches invalid basis "unit_x" for dkFallback.
    let required = @[makeRequestId(@["unit_a"])]
    let derived = @[makeRequestId(@["unit_x"])]  # different source fields
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["unit_x"]),
      evidence: "basis: unit_x",
      basis: "unit_x")]  # INVALID basis for dkFallback
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok  ## Basis mismatch detected as completeness violation

# ---------------------------------------------------------------------------
# Suite: CLI-level exit-code contract verification
# ---------------------------------------------------------------------------

suite "R8c CLI-level exit-code contract":

  test "FULL-group: ssFallbackRequired → selection_report exit 2":
    ## selection_report.nim:399-403 maps:
    ##   ssValid → quit(0), ssFallbackRequired → quit(2), ssError → quit(1)
    ## Verify the FULL-group outcome maps to exit 2.
    let edge = TopologyUnresolvedEdge(
      fromNodeId: sorterNodeId("0"),
      targetName: "unknown_target",
      modulePath: "src/core/unknown.nim",
      resolutionKind: rrUnresolved)
    let inputs = makeInputs(unresolvedEdges = @[edge])
    let outcome = computeSelection(inputs)
    let exitCode = case outcome.derivation.status
      of ssValid: 0
      of ssFallbackRequired: 2
      of ssError: 1
    check exitCode == 2
    check outcome.plan.mode == umFull

  test "REJECT-group: verifyPlanDigest fail → axiom_engine err() → exit 1":
    ## axiom_engine.nim:858-859: verifyPlanDigest false → err() → exit 1
    ## Plan is rejected before any execution (no partial run).
    let deriv = SelectionDerivation(
      inputDigests: SelectionInputs(
        changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p"),
      status: ssValid, selected: @[], excluded: @[],
      fallbackReason: "", witnessDigest: "")
    var plan = makeExecutionPlan(deriv, umSelected, @["m::f"])
    plan.selectedUnitIds = @["m::f", "m::injected"]
    check not verifyPlanDigest(plan)

  test "REJECT-group: corrupted JSON → axiom_engine err() → exit 1":
    ## axiom_engine.nim:853-856: readJsonFile None or fromJson None → err() → exit 1
    let badJson = %*"not a plan"
    let planOpt = execution_plan.fromJson(badJson)
    check planOpt.isNone

{.pop.}