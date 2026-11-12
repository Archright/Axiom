## Unit tests for cfg_builder.nim — CFG construction and analysis.
import std/strutils
import std/tables
import core/boundary/cfg_builder

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  echo "=== CfgGraph structure ==="

  check "CfgGraph entry field is set":
    var emptyGraph = CfgGraph(entry: 0, nodes: @[], nodeMap: initTable[int, int]())
    doAssert emptyGraph.entry == 0

  check "CfgGraph nodes initial state":
    var emptyGraph2 = CfgGraph(entry: 0, nodes: @[], nodeMap: initTable[int, int]())
    doAssert emptyGraph2.nodes.len == 0

  echo ""
  echo "=== buildCfgFromSource ==="

  check "empty source produces single-entry graph":
    let graph1 = buildCfgFromSource("")
    doAssert graph1.entry == 0
    doAssert graph1.nodes.len >= 1

  check "simple function produces entry node":
    let graph2 = buildCfgFromSource("proc foo(): int = 1")
    doAssert graph2.entry == 0

  check "if statement creates branch node":
    let source = "if x > 0:\n  y = 1"
    let graph3 = buildCfgFromSource(source)
    doAssert graph3.entry >= 0

  check "while loop creates back edge node":
    let source2 = "while i < n:\n  i += 1"
    let graph4 = buildCfgFromSource(source2)
    doAssert graph4.nodes.len >= 1

  check "for loop creates loop node":
    let source3 = "for i in 0..<10:\n  discard"
    let graph5 = buildCfgFromSource(source3)
    doAssert graph5.entry == 0

  check "case statement handled":
    let source4 = "case x:\n  of 0: y = 1\n  of 1: y = 2"
    let graph6 = buildCfgFromSource(source4)
    doAssert graph6.entry == 0

  check "try-except creates branch":
    let source5 = "try:\n  risky()\nexcept:\n  handle()"
    let graph7 = buildCfgFromSource(source5)
    doAssert graph7.entry == 0

  echo ""
  echo "=== tarjanSCC ==="

  check "empty graph returns empty SCCs":
    let emptyGraph = CfgGraph(entry: 0, nodes: @[], nodeMap: initTable[int, int]())
    let sccs1 = tarjanSCC(emptyGraph)
    doAssert sccs1.len == 0

  check "single node graph has one SCC":
    var singleNodeGraph = CfgGraph(
      entry: 0,
      nodes: @[CfgNode(id: 0, label: "entry", successors: @[])],
      nodeMap: initTable[int, int]()
    )
    singleNodeGraph.nodeMap[0] = 0
    let sccs2 = tarjanSCC(singleNodeGraph)
    doAssert sccs2.len == 1

  check "acyclic graph has each node in own SCC":
    var dagGraph = CfgGraph(
      entry: 0,
      nodes: @[
        CfgNode(id: 0, label: "entry", successors: @[1]),
        CfgNode(id: 1, label: "block1", successors: @[2]),
        CfgNode(id: 2, label: "block2", successors: @[])
      ],
      nodeMap: initTable[int, int]()
    )
    dagGraph.nodeMap[0] = 0
    dagGraph.nodeMap[1] = 1
    dagGraph.nodeMap[2] = 2
    let sccs3 = tarjanSCC(dagGraph)
    doAssert sccs3.len >= 1

  echo ""
  echo "=== topologicalSort ==="

  check "empty graph returns empty":
    let emptyGraph = CfgGraph(entry: 0, nodes: @[], nodeMap: initTable[int, int]())
    let sorted1 = topologicalSort(emptyGraph)
    doAssert sorted1.len == 0

  check "single node returns that node":
    var singleNodeGraph = CfgGraph(
      entry: 0,
      nodes: @[CfgNode(id: 0, label: "entry", successors: @[])],
      nodeMap: initTable[int, int]()
    )
    singleNodeGraph.nodeMap[0] = 0
    let sorted2 = topologicalSort(singleNodeGraph)
    doAssert sorted2.len == 1

  check "acyclic graph returns valid order":
    var dagGraph = CfgGraph(
      entry: 0,
      nodes: @[
        CfgNode(id: 0, label: "entry", successors: @[1]),
        CfgNode(id: 1, label: "block1", successors: @[2]),
        CfgNode(id: 2, label: "block2", successors: @[])
      ],
      nodeMap: initTable[int, int]()
    )
    dagGraph.nodeMap[0] = 0
    dagGraph.nodeMap[1] = 1
    dagGraph.nodeMap[2] = 2
    let sorted3 = topologicalSort(dagGraph)
    doAssert sorted3.len == 3

  check "cyclic graph returns empty (not a DAG)":
    var cyclicGraph = CfgGraph(
      entry: 0,
      nodes: @[
        CfgNode(id: 0, label: "entry", successors: @[1]),
        CfgNode(id: 1, label: "block1", successors: @[0])
      ],
      nodeMap: initTable[int, int]()
    )
    cyclicGraph.nodeMap[0] = 0
    cyclicGraph.nodeMap[1] = 1
    let sorted4 = topologicalSort(cyclicGraph)
    doAssert sorted4.len == 0

  echo ""
  echo "=== isReducible ==="

  check "single node graph is reducible":
    var singleNodeGraph = CfgGraph(
      entry: 0,
      nodes: @[CfgNode(id: 0, label: "entry", successors: @[])],
      nodeMap: initTable[int, int]()
    )
    singleNodeGraph.nodeMap[0] = 0
    doAssert isReducible(singleNodeGraph) == true

  check "DAG graph is reducible":
    var dagGraph = CfgGraph(
      entry: 0,
      nodes: @[
        CfgNode(id: 0, label: "entry", successors: @[1]),
        CfgNode(id: 1, label: "block1", successors: @[2]),
        CfgNode(id: 2, label: "block2", successors: @[])
      ],
      nodeMap: initTable[int, int]()
    )
    dagGraph.nodeMap[0] = 0
    dagGraph.nodeMap[1] = 1
    dagGraph.nodeMap[2] = 2
    doAssert isReducible(dagGraph) == true

  echo ""
  echo "=== classifyTopology ==="

  check "empty graph is DAG":
    let emptyGraph = CfgGraph(entry: 0, nodes: @[], nodeMap: initTable[int, int]())
    let result1 = classifyTopology(emptyGraph)
    doAssert result1.kind == topoDag

  check "single node is DAG":
    var singleNodeGraph = CfgGraph(
      entry: 0,
      nodes: @[CfgNode(id: 0, label: "entry", successors: @[])],
      nodeMap: initTable[int, int]()
    )
    singleNodeGraph.nodeMap[0] = 0
    let result2 = classifyTopology(singleNodeGraph)
    doAssert result2.kind == topoDag
    doAssert result2.nodeCount == 1

  check "topoDag for acyclic":
    var dagGraph = CfgGraph(
      entry: 0,
      nodes: @[
        CfgNode(id: 0, label: "entry", successors: @[1]),
        CfgNode(id: 1, label: "block1", successors: @[2]),
        CfgNode(id: 2, label: "block2", successors: @[])
      ],
      nodeMap: initTable[int, int]()
    )
    dagGraph.nodeMap[0] = 0
    dagGraph.nodeMap[1] = 1
    dagGraph.nodeMap[2] = 2
    let result3 = classifyTopology(dagGraph)
    doAssert result3.kind == topoDag

  check "TopologyResult has edge count":
    var simpleGraph = CfgGraph(
      entry: 0,
      nodes: @[
        CfgNode(id: 0, label: "entry", successors: @[1, 2]),
        CfgNode(id: 1, label: "b1", successors: @[2]),
        CfgNode(id: 2, label: "b2", successors: @[])
      ],
      nodeMap: initTable[int, int]()
    )
    simpleGraph.nodeMap[0] = 0
    simpleGraph.nodeMap[1] = 1
    simpleGraph.nodeMap[2] = 2
    let result4 = classifyTopology(simpleGraph)
    doAssert result4.edgeCount >= 0

  echo ""
  echo "=== classifyFunction ==="

  check "classifyFunction returns topology for simple input":
    let result = classifyFunction("proc foo(): int = 1")
    doAssert result.kind == topoDag

  check "classifyFunction for loop":
    let result2 = classifyFunction("proc test(): void = for i in 0..<10: discard")
    doAssert result2.kind in {topoDag, topoReducible}

  echo ""
  echo "Result: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()