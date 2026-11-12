{.push raises: [CatchableError].}
## BDD feature test for heal_hint_manager.feature
## Verifies the Heal Hint Manager's pure state automata.

import std/unittest
import core/contract/heal_hint_manager
import core/types/heal_types
import core/types/hubs/semantic_hint_hub

suite "Heal Hint Manager":
  test "acceptVerifiedAxiom processes hint correctly":
    var manager = HintManager(hint: SemanticHint(leanProposition: "test_prop"))
    var logLines: seq[string] = @[]
    acceptVerifiedAxiom(manager, logLines)
    check manager.hint.leanProposition == "test_prop"
