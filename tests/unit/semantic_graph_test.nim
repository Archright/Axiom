import std/unittest
import verification/semantic_graph

suite "SemanticGraph value type":
  test "SemanticGraph is a value type, not ref":
    var graph = buildSemanticGraph("src", graphPath = "logs/global_symbol_graph.json")
    check graph.totalNodes >= 0
    graph.verifiedNodes = 5
    var graph2 = graph
    graph2.verifiedNodes = 10
    check graph.verifiedNodes == 5
    check graph2.verifiedNodes == 10
