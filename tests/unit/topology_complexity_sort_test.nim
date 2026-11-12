import std/[sequtils, unittest]

import core/topology/topology_engine
import core/topology/topology_types

proc makeMetric(
  name: string;
  interfaceDistance: int;
  complexityScore: int;
  topologyScore: int;
  couplingScore: int = 0
): TopologyNodeMetric =
  TopologyNodeMetric(
    nodeId: sorterNodeId(name),
    interfaceDistance: interfaceDistance,
    complexityScore: complexityScore,
    topologyScore: topologyScore,
    couplingScore: couplingScore,
    dependencyCount: 0,
    dependentCount: 0,
    transitiveDependentCount: 0,
    centralityScore: 0,
    branchCount: 0,
    nestingDepth: 0,
    lineSpan: 0,
    logicalDepth: 0,
    semanticWeight: 0.0
  )

proc checkOrder(metrics: seq[TopologyNodeMetric]; expectedNames: seq[string]) =
  let order = sortMetricIndices(metrics)
  let names = order.mapIt(sorterNodeIdString(metrics[it].nodeId))
  check names == expectedNames

suite "Topology complexityScore ascending tiebreaker":
  test "same interfaceDistance: lower complexityScore sorts first":
    let metrics = @[
      makeMetric("high", 1, complexityScore = 9, topologyScore = 1),
      makeMetric("low", 1, complexityScore = 2, topologyScore = 5),
      makeMetric("mid", 1, complexityScore = 5, topologyScore = 3)
    ]
    checkOrder(metrics, @["low", "mid", "high"])

  test "same complexityScore: higher topologyScore sorts first (legacy priority preserved)":
    let metrics = @[
      makeMetric("a", 1, complexityScore = 4, topologyScore = 1),
      makeMetric("b", 1, complexityScore = 4, topologyScore = 9),
      makeMetric("c", 1, complexityScore = 4, topologyScore = 4)
    ]
    checkOrder(metrics, @["b", "c", "a"])

  test "different interfaceDistance: reachable/interfaceDistance precedes complexityScore":
    let metrics = @[
      makeMetric("far", 5, complexityScore = 1, topologyScore = 9),
      makeMetric("near", 1, complexityScore = 9, topologyScore = 1),
      makeMetric("mid", 3, complexityScore = 4, topologyScore = 4)
    ]
    checkOrder(metrics, @["near", "mid", "far"])

  test "reachability: reachable nodes precede unreachable regardless of complexityScore":
    let metrics = @[
      makeMetric("unreachable", 100, complexityScore = 1, topologyScore = 9),
      makeMetric("reachable", 1, complexityScore = 9, topologyScore = 1),
      makeMetric("unreachable2", 100, complexityScore = 2, topologyScore = 8)
    ]
    checkOrder(metrics, @["reachable", "unreachable", "unreachable2"])

  test "tie on all priority fields: nodeId lexicographic fallback":
    let metrics = @[
      makeMetric("zeta", 1, complexityScore = 2, topologyScore = 3),
      makeMetric("alpha", 1, complexityScore = 2, topologyScore = 3)
    ]
    checkOrder(metrics, @["alpha", "zeta"])
