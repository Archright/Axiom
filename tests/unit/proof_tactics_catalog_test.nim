import std/unittest
import core/proof/proof_tactics_catalog

suite "proof tactics catalog contract":
  test "defaultVerifiedTactics returns intros;rfl":
    let tactics = defaultVerifiedTactics()
    check tactics.len == 2
    check tactics[0] == "intros"
    check tactics[1] == "rfl"

  test "deterministicTacticPatterns contains 6 patterns":
    check deterministicTacticPatterns.len == 6

  test "equality_identity pattern has correct tactics":
    let p = deterministicTacticPatterns[0]
    check p.name == "equality_identity"
    check p.tactics == @["intros", "rfl"]
    check p.applicableGoals == @["equality", "identity", "reflexivity"]

  test "auto_aesop pattern has correct tactics":
    let p = deterministicTacticPatterns[^1]
    check p.name == "auto_aesop"
    check p.tactics == @["intros", "aesop"]
    check p.applicableGoals == @["auto", "general"]
