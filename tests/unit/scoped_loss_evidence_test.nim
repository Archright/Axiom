## scoped_loss_evidence_test.nim
##
## Translation evidence for the binding channel: what the translator can now say
## about a LEXICAL REGION instead of about a whole function.
##
## Before this slice `IrContext.lossySeen` was one bit per function, so a loss in
## an unreachable statement made a faithful binding region look unfaithful. The
## translator now separates two losses that mean opposite things to a caller:
##
##   * an expression-level loss — a construct this IR cannot spell, replaced by a
##     placeholder. The surrounding structure survives; only the leaf is wrong.
##   * a region drop — a statement form with no translation arm. The subtree is
##     never traversed, so a binding inside it is ABSENT rather than marked lossy.
##
## The second is why name uniqueness alone cannot detect shadowing: `let x = 1;
## block: let x = 2` reaches the IR with the inner binding deleted, so the
## surviving `x` looks unique. Each fixture below is shaped to separate the two.
##
## The fixtures run through the same pipeline the external-subject census uses —
## parseStringAST → pnodeToCanon → axiomBodyCanon — and not through `quote do`
## blocks: `PNode` and `NimNode` are separate type hierarchies in Nim 2.2.10
## (docs/spec/pnode_nimnode_type_separation_quirk.md), so a macro-produced tree
## cannot be fed to pnodeToCanon.
##
## Run: nim c -r --hints:off --warnings:off --nimcache:/tmp/scopedloss \
##          tests/unit/scoped_loss_evidence_test.nim

import std/strutils
import compiler/ast
import core/parser_utils
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/ast_to_ir
import core/trusted/pnode_to_canon

proc findProcDef(root: PNode; name: string): PNode =
  ## First `proc`/`func` named `name`, including the `*` export postfix form.
  if root.isNil: return nil
  if root.kind == nkProcDef and root.len > 0:
    let head = root[0]
    if head.kind == nkIdent and head.ident.s == name: return root
    if head.kind == nkPostfix and head.len > 1 and head[1].kind == nkIdent and
       head[1].ident.s == name:
      return root
  for i in 0 ..< root.len:
    let found = findProcDef(root[i], name)
    if not found.isNil: return found
  nil

proc evidenceReport(fd: IRFuncDef): string =
  ## translationLossFree | propositionRegionLossFree | lossOutsideBindingRegions
  ## | name:lossFree:anchor per recorded binding, in translator order.
  var parts: seq[string] = @[]
  for b in fd.recordedBindings:
    parts.add(b.name & ":" & $b.lossFree & ":" & b.anchor)
  $fd.translationLossFree & "|" & $fd.propositionRegionLossFree & "|" &
    $fd.lossOutsideBindingRegions & "|" & parts.join(",")

proc report(name, source: string): string =
  let ast = parseStringAST(source)
  let node = findProcDef(ast, name)
  if node.isNil: return "NOTFOUND"
  evidenceReport(axiomBodyCanon(pnodeToCanon(node)))

proc irOf(name, source: string): IRFuncDef =
  axiomBodyCanon(pnodeToCanon(findProcDef(parseStringAST(source), name)))

const
  # A body expression containing a layout intrinsic this IR cannot spell. The
  # loss is real and function-wide, and it is in neither a binding region nor a
  # guard. (Parenthesized operands translate faithfully since the ckPar arm,
  # so the unspellable operand here is `sizeof`.)
  LossOutsideSource = """
proc probeOutside(n: int): int =
  let
    first = n
    shifted = n - 1
  result = first * 8 - sizeof(int8) - shifted
"""

  # The same loss, moved into a binding's defining expression.
  LossInsideSource = """
proc probeInside(n: int): int =
  let shifted = sizeof(n)
  result = shifted
"""

  # `block:` has no case arm, so the statement — and every binding inside it — is
  # dropped rather than translated. The outer `x` survives and its defining
  # expression converted cleanly: exactly the shape that makes a name-uniqueness
  # check alone unsafe.
  RegionDropSource = """
proc probeDrop(y: int): int =
  let x = 1
  block:
    let x = 2
    discard x
  result = x div y
"""

  # A lossy operand inside a guard. The condition decides which branch an
  # obligation is derived under, so a fabricated guard is a fabricated premise.
  # (`sizeof` marks the loss while the guard region is open, so it lands in the
  # guard channel.)
  GuardLossSource = """
proc probeGuard(y: int): int =
  let x = y
  if sizeof(x) != 0:
    return x div y
  result = 0
"""

  ControlSource = """
proc probeControl(y: int): int =
  let x = y
  result = x div y
"""

