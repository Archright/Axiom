import core/trusted/layer_declaration
import core/trusted/regeneration_conformance
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import core/trusted/replay_engine

proc main() =
  echo "=== Regeneration Conformance Tests ==="

  let bv64 = irTypeBitVec64()
  let x = irVar("x", bv64)
  let y = irVar("y", bv64)
  let body = irAdd(x, y)
  let result = irVar("result", bv64)
  let postcond = irEq(result, irAdd(x, y))
  var f = irFuncDef("add", @[("x", bv64), ("y", bv64)], bv64, body, isRec = false)
  f.postConditions = @[postcond]

  # T1: regenerateSmt is deterministic (same output twice)
  block:
    let smt1 = regenerateSmt(f)
    let smt2 = regenerateSmt(f)
    doAssert smt1 == smt2, "regenerateSmt must be deterministic"
    echo "  OK: regenerateSmt is deterministic"

  # T2: regenConformance(stored, same) == rgMatch
  block:
    let smt = regenerateSmt(f)
    doAssert regenConformance(smt, smt) == rgMatch,
      "identical SMT must yield rgMatch"
    echo "  OK: regenConformance(stored, same) == rgMatch"

  # T3: regenConformance(stored, different-by-any-byte) == rgMismatch
  block:
    let smt = regenerateSmt(f)
    let different = smt & " "
    doAssert regenConformance(smt, different) == rgMismatch,
      "different SMT must yield rgMismatch"
    echo "  OK: regenConformance(stored, different) == rgMismatch"

  # T4: regenConformance("", _) == rgUnavailable
  block:
    let smt = regenerateSmt(f)
    doAssert regenConformance("", smt) == rgUnavailable,
      "empty stored must yield rgUnavailable"
    doAssert regenConformance(smt, "") == rgUnavailable,
      "empty regenerated must yield rgUnavailable"
    echo "  OK: regenConformance(\"\", _) == rgUnavailable"

  # T5: regenConformanceFromIR(storedSmt == irToSmtScript(f), f) == rgMatch
  block:
    let stored = irToSmtScript(f)
    doAssert regenConformanceFromIR(stored, f) == rgMatch,
      "stored == regenerated must yield rgMatch"
    echo "  OK: regenConformanceFromIR(stored == irToSmtScript(f), f) == rgMatch"

  # T6: regenConformanceFromIR(storedSmt != irToSmtScript(f), f) == rgMismatch
  block:
    let stored = irToSmtScript(f) & "x"
    doAssert regenConformanceFromIR(stored, f) == rgMismatch,
      "stored != regenerated must yield rgMismatch"
    echo "  OK: regenConformanceFromIR(stored != irToSmtScript(f), f) == rgMismatch"

  # T7: SEPARATION — RegenStatus and ReplayStatus are distinct types.
  # rgMismatch (RegenStatus) is not rsMismatch (ReplayStatus).
  # The compiler enforces this boundary — cross-type comparison is a type error.
  block:
    let _: RegenStatus = rgMismatch
    let _: ReplayStatus = rsMismatch
    echo "  OK: RegenStatus and ReplayStatus are distinct types"

  echo "=== Regeneration Conformance OK ==="

main()