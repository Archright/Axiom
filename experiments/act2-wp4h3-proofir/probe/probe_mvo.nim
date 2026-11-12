import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import verification/obligation/obligation_types
import verification/obligation/obligation_ir

proc main() =
  let p = irNot(irEq(irVar("x", irTypeBitVec64()), irLit(0)))
  # control 1: sibling exported proc `computeId` from obligation_ir
  let ctl = VerificationObligation(
    id: "", kind: okSafetyDiv, subject: "s", assumptions: "",
    proposition: p, predicate: canonicalizePredicate(p),
    derivationRule: "d", provenance: "p")
  echo "ctl computeId len=", ctl.computeId().len
  # control 2: exported producer
  let o = makeVerificationObligation(okSafetyDiv, "s", "", "d", "p", p)
  echo "o pred=", o.predicate

main()
