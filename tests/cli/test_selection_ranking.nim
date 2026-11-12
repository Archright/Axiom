{.push raises: [].}

## Unit tests for deterministic ranking-based node selection.
## Tests pure computation functions — no I/O required.

import std/json
import std/unittest
import std/tables

import cli/selection_state

suite "Selection State — computeScore":
  test "score monotonicity: less-selected nodes get higher score":
    check computeScore(0) > computeScore(1)
    check computeScore(1) > computeScore(5)
    check computeScore(5) > computeScore(100)

  test "score at count=0 is 1.0":
    check computeScore(0) == 1.0

  test "score at count=1 is 0.5":
    check computeScore(1) == 0.5

  test "score decreases asymptotically":
    let s10 = computeScore(10)
    let s100 = computeScore(100)
    check s10 > 0.0
    check s100 > 0.0
    check s10 > s100

suite "Selection State — incrementCount":
  test "increments from zero":
    var state = emptyState()
    incrementCount(state, @["nodeA", "nodeB"])
    check state.counts["nodeA"] == 1
    check state.counts["nodeB"] == 1

  test "increments existing counts":
    var state = emptyState()
    incrementCount(state, @["nodeA"])
    incrementCount(state, @["nodeA", "nodeB"])
    check state.counts["nodeA"] == 2
    check state.counts["nodeB"] == 1

  test "empty list is no-op":
    var state = emptyState()
    incrementCount(state, @[])
    check state.counts.len == 0

suite "Selection State — recordAsi":
  test "appends ASI values":
    var state = emptyState()
    recordAsi(state, 0.1972)
    recordAsi(state, 0.1972)
    recordAsi(state, 0.2500)
    check state.asiHistory.len == 3
    check state.asiHistory[2] == 0.2500

  test "respects maxHistory limit":
    var state = emptyState()
    for i in 0 .. 25:
      recordAsi(state, i.float, maxHistory = 20)
    check state.asiHistory.len == 20

suite "Selection State — isStalled":
  test "not stalled with fewer than threshold entries":
    var state = emptyState()
    recordAsi(state, 0.1972)
    recordAsi(state, 0.1972)
    check isStalled(state, threshold = 3) == false

  test "stalled when last N values are identical":
    var state = emptyState()
    recordAsi(state, 0.1972)
    recordAsi(state, 0.1972)
    recordAsi(state, 0.1972)
    check isStalled(state, threshold = 3) == true

  test "not stalled when values differ":
    var state = emptyState()
    recordAsi(state, 0.1972)
    recordAsi(state, 0.1972)
    recordAsi(state, 0.2500)
    check isStalled(state, threshold = 3) == false

  test "stalled with larger threshold":
    var state = emptyState()
    for i in 0 .. 5:
      recordAsi(state, 0.5)
    check isStalled(state, threshold = 5) == true

suite "Selection State — JSON round-trip":
  test "stateToJson and stateFromJson preserve data":
    var state = emptyState()
    state.counts["nodeA"] = 3
    state.counts["nodeB"] = 1
    state.lastRunTimestamp = "2026-06-24T12:00:00Z"
    recordAsi(state, 0.1972)
    recordAsi(state, 0.2500)

    let json = stateToJson(state)
    let restored = stateFromJson(json)

    check restored.counts["nodeA"] == 3
    check restored.counts["nodeB"] == 1
    check restored.asiHistory.len == 2
    check restored.lastRunTimestamp == "2026-06-24T12:00:00Z"

  test "stateFromJson handles empty/malformed input":
    let restored = stateFromJson(parseJson("null"))
    check restored.counts.len == 0
    check restored.asiHistory.len == 0

suite "Selection State — emptyState":
  test "empty state has no counts":
    let state = emptyState()
    check state.counts.len == 0
    check state.asiHistory.len == 0
    check state.lastRunTimestamp.len == 0

{.pop.}
