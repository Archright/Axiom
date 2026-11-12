## tests/unit/test_kernel_completeness_inventory.nim
## Phase 1A — kernel completeness REAL source↔IR binding-inventory
## correspondence measurement (no derived flags, no count-only equality).
##
## Covers (each named for the failure mode it pins):
##   - corresponding source↔IR multisets + no opaque boundary → complete.
##   - MISSING binding (source binds a name the IR lost) → NOT complete.
##   - EXTRA binding (IR binds a name the source does not) → NOT complete.
##   - MISMATCH (same total count, different names) → NOT complete — count
##     equality alone is never correspondence.
##   - opaque construct observed → NOT complete, status measured from the
##     inventory ("opaque-boundary-present").
##   - unmeasurable inventory (none) → NOT complete with the honest
##     "source-inventory-unmeasured" status (fail-closed, never fabricated).
##   - counts measured from each side independently (not params+bindings
##     twice).
##
## Run: nim c --hints:off --path:src -o:tmp/test_kernel_completeness_inventory -r tests/unit/test_kernel_completeness_inventory.nim

import std/[options, strutils]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/semantic_fact_types
import core/trusted/binding_inventory
import infrastructure/external_ir_materializer
import verification/batch_uap/ir_pipeline_runner

proc witness(name: string; opaque = false): BindingWitness =
  BindingWitness(scopePath: "func[f]", bindingKind: "let",
    localOccurrence: 0, name: name, lineHint: 1, opaque: opaque)

proc inventory(names: seq[string]; opaqueKinds: seq[string] = @[]): BindingInventory =
  for n in names:
    result.witnesses.add(witness(n))
  for k in opaqueKinds:
    result.opaqueBoundaries.add("opaque:" & k)

proc irFuncDef(body: IRExpr; paramNames: varargs[string]): IRFuncDef =
  var params: seq[IRFuncParam] = @[]
  for p in paramNames:
    params.add(IRFuncParam(name: p, ty: irTypeBitVec64()))
  IRFuncDef(name: "subjectFn", params: params, retType: irTypeBitVec64(),
    body: body, isRecursive: false)

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()
      except Defect:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # IR: one param + one compile-time let binding `n`.
  let bodyLet = irLet("n", irLit(32), irVar("n", irTypeBitVec64()),
    isCompileTime = true)
  let fd = irFuncDef(bodyLet, "p")
  let irNames = irBindingNames(fd)
  doAssert irNames.len == 2  # p (param) + n (let)

  echo "=== corresponding universe ==="
  check "corresponding source↔IR multisets + no opaque → complete":
    let e = measuredKernelCompletenessEvidence(true, fd,
      some(inventory(@["p", "n"])))
    doAssert e.bindingUniverseComplete
    doAssert e.translationLossFree
    doAssert e.opaqueExpansionStatus == "none"
    doAssert e.sourceBindingCount == 2
    doAssert e.irBindingCount == 2

  check "EA disagreement fails the universe closed even with correspondence":
    let e = measuredKernelCompletenessEvidence(false, fd,
      some(inventory(@["p", "n"])))
    doAssert not e.bindingUniverseComplete

  echo "=== missing binding (source has it, IR lost it) ==="
  check "source binds a name the IR lost → NOT complete":
    let e = measuredKernelCompletenessEvidence(true, fd,
      some(inventory(@["p", "n", "lostByIr"])))
    doAssert not e.bindingUniverseComplete
    doAssert e.sourceBindingCount == 3
    doAssert e.irBindingCount == 2
    doAssert e.opaqueExpansionStatus == "none"

  echo "=== extra binding (IR has it, source does not) ==="
  check "IR binds a name the source does not → NOT complete":
    let e = measuredKernelCompletenessEvidence(true, fd,
      some(inventory(@["p"])))
    doAssert not e.bindingUniverseComplete
    doAssert e.sourceBindingCount == 1
    doAssert e.irBindingCount == 2

  echo "=== mismatch (count equality without name equality) ==="
  check "same total count, different names → NOT complete":
    # 2 vs 2 — the derived count-only comparison of the old implementation
    # would pass this; the bidirectional multiset must refuse it.
    let e = measuredKernelCompletenessEvidence(true, fd,
      some(inventory(@["q", "r"])))
    doAssert not e.bindingUniverseComplete
    doAssert e.sourceBindingCount == e.irBindingCount

  echo "=== opaque constructs measured from the inventory ==="
  check "opaque boundary observed → NOT complete, status recorded":
    let e = measuredKernelCompletenessEvidence(true, fd,
      some(inventory(@["p", "n"], @["WhenStmt"])))
    doAssert not e.bindingUniverseComplete
    doAssert e.opaqueExpansionStatus == "opaque-boundary-present"

  echo "=== unmeasurable inventory (fail-closed) ==="
  check "none inventory → NOT complete with honest unmeasured status":
    let e = measuredKernelCompletenessEvidence(true, fd,
      none(BindingInventory))
    doAssert not e.bindingUniverseComplete
    doAssert e.opaqueExpansionStatus == "source-inventory-unmeasured"
    doAssert e.sourceBindingCount == 0
    doAssert e.irBindingCount == irNames.len

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
