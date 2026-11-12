import std/unittest
import std/tables
import std/os
import core/symbolic/global_symbol_graph_types
import core/symbol_graph/global_symbol_graph_query
import core/symbol_graph/global_symbol_graph_builder_part1
import core/symbol_graph/global_symbol_graph_builder_part2

suite "countSourceFunctions physical guard":
  test "counts only proc and func symbols, excludes types and vars":
    var graph = GlobalSymbolGraph()
    graph.symbols["a::foo"] = SymbolNode(
      qualifiedName: "a::foo",
      kind: skProc,
      modulePath: "a.nim"
    )
    graph.symbols["a::bar"] = SymbolNode(
      qualifiedName: "a::bar",
      kind: skFunc,
      modulePath: "a.nim"
    )
    graph.symbols["a::T"] = SymbolNode(
      qualifiedName: "a::T",
      kind: skType,
      modulePath: "a.nim"
    )
    graph.symbols["a::x"] = SymbolNode(
      qualifiedName: "a::x",
      kind: skVar,
      modulePath: "a.nim"
    )
    check countSourceFunctions(graph) == 2

  test "returns 0 for empty graph":
    var graph = GlobalSymbolGraph()
    check countSourceFunctions(graph) == 0

  test "incremental cache round-trip preserves symbols and edges":
    var entries = initTable[string, ModuleGraphContribution]()
    entries["a.nim"] = ModuleGraphContribution(
      fileHash: "abc123",
      symbols: @[
        SymbolNode(qualifiedName: "a::foo", kind: skProc, modulePath: "a.nim", visibility: "public"),
        SymbolNode(qualifiedName: "a::bar", kind: skFunc, modulePath: "a.nim", visibility: "public")
      ],
      edges: @[
        ReferenceEdge(source: "a::foo", target: "a::bar", kind: rkCall, line: 1, column: 0)
      ]
    )
    let cachePath = getTempDir() / "axiom_gsg_test_cache.json"
    saveIncrementalGraphCache(cachePath, entries)
    let loaded = loadIncrementalGraphCache(cachePath)
    check loaded.len == 1
    check loaded.hasKey("a.nim")
    check loaded["a.nim"].fileHash == "abc123"
    check loaded["a.nim"].symbols.len == 2
    check loaded["a.nim"].edges.len == 1

  test "canonical graph ordering is stable":
    var graph = GlobalSymbolGraph(
      symbols: initTable[string, SymbolNode](),
      edges: @[],
      byTarget: initTable[string, seq[ReferenceEdge]]()
    )
    graph.symbols["b::bar"] = SymbolNode(qualifiedName: "b::bar", kind: skFunc, modulePath: "b.nim")
    graph.symbols["a::foo"] = SymbolNode(qualifiedName: "a::foo", kind: skProc, modulePath: "a.nim")
    graph.edges.add(ReferenceEdge(source: "b::bar", target: "a::foo", kind: rkCall, line: 2, column: 1))
    graph.edges.add(ReferenceEdge(source: "a::foo", target: "b::bar", kind: rkCall, line: 1, column: 1))

    canonicalizeGlobalSymbolGraph(graph)

    check graph.edges[0].source == "a::foo"
    check graph.edges[1].source == "b::bar"
    check graph.byTarget["b::bar"][0].source == "a::foo"
