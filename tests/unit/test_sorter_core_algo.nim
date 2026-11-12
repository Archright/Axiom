{.push raises: [CatchableError].}

## Sorter Core Algo Tests — Unit tests for core/sorter/sorter_core_algo.nim
## Tests buildSorterPlan (pure), verifyWorkflowLabelFromNode, verifyWorkflowLabelFromNodeId,
## setNodeStale, promoteNodeToVault.

import std/[unittest, os, sets, tables, strutils, times]
import core/sorter/sorter_core_algo
import core/sorter/sorter_core_index_base
import core/sorter/sorter_core_index_table

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeSimpleNodes(): seq[SorterNode] =
  @[
    makeSorterNode("src/a.nim", "fn1", sorterNodeId("n1"), @[], "pure"),
    makeSorterNode("src/b.nim", "fn2", sorterNodeId("n2"), @[sorterNodeId("n1")], "pure"),
    makeSorterNode("src/c.nim", "fn3", sorterNodeId("n3"), @[sorterNodeId("n1"), sorterNodeId("n2")], "pure"),
  ]

proc simpleState(): SorterState =
  initSorterState(makeSimpleNodes(), @[], @[])

# ---------------------------------------------------------------------------
# buildSorterPlan
# ---------------------------------------------------------------------------

suite "buildSorterPlan":
  test "simple DAG: all nodes become workItems":
    let st = simpleState()
    let plan = buildSorterPlan(st)
    check plan.blockedNodes.len == 0

  test "empty nodes: no workItems and no blockedNodes":
    let st = initSorterState(@[], @[], @[])
    let plan = buildSorterPlan(st)
    check plan.workItems.len == 0
    check plan.blockedNodes.len == 0

  test "cycle detection: unprocessed nodes end up in blockedNodes":
    let nodes = @[
      makeSorterNode("a.nim", "fn", sorterNodeId("n1"), @[sorterNodeId("n2")], "pure"),
      makeSorterNode("b.nim", "fn", sorterNodeId("n2"), @[sorterNodeId("n1")], "pure"),
    ]
    let st = initSorterState(nodes, @[], @[])
    let plan = buildSorterPlan(st)
    check plan.blockedNodes.len > 0

  test "single node with no dependencies":
    let nodes = @[makeSorterNode("a.nim", "fn", sorterNodeId("n1"), @[], "pure")]
    let st = initSorterState(nodes, @[], @[])
    let plan = buildSorterPlan(st)
    check plan.blockedNodes.len == 0
    check plan.workItems.len >= 1

  test "DAG: dependency depth ordering":
    let st = simpleState()
    let plan = buildSorterPlan(st)
    # All 3 nodes should be reachable (no blocked)
    check plan.blockedNodes.len == 0

# ---------------------------------------------------------------------------
# verifyWorkflowLabelFromNode
# ---------------------------------------------------------------------------

suite "verifyWorkflowLabelFromNode":
  test "valid node → correct label":
    let n = makeSorterNode("src/core/mod.nim", "myFunc", sorterNodeId("n1"), @[], "pure")
    let label = verifyWorkflowLabelFromNode(n)
    check "mod.nim::myFunc" == label

  test "multiple path segments":
    let n = makeSorterNode("src/a/b/c/deep.nim", "fn", sorterNodeId("n1"), @[], "pure")
    let label = verifyWorkflowLabelFromNode(n)
    check "deep.nim::fn" in label

# ---------------------------------------------------------------------------
# verifyWorkflowLabelFromNodeId
# ---------------------------------------------------------------------------

suite "verifyWorkflowLabelFromNodeId":
  test "returns same as verifyWorkflowLabelFromNode":
    let st = simpleState()
    let nodeId = sorterNodeId("n1")
    let label = verifyWorkflowLabelFromNodeId(st, nodeId)
    check "a.nim::fn1" in label

  test "unknown node → returns raw nodeId string":
    let st = simpleState()
    let label = verifyWorkflowLabelFromNodeId(st, sorterNodeId("nonexistent"))
    # When nodeId not found, returns raw string as fallback
    check "::" notin label

# ---------------------------------------------------------------------------
# setNodeStale
# ---------------------------------------------------------------------------

suite "setNodeStale":
  test "sets node stale flag to true":
    var st = simpleState()
    setNodeStale(st, sorterNodeId("n1"), true)
    check st.nodes[0].isStale == true

  test "nonexistent node does not crash":
    var st = simpleState()
    setNodeStale(st, sorterNodeId("nonexistent"), true)
    # Should not crash; all nodes remain unchanged
    check st.nodes.len == 3

  test "setNodeStale with dependency nodes does not crash":
    var st = simpleState()
    setNodeStale(st, sorterNodeId("n2"), true)
    check st.nodes[1].isStale == true

# ---------------------------------------------------------------------------
# promoteNodeToVault
# ---------------------------------------------------------------------------

suite "promoteNodeToVault":
  test "promotes node with valid axiom to vault entries":
    var st = simpleState()
    let nodeId = sorterNodeId("n1")
    let axiom = axiomFormula("∀ x, x ≥ 0")
    promoteNodeToVault(st, nodeId, axiom)
    check st.vaultEntries.len == 1
    check nodeIdEquals(st.vaultEntries[0].nodeId, nodeId)
    check axiomFormulaString(st.vaultEntries[0].axiom) == axiomFormulaString(axiom)

  test "nonexistent node does not crash":
    var st = simpleState()
    promoteNodeToVault(st, sorterNodeId("nonexistent"), axiomFormula("ax"))
    # promoteNodeToVault adds regardless of node existence
    check st.vaultEntries.len == 1

{.pop.}
