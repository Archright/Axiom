## Unit test for frontier target selection ordering fix.
##
## Regression test for the ordering bug where --target filter operated
## on the post-eligibility, post-limit frontier, causing targeted
## symbols to be lost when --limit selected a different node first
## and the eligibility gate then removed that node.
##
## The fix: --target now applies BEFORE automatic frontier filtering
## (eligibility gate + limit), while eligibility is still enforced as
## a final guard.
##
## Oracle design:
## Each test case verifies that selectFrontierNodes returns the
## expected frontier after applying --target filter, eligibility gate,
## and limit in the correct order.

import std/[unittest, tables, strutils]
import core/sorter/sorter_core
import cli/frontier_selection

suite "Frontier target selection ordering":

  # -----------------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------------

  func makeNode(id: string): SorterNodeId =
    sorterNodeId(id)

  func makeNodeFnIdx(pairs: varargs[string]): Table[string, string] =
    ## Build a nodeFnIdx from alternating (id, fnName) pairs.
    result = initTable[string, string]()
    for i in countup(0, pairs.len - 1, 2):
      result[pairs[i]] = pairs[i + 1]

  # -----------------------------------------------------------------------
  # Test 1: --target finds node in pre-eligibility frontier even when
  #         --limit would have excluded it from automatic selection
  # -----------------------------------------------------------------------

  test "--target finds eligible target in pre-eligibility frontier when limit=1 would select non-eligible node first":
    ## Scenario: frontier = [nonEligibleNode, targetNode], limit=1
    ## Bug: limit=1 selects nonEligibleNode first, eligibility gate
    ##      removes it, frontier becomes empty, target filter finds nothing.
    ## Fix: --target searches pre-eligibility frontier, finds targetNode,
    ##      then eligibility gate confirms targetNode is eligible.
    let frontier = @[makeNode("nodeA"), makeNode("nodeB")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "otherFunc",   # not in registry → not eligible
      "nodeB", "decodedLength" # in registry → eligible (if registered)
    )
    let target = "decodedLength"
    let frontierLimit = 1

    ## Mock eligibility: decodedLength is eligible, otherFunc is not.
    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      fnName == "decodedLength"

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, initTable[string, string](), frontierLimit, isEligible)

    check result.len == 1
    check sorterNodeIdString(result[0]) == "nodeB"

  # -----------------------------------------------------------------------
  # Test 2: --target with non-eligible target still excludes it
  # -----------------------------------------------------------------------

  test "--target with non-eligible target is excluded by eligibility gate":
    ## Scenario: frontier = [targetNode], limit=1
    ## Target is explicitly specified but is NOT eligible.
    ## Expected: target is excluded by eligibility gate, result is empty.
    let frontier = @[makeNode("nodeA")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "unsupportedFunc"  # not eligible
    )
    let target = "unsupportedFunc"
    let frontierLimit = 1

    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      false  # nothing is eligible

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, initTable[string, string](), frontierLimit, isEligible)

    check result.len == 0

  # -----------------------------------------------------------------------
  # Test 3: no --target preserves existing frontier behavior
  # -----------------------------------------------------------------------

  test "no --target preserves existing frontier behavior (no regression)":
    ## Scenario: frontier = [nodeA, nodeB], no target, limit=1
    ## Expected: eligibility gate filters, then limit is applied.
    let frontier = @[makeNode("nodeA"), makeNode("nodeB")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "eligibleFunc",
      "nodeB", "otherFunc"
    )
    let target = ""
    let frontierLimit = 1

    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      fnName == "eligibleFunc"

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, initTable[string, string](), frontierLimit, isEligible)

    check result.len == 1
    check sorterNodeIdString(result[0]) == "nodeA"

  # -----------------------------------------------------------------------
  # Test 4: --target with multiple matching nodes
  # -----------------------------------------------------------------------

  test "--target matches multiple nodes in pre-eligibility frontier":
    let frontier = @[makeNode("nodeA"), makeNode("nodeB"), makeNode("nodeC")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "decodedLength_v1",
      "nodeB", "decodedLength_v2",
      "nodeC", "otherFunc"
    )
    let target = "decodedLength"
    let frontierLimit = 0  # unlimited

    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      fnName.startsWith("decodedLength")

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, initTable[string, string](), frontierLimit, isEligible)

    check result.len == 2
    check sorterNodeIdString(result[0]) == "nodeA"
    check sorterNodeIdString(result[1]) == "nodeB"

  # -----------------------------------------------------------------------
  # Test 5: --target not found falls back to full frontier
  # -----------------------------------------------------------------------

  test "--target not found falls back to full frontier for eligibility filtering":
    let frontier = @[makeNode("nodeA"), makeNode("nodeB")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "eligibleFunc",
      "nodeB", "otherFunc"
    )
    let target = "nonexistent"
    let frontierLimit = 0

    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      fnName == "eligibleFunc"

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, initTable[string, string](), frontierLimit, isEligible)

    check result.len == 1
    check sorterNodeIdString(result[0]) == "nodeA"

  # -----------------------------------------------------------------------
  # WP4-e: canonical ``module::function`` targets are fail-closed.
  # 0 matches → NotFound (empty selection). >1 matches → Ambiguous
  # (empty selection). Exactly 1 → executed. Legacy bare-name fallback
  # (no ``::``) is preserved as a non-canonical convenience.
  # -----------------------------------------------------------------------

  test "canonical --target 'module::fn' exact match returns the single matching node":
    let frontier = @[makeNode("nodeA"), makeNode("nodeB")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "encode",   # same module
      "nodeB", "encode"
    )
    let nodeModuleIdx = {
      "nodeA": "stew/base36.nim",
      "nodeB": "other/mod.nim"
    }.toTable
    let target = "stew/base36.nim::encode"
    let frontierLimit = 0

    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      true

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, nodeModuleIdx, frontierLimit, isEligible)

    check result.len == 1
    check sorterNodeIdString(result[0]) == "nodeA"

  test "canonical --target 'module::fn' with 0 matches fails closed (empty selection, no full-frontier fallback)":
    let frontier = @[makeNode("nodeA"), makeNode("nodeB")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "encode",
      "nodeB", "other"
    )
    let nodeModuleIdx = {
      "nodeA": "stew/base36.nim",
      "nodeB": "other/mod.nim"
    }.toTable
    let target = "stew/base36.nim::decode"  # module matches, fn does not
    let frontierLimit = 0

    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      true  # everything eligible — a full-frontier fallback would return 2 nodes

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, nodeModuleIdx, frontierLimit, isEligible)

    check result.len == 0

  test "canonical --target 'module::fn' with >1 matches (same module+fn) fails closed (Ambiguous, empty selection)":
    let frontier = @[makeNode("nodeA"), makeNode("nodeB")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "getBitsBE",
      "nodeB", "getBitsBE"
    )
    let nodeModuleIdx = {
      "nodeA": "stew/bitops2.nim",
      "nodeB": "stew/bitops2.nim"
    }.toTable
    let target = "stew/bitops2.nim::getBitsBE"  # two distinct defs share the identity
    let frontierLimit = 0

    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      true

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, nodeModuleIdx, frontierLimit, isEligible)

    check result.len == 0

  test "legacy bare-name --target with 0 matches still falls back to full frontier (non-canonical convenience preserved)":
    let frontier = @[makeNode("nodeA"), makeNode("nodeB")]
    let nodeFnIdx = makeNodeFnIdx(
      "nodeA", "encode",
      "nodeB", "other"
    )
    let nodeModuleIdx = {
      "nodeA": "stew/base36.nim",
      "nodeB": "other/mod.nim"
    }.toTable
    let target = "nonexistent"
    let frontierLimit = 0

    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      true

    let result = selectFrontierNodes(frontier, target, nodeFnIdx, nodeModuleIdx, frontierLimit, isEligible)

    # Legacy bare-name path: nonexistent target → full frontier (2 nodes), eligibility keeps all.
    check result.len == 2
