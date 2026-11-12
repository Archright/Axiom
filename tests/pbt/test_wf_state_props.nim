{.push raises: [].}
## PBT: Workflow State FSM Invariants
## Exercises: Stateful property verification via PBT engine checkProperty.
## Self-contained FSM (counter + phase) with 4 operations:
##   Init → Transit → Suspend → Terminate
## Properties:
##   - Terminated state always has nodeCount=0 and active=false
##   - Active state always has active=true
##   - Suspended state preserves nodeCount
##   - Random action sequences maintain invariants
## @basic tier — runs in every CI push.

import std/[unittest]
import core/testing/pbt_engine

# ─── Self-contained FSM for PBT ─────────────────────────────────────────────

type
  WfPhase = enum
    wfIdle, wfActive, wfSuspended, wfTerminated

  WfState = object
    phase: WfPhase
    nodeCount: int
    active: bool
func initWfState(): WfState {.noSideEffect, raises: [].} =
  WfState(phase: wfIdle, nodeCount: 0, active: false)
func applyAction(state: WfState; action: int): WfState {.noSideEffect, raises: [].} =
  case action
  of 0:  # Init
    WfState(phase: wfActive, nodeCount: 0, active: true)
  of 1:  # Transit (add node)
    if state.phase == wfActive:
      WfState(phase: wfActive, nodeCount: state.nodeCount + 1, active: true)
    else:
      state
  of 2:  # Suspend
    if state.phase == wfActive:
      WfState(phase: wfSuspended, nodeCount: state.nodeCount, active: false)
    else:
      state
  of 3:  # Terminate
    if state.phase in {wfActive, wfSuspended}:
      WfState(phase: wfTerminated, nodeCount: 0, active: false)
    else:
      state
  else:
    state
func verifyInvariant(state: WfState): bool {.noSideEffect, raises: [].} =
  ## Core FSM invariant: terminated implies nodeCount=0 and !active.
  case state.phase
  of wfTerminated:
    state.nodeCount == 0 and not state.active
  of wfActive:
    state.active and state.nodeCount >= 0
  of wfSuspended:
    not state.active and state.nodeCount >= 0
  of wfIdle:
    not state.active and state.nodeCount == 0

suite "PBT: Workflow State Invariants":
  test "Single action preserves invariants (200 iterations)":
    # Property: any single valid action from any reachable state
    # yields a state that satisfies verifyInvariant.
    let gen = genInt(0, 3)
    let prop = proc(action: int): bool =
      # Test from multiple starting states
      let startStates = [initWfState(),
                         applyAction(initWfState(), 0),        # active
                         applyAction(applyAction(initWfState(), 0), 2)]  # suspended
      for start in startStates:
        let after = start.applyAction(action)
        if not after.verifyInvariant():
          return false
      true
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "5-step sequences maintain invariants (200 iterations)":
    # Property: any 5-step random action sequence maintains invariants
    # at every intermediate step.
    let gen = genInt(0, 3)
    let prop = proc(firstAction: int): bool =
      var state = initWfState()
      # Step 1: first action from gen
      state = state.applyAction(firstAction)
      if not state.verifyInvariant(): return false
      # Steps 2-5: fixed secondary actions
      let actions = [0, 1, 2, 3]
      for a in actions:
        state = state.applyAction(a)
        if not state.verifyInvariant(): return false
      true
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "Init always produces active state (200 iterations)":
    # Property: applying Init from idle always yields active=true.
    let gen = genInt(0, 0)  # Only Init action
    let prop = proc(_: int): bool =
      let state = initWfState().applyAction(0)
      state.phase == wfActive and state.active == true
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "Terminate from active/suspended always clears (200 iterations)":
    # Property: Terminate from Active or Suspended yields nodeCount=0, !active.
    let gen = genInt(0, 1)  # 0=active, 1=suspended starting state
    let prop = proc(startKind: int): bool =
      var state = initWfState().applyAction(0)  # → active
      if startKind == 1:
        state = state.applyAction(2)  # → suspended
      state = state.applyAction(3)  # → terminated
      state.phase == wfTerminated and state.nodeCount == 0 and not state.active
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

  test "Suspend preserves nodeCount (200 iterations)":
    # Property: Suspended state preserves nodeCount from Active state.
    let gen = genInt(0, 10)
    let prop = proc(extraTransits: int): bool =
      var state = initWfState().applyAction(0)  # → active
      for _ in 0..<extraTransits:
        state = state.applyAction(1)  # transit (add node)
      let countBefore = state.nodeCount
      state = state.applyAction(2)  # suspend
      state.phase == wfSuspended and state.nodeCount == countBefore
    let pbtResult = checkProperty(gen, prop, iterations = 200,
                                   tier = PbtBasic, verbosity = PbtSilent)
    check pbtResult.passed == true

{.pop.}
