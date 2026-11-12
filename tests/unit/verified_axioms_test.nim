import std/unittest
import core/verified_axioms/verified_axioms

suite "Anti-Tautology Registry ASI Weights":
  test "trivial axioms have zero ASI weight":
    check getAxiomWeight("nim.string.len.isNat") == 0.0
    check getAxiomWeight("nim.seq.len.isNat") == 0.0

  test "meaningful axioms have full ASI weight":
    check getAxiomWeight("nim.os.readFileOpt.externalIO") == 1.0
    check getAxiomWeight("unknown.custom.axiom") == 1.0

  test "totalVerifiedAxiomWeight is non-negative":
    let w = totalVerifiedAxiomWeight()
    check w >= 0.0
