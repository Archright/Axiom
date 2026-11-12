{.push raises: [CatchableError].}

## Proof Typestate Feature Test.
## See tests/features/proof_typestate.feature for the specification.
##
## Validates the typestate FSM for proof states.

import std/[unittest]

import ../../src/core/fsm/proof_typestate

{.push warning[BareExcept]:off.}
suite "proof typestate FSM — state transitions":

  test "new proof starts in Unattempted state":
    let state = beginProof()
    check stateName(state) == "unattempted"

  test "start transitions from Unattempted to InProgress":
    let s = start(beginProof())
    check stateName(s) == "in_progress"

  test "succeed transitions from InProgress to Verified":
    let s = succeed(start(beginProof()))
    check stateName(s) == "verified"

  test "counterExample transitions from InProgress":
    let s = counterExample(start(beginProof()))
    check stateName(s) == "counter_example"

  test "timeout transitions from InProgress":
    let s = timeout(start(beginProof()))
    check stateName(s) == "timed_out"

  test "markBlocked transitions from InProgress":
    let s = markBlocked(start(beginProof()))
    check stateName(s) == "blocked"

  test "unverifiable transitions from InProgress":
    let s = unverifiable(start(beginProof()))
    check stateName(s) == "unverifiable"

  test "isTerminal returns true for Verified":
    check isTerminal(succeed(start(beginProof()))) == true

  test "isTerminal returns true for CounterEx":
    check isTerminal(counterExample(start(beginProof()))) == true

  test "isTerminal returns false for InProgress":
    check isTerminal(start(beginProof())) == false
{.pop.}
