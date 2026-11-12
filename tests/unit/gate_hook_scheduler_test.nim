## Unit test for gate_hook token scheduler logic
## Extracts pure functions from gate_hook.nim for deterministic verification.

import std/unittest
import core/types/domain_types
import gate/gate_contract

# ---------------------------------------------------------------------------
# Scheduler logic (mirrors scripts/gate_hook.nim)
# ---------------------------------------------------------------------------

proc allocateTokens(gate: GateConfig; available: int): int =
  ## Returns tokens allocated (0 if insufficient).
  let cost = gate.weight.int
  if cost > available:
    return 0
  return cost

proc jobsFromTokens(tokens: int): int =
  ## Map allocated tokens to child maxJobs.
  max(1, tokens)

# ---------------------------------------------------------------------------
# R3: canDispatchAnyQueue — pure scheduler progress predicate
# Mirrors func canDispatchAnyQueue*(readyQueue: seq[GateConfig];
#   availableTokens: int): bool from executor.nim (A2 deadlock fix).
# Extracted as a top-level pure function so the no-spin invariant is
# unit-testable in isolation.
# ---------------------------------------------------------------------------

func canDispatchAnyQueue*(readyQueue: seq[GateConfig]; availableTokens: int): bool =
  var i = readyQueue.len
  while i > 0:
    dec i
    if readyQueue[i].weight.int <= availableTokens:
      return true
  false

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "Token scheduler":

  test "allocateTokens exact fit":
    let g = GateConfig(
      id: "h", name: "Heavy", layer: glFunctional,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwHeavy
    )
    check allocateTokens(g, 4) == 4

  test "allocateTokens insufficient":
    let g = GateConfig(
      id: "h", name: "Heavy", layer: glFunctional,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwHeavy
    )
    check allocateTokens(g, 3) == 0

  test "allocateTokens light gate":
    let g = GateConfig(
      id: "l", name: "Light", layer: glMeta,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwLight
    )
    check allocateTokens(g, 1) == 1

  test "allocateTokens zero available":
    let g = GateConfig(
      id: "l", name: "Light", layer: glMeta,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwLight
    )
    check allocateTokens(g, 0) == 0

  test "jobsFromTokens maps correctly":
    check jobsFromTokens(4) == 4
    check jobsFromTokens(2) == 2
    check jobsFromTokens(1) == 1
    check jobsFromTokens(0) == 1

  test "deterministic dispatch order with budget 8":
    let gates = @[
      GateConfig(
        id: "h1", name: "Heavy1", layer: glFunctional,
        entry: "", stages: {}, filesPattern: "", passFilenames: false,
        weight: gwHeavy
      ),
      GateConfig(
        id: "h2", name: "Heavy2", layer: glFunctional,
        entry: "", stages: {}, filesPattern: "", passFilenames: false,
        weight: gwHeavy
      ),
      GateConfig(
        id: "l1", name: "Light1", layer: glMeta,
        entry: "", stages: {}, filesPattern: "", passFilenames: false,
        weight: gwLight
      ),
    ]
    var available = 8
    var dispatchOrder: seq[string]
    for g in gates:
      let allocated = allocateTokens(g, available)
      if allocated > 0:
        available -= allocated
        dispatchOrder.add(g.id)
    check dispatchOrder == @["h1", "h2"]
    check available == 0

  test "token release allows waiting gate to dispatch":
    var available = 8
    let h1 = GateConfig(
      id: "h1", name: "Heavy1", layer: glFunctional,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwHeavy
    )
    let h2 = GateConfig(
      id: "h2", name: "Heavy2", layer: glFunctional,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwHeavy
    )
    let h3 = GateConfig(
      id: "h3", name: "Heavy3", layer: glFunctional,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwHeavy
    )

    # Dispatch h1 and h2 (consumes all 8 tokens)
    let a1 = allocateTokens(h1, available)
    available -= a1
    let a2 = allocateTokens(h2, available)
    available -= a2
    check a1 == 4
    check a2 == 4
    check available == 0

    # h3 cannot dispatch (0 tokens available)
    let a3 = allocateTokens(h3, available)
    check a3 == 0

    # Simulate h1 completion: release 4 tokens
    available += a1

    # h3 can now dispatch
    let a3After = allocateTokens(h3, available)
    available -= a3After
    check a3After == 4
    check available == 0

# ---------------------------------------------------------------------------
# R3: canDispatchAnyQueue — no-progress deadlock detection
# ---------------------------------------------------------------------------

suite "canDispatchAnyQueue — R3 scheduler progress predicate":

  test "empty queue returns false (no gates to dispatch)":
    check canDispatchAnyQueue(@[], 8) == false

  test "budget zero cannot dispatch any gate":
    let g = GateConfig(
      id: "l", name: "Light", layer: glMeta,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwLight
    )
    check canDispatchAnyQueue(@[g], 0) == false

  test "light gate fits within budget":
    let g = GateConfig(
      id: "l", name: "Light", layer: glMeta,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwLight
    )
    check canDispatchAnyQueue(@[g], 1) == true

  test "heavy gate exceeds budget — deadlock detected":
    let g = GateConfig(
      id: "h", name: "Heavy", layer: glFunctional,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwHeavy
    )
    check canDispatchAnyQueue(@[g], 3) == false

  test "heavy gate exact fit":
    let g = GateConfig(
      id: "h", name: "Heavy", layer: glFunctional,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwHeavy
    )
    check canDispatchAnyQueue(@[g], 4) == true

  test "mixed queue — at least one gate fits budget":
    let gates = @[
      GateConfig(
        id: "h", name: "Heavy", layer: glFunctional,
        entry: "", stages: {}, filesPattern: "", passFilenames: false,
        weight: gwHeavy
      ),
      GateConfig(
        id: "l", name: "Light", layer: glMeta,
        entry: "", stages: {}, filesPattern: "", passFilenames: false,
        weight: gwLight
      ),
    ]
    # budget=3: heavy(4) cannot dispatch, light(1) can → true
    check canDispatchAnyQueue(gates, 3) == true

  test "mixed queue — all gates exceed budget (deadlock)":
    let gates = @[
      GateConfig(
        id: "h1", name: "Heavy1", layer: glFunctional,
        entry: "", stages: {}, filesPattern: "", passFilenames: false,
        weight: gwHeavy
      ),
      GateConfig(
        id: "h2", name: "Heavy2", layer: glFunctional,
        entry: "", stages: {}, filesPattern: "", passFilenames: false,
        weight: gwHeavy
      ),
    ]
    # budget=3: heavy(4) cannot dispatch → false
    check canDispatchAnyQueue(gates, 3) == false

  test "medium gate fits within budget":
    let g = GateConfig(
      id: "m", name: "Medium", layer: glMeta,
      entry: "", stages: {}, filesPattern: "", passFilenames: false,
      weight: gwMedium
    )
    check canDispatchAnyQueue(@[g], 2) == true
    check canDispatchAnyQueue(@[g], 1) == false
