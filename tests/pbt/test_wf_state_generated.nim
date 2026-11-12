{.push raises: [].}
## Algebraic Stateful PBT for wf_state
##
## Generates random action sequences and verifies FSM invariants.
## Emits [PBT-SEED] and [PBT-FAILED] markers for CI seed tracking.

import std/random

# Placeholder: will be connected when wf_state module is available
type
  WfActionKind = enum
    wakInit, wakTransit, wakSuspend, wakTerminate

  WfAction = object
    kind: WfActionKind
    nodeId: string
    reason: int

  WfStateMock = object
    active: bool
    nodeCount: int
    status: string

proc applyAction*(state: var WfStateMock; action: WfAction) =
  case action.kind
  of wakInit:
    state.active = true
    state.status = "active"
  of wakTransit:
    if state.active:
      state.nodeCount += 1
  of wakSuspend:
    state.status = "suspended"
  of wakTerminate:
    state.active = false
    state.nodeCount = 0
    state.status = "terminated"

proc verifyInvariants*(state: WfStateMock): bool =
  if state.status == "terminated":
    return state.nodeCount == 0 and not state.active
  if state.status == "active":
    return state.active
  true

proc generateRandomAction(): WfAction =
  let kind = WfActionKind(rand(0..3))
  WfAction(kind: kind, nodeId: "node_" & $rand(0..99), reason: rand(0..10))

proc runStatefulPbt*(steps: int = 100; seed: int64 = 0) =
  ## Runs stateful PBT with structured marker output for CI seed tracking.
  ## Emits [PBT-SEED] at start and [PBT-FAILED] on invariant violation.
  let effectiveSeed = if seed != 0: seed else: int64(rand(high(int)))
  randomize(effectiveSeed)
  let testName = "wf_state_stateful_pbt"
  echo "[PBT-SEED] seed=", effectiveSeed, " test=", testName

  var state = WfStateMock()
  var trace: seq[WfAction] = @[]
  for _ in 0 ..< steps:
    let action = generateRandomAction()
    trace.add(action)
    state.applyAction(action)
    if not state.verifyInvariants():
      echo "[PBT-FAILED] seed=", effectiveSeed, " test=", testName
      echo "❌ Invariant violation at step ", trace.len
      echo "  Action: ", action
      echo "  State: ", state
      doAssert false, "Stateful PBT failed"

when isMainModule:
  echo "Running Algebraic Stateful PBT..."
  runStatefulPbt(1000)
  echo "✅ 1000 steps passed"
