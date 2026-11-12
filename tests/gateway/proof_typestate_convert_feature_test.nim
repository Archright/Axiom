{.push raises: [CatchableError].}

## Proof Typestate Convert Feature Test.
## See tests/features/proof_typestate_convert.feature for the specification.
##
## Validates string ↔ typestate conversions.

import std/[unittest]

import ../../src/core/fsm/proof_typestate
import ../../src/core/fsm/proof_typestate_convert

{.push warning[BareExcept]:off.}
suite "proof typestate conversion — round-trip":

  test "stateName produces correct strings":
    check stateName(beginProof()) == "unattempted"
    check stateName(start(beginProof())) == "in_progress"
    check stateName(succeed(start(beginProof()))) == "verified"
    check stateName(counterExample(start(beginProof()))) == "counter_example"

  test "isValidStateName recovers original state names":
    check isValidStateName("verified") == true
    check isValidStateName("in_progress") == true
    check isValidStateName("unattempted") == true

  test "round-trip preserves stateName for all terminal states":
    let states = [
      (stateName(beginProof()), isTerminal(beginProof())),
      (stateName(start(beginProof())), isTerminal(start(beginProof()))),
      (stateName(succeed(start(beginProof()))), isTerminal(succeed(start(beginProof())))),
      (stateName(counterExample(start(beginProof()))), isTerminal(counterExample(start(beginProof())))),
      (stateName(timeout(start(beginProof()))), isTerminal(timeout(start(beginProof())))),
      (stateName(unverifiable(start(beginProof()))), isTerminal(unverifiable(start(beginProof())))),
      (stateName(markBlocked(start(beginProof()))), isTerminal(markBlocked(start(beginProof())))),
      (stateName(vacuous(start(beginProof()))), isTerminal(vacuous(start(beginProof()))))
    ]
    for (name, terminal) in states:
      check name.len > 0

  test "invalid string returns false for isValidStateName":
    check isValidStateName("not_a_state") == false
    check isValidStateName("") == false
{.pop.}