proc main() =
  var passed = 0
  var failed = 0

  ## Non-aborting: every check runs and is reported, so one failure never hides
  ## the state of the others.
  template check(name: string, cond: untyped) =
    block:
      if (cond):
        inc passed
        echo "  PASS: " & name
      else:
        inc failed
        echo "  FAIL: " & name

  echo "=== 1. loss outside every certified region ==="
  block:
    let r = report("probeOutside", LossOutsideSource).split('|')
    check "function-level translation is lossy (the placeholder is real)",
      r[0] == "false"
    check "the certified regions are still declared clean",
      r[1] == "true"
    check "the loss is reported as outside the binding/guard regions",
      r[2] == "true"
    check "all bindings recorded, each loss-free, anchored by statement position",
      r[3] == "first:true:stmt[0]/let,shifted:true:stmt[0]/let"

  echo ""
  echo "=== 2. loss inside a binding's defining expression ==="
  block:
    let r = report("probeInside", LossInsideSource).split('|')
    check "function-level translation is lossy",
      r[0] == "false"
    check "no guard was dropped, so the proposition-region claim is untouched",
      r[1] == "true"
    check "the loss is NOT reported as outside the regions — it is inside one",
      r[2] == "false"
    check "the binding is recorded as lossy, not silently omitted",
      r[3] == "shifted:false:stmt[0]/let"

  echo ""
  echo "=== 3. a dropped statement region is not an expression loss ==="
  block:
    let r = report("probeDrop", RegionDropSource).split('|')
    check "function-level translation is lossy",
      r[0] == "false"
    check "the proposition-region claim is FALSE — this is the shadowing trap",
      r[1] == "false"
    check "not reported as outside the regions: the drop is inside the claim",
      r[2] == "false"
    check "the surviving outer binding is recorded once and looks unique",
      r[3] == "x:true:stmt[0]/let"

  echo ""
  echo "=== 4. a lossy guard is a guard-region loss ==="
  block:
    let r = report("probeGuard", GuardLossSource).split('|')
    check "function-level translation is lossy",
      r[0] == "false"
    check "the proposition-region claim is FALSE — the premise was fabricated",
      r[1] == "false"
    check "the binding itself is faithful and recorded as such",
      r[3] == "x:true:stmt[0]/let"

  echo ""
  echo "=== 5. control: nothing lost anywhere ==="
  block:
    let r = report("probeControl", ControlSource).split('|')
    check "translation is loss-free", r[0] == "true"
    check "regions certified clean", r[1] == "true"
    check "no coverage caveat", r[2] == "false"
    check "binding recorded loss-free", r[3] == "x:true:stmt[0]/let"

  echo ""
  echo "=== 6. IR identity does not move with the evidence ==="
  block:
    let base = irOf("probeControl", ControlSource)
    var mutated = base
    mutated.recordedBindings = @[IRBinding(name: "invented", value: irLit(7),
                                          anchor: "stmt[9]/let",
                                          isCompileTime: true, lossFree: false)]
    mutated.propositionRegionLossFree = false
    mutated.lossOutsideBindingRegions = true
    mutated.translationLossFree = false
    mutated.bindingUniverseComplete = true

    check "canonical serialization is unchanged by the evidence fields",
      serializeIRFuncDef(base) == serializeIRFuncDef(mutated)
    check "IR digest is unchanged by the evidence fields",
      computeIrDigest(base) == computeIrDigest(mutated)
    check "the mutated fixture really does carry a binding",
      mutated.recordedBindings.len == 1
    check "the base fixture carries the translator's own binding",
      base.recordedBindings.len == 1

  echo ""
  echo "=== 7. hand-built IR carries no observation ==="
  block:
    var hand = irFuncDef("hand", @[("x", irTypeBitVec64())], irTypeBitVec64(),
                         irDiv(irVar("x", irTypeBitVec64()),
                               irVar("x", irTypeBitVec64())), false)
    check "a hand-built funcDef has no recorded bindings", hand.recordedBindings.len == 0
    check "and does not claim its regions were certified",
      not hand.propositionRegionLossFree
    check "and does not claim incomplete coverage", not hand.lossOutsideBindingRegions

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)
  echo "ALL CHECKS PASSED"

main()