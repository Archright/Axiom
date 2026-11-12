import std/unittest
import std/tables
import core/sorter/sorter_core

suite "deduplicateStrings contract":
  test "removes duplicates preserving order":
    let expected: seq[string] = @["a", "b", "c"]
    check deduplicateStrings(@["a", "b", "a", "c", "b"]) == expected

  test "empty seq returns empty":
    let expected: seq[string] = @[]
    check deduplicateStrings(@[]) == expected

  test "all unique returns unchanged":
    let expected: seq[string] = @["a", "b", "c"]
    check deduplicateStrings(@["a", "b", "c"]) == expected

suite "nodeIdEquals contract":
  test "same id returns true":
    check nodeIdEquals(sorterNodeId("a"), sorterNodeId("a"))

  test "different id returns false":
    check not nodeIdEquals(sorterNodeId("a"), sorterNodeId("b"))

suite "containsNodeId contract":
  test "finds existing node":
    let nodes = @[sorterNodeId("a"), sorterNodeId("b")]
    check containsNodeId(nodes, sorterNodeId("b"))

  test "returns false for missing node":
    let nodes = @[sorterNodeId("a")]
    check not containsNodeId(nodes, sorterNodeId("z"))

suite "findNodeIndex contract":
  test "returns index for existing node":
    let state = initSorterState(@[makeSorterNode("m", "a", sorterNodeId("a"), @[]), makeSorterNode("m", "b", sorterNodeId("b"), @[])])
    check findNodeIndex(state, sorterNodeId("b")) == 1

  test "returns -1 for missing node":
    let state = initSorterState(@[makeSorterNode("m", "a", sorterNodeId("a"), @[])])
    check findNodeIndex(state, sorterNodeId("z")) == -1

suite "buildNodeIndexTable contract":
  test "maps node id to index":
    let state = initSorterState(@[makeSorterNode("m", "a", sorterNodeId("a"), @[]), makeSorterNode("m", "b", sorterNodeId("b"), @[])])
    let table = buildNodeIndexTable(state)
    check table["b"] == 1

suite "deduplicateNodeIds contract":
  test "removes duplicate node ids":
    let ids = @[sorterNodeId("a"), sorterNodeId("b"), sorterNodeId("a")]
    let result = deduplicateNodeIds(ids)
    check result.len == 2
    check nodeIdEquals(result[0], sorterNodeId("a"))
    check nodeIdEquals(result[1], sorterNodeId("b"))

  test "empty seq returns empty":
    let ids: seq[SorterNodeId] = @[]
    check deduplicateNodeIds(ids).len == 0

suite "verifyWorkflowLabelFromNode contract":
  test "returns label for resident node":
    let node = makeSorterNode("m", "fn", sorterNodeId("a"), @[])
    check verifyWorkflowLabelFromNode(node).len > 0

suite "buildDependentsGraph contract (Phase 10)":
  test "no dependencies returns empty graph":
    let state = initSorterState(@[
      makeSorterNode("m", "a", sorterNodeId("a"), @[]),
      makeSorterNode("m", "b", sorterNodeId("b"), @[])
    ])
    let graph = buildDependentsGraph(state)
    check graph.len == 0

  test "linear chain: a -> b -> c":
    let state = initSorterState(@[
      makeSorterNode("m", "a", sorterNodeId("a"), @[]),
      makeSorterNode("m", "b", sorterNodeId("b"), @[sorterNodeId("a")]),
      makeSorterNode("m", "c", sorterNodeId("c"), @[sorterNodeId("b")])
    ])
    let graph = buildDependentsGraph(state)
    check graph.hasKey("a")
    check graph["a"].len == 1
    check graph["a"][0] == "b"
    check graph.hasKey("b")
    check graph["b"].len == 1
    check graph["b"][0] == "c"
    check not graph.hasKey("c")

  test "diamond: a -> b, a -> c, b -> d, c -> d":
    let state = initSorterState(@[
      makeSorterNode("m", "a", sorterNodeId("a"), @[]),
      makeSorterNode("m", "b", sorterNodeId("b"), @[sorterNodeId("a")]),
      makeSorterNode("m", "c", sorterNodeId("c"), @[sorterNodeId("a")]),
      makeSorterNode("m", "d", sorterNodeId("d"), @[sorterNodeId("b"), sorterNodeId("c")])
    ])
    let graph = buildDependentsGraph(state)
    check graph["a"].len == 2
    check graph["b"].len == 1
    check graph["c"].len == 1
    check not graph.hasKey("d")

suite "cascadeStaleDependents contract (Phase 10)":
  test "single node, no dependents":
    var state = initSorterState(@[
      makeSorterNode("m", "a", sorterNodeId("a"), @[])
    ])
    cascadeStaleDependents(state, sorterNodeId("a"))
    check state.nodes[0].isStale

  test "linear chain cascade: a stale -> b stale -> c stale":
    var state = initSorterState(@[
      makeSorterNode("m", "a", sorterNodeId("a"), @[]),
      makeSorterNode("m", "b", sorterNodeId("b"), @[sorterNodeId("a")]),
      makeSorterNode("m", "c", sorterNodeId("c"), @[sorterNodeId("b")])
    ])
    cascadeStaleDependents(state, sorterNodeId("a"))
    check state.nodes[0].isStale
    check state.nodes[1].isStale
    check state.nodes[2].isStale

  test "partial cascade: only dependent subtree invalidated":
    var state = initSorterState(@[
      makeSorterNode("m", "a", sorterNodeId("a"), @[]),
      makeSorterNode("m", "b", sorterNodeId("b"), @[sorterNodeId("a")]),
      makeSorterNode("m", "c", sorterNodeId("c"), @[])  # c has no deps
      # mark c as not stale initially
    ])
    state.nodes[2].isStale = false
    cascadeStaleDependents(state, sorterNodeId("a"))
    check state.nodes[0].isStale  # a is root of cascade
    check state.nodes[1].isStale  # b depends on a
    check not state.nodes[2].isStale  # c is independent — unaffected

  test "diamond cascade: a stale -> b,c,d all stale":
    var state = initSorterState(@[
      makeSorterNode("m", "a", sorterNodeId("a"), @[]),
      makeSorterNode("m", "b", sorterNodeId("b"), @[sorterNodeId("a")]),
      makeSorterNode("m", "c", sorterNodeId("c"), @[sorterNodeId("a")]),
      makeSorterNode("m", "d", sorterNodeId("d"), @[sorterNodeId("b"), sorterNodeId("c")])
    ])
    cascadeStaleDependents(state, sorterNodeId("a"))
    check state.nodes[0].isStale
    check state.nodes[1].isStale
    check state.nodes[2].isStale
    check state.nodes[3].isStale

  test "no-op on already-stale graph":
    var state = initSorterState(@[
      makeSorterNode("m", "a", sorterNodeId("a"), @[]),
      makeSorterNode("m", "b", sorterNodeId("b"), @[sorterNodeId("a")])
    ])
    state.nodes[0].isStale = true
    state.nodes[1].isStale = true
    cascadeStaleDependents(state, sorterNodeId("a"))
    check state.nodes[0].isStale
    check state.nodes[1].isStale
