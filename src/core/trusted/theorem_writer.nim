import core/trusted/layer_declaration
axiomLayer "trusted.core.theorem-writer"

{.push raises: [].}

import core/trusted/axiom_ir

type TacticKind* = enum
  tkOmega
  tkBvDecide
  tkSimp
  tkNlinarith
  tkAesop
  tkSorry

type PostConditionClassifier* = object
  needsMathlib*: bool
  tactic*: TacticKind

const defaultTactic*: TacticKind =
  when defined(allowSorry): tkSorry
  else: tkAesop

func containsNonLinearMul(e: IRExpr): bool =
  if e == nil: return false
  case e.kind
  of irBinOp:
    if e.binOp == boMul and e.binLhs.kind == irVar and e.binRhs.kind == irVar:
      return true
    result = containsNonLinearMul(e.binLhs) or containsNonLinearMul(e.binRhs)
  of irUnaryOp:
    result = containsNonLinearMul(e.unaryArg)
  of irLet:
    result = containsNonLinearMul(e.letVal) or containsNonLinearMul(e.letBody)
  of irIf:
    result = containsNonLinearMul(e.ifCond) or containsNonLinearMul(e.ifThen) or containsNonLinearMul(e.ifElse)
  of irCase:
    if containsNonLinearMul(e.caseScrutinee): return true
    for br in e.caseBranches:
      if containsNonLinearMul(br.body): return true
    if e.caseDefault != nil and containsNonLinearMul(e.caseDefault): return true
    result = false
  of irCall:
    for a in e.callArgs:
      if containsNonLinearMul(a): return true
    result = false
  of irRecCall:
    for a in e.recArgs:
      if containsNonLinearMul(a): return true
    result = false
  of irLoop:
    for init in e.loopInits:
      if containsNonLinearMul(init): return true
    if containsNonLinearMul(e.loopCond): return true
    if e.loopStep != nil and containsNonLinearMul(e.loopStep): return true
    if containsNonLinearMul(e.loopBody): return true
    for inv in e.loopInvariants:
      if containsNonLinearMul(inv): return true
    if e.loopVariant != nil and containsNonLinearMul(e.loopVariant): return true
    result = false
  of irCast:
    result = containsNonLinearMul(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    result = false

func containsBitwiseOp(e: IRExpr): bool =
  if e == nil: return false
  case e.kind
  of irUnaryOp:
    if e.unaryOp in {uoBvNot, uoBvNeg}:
      return true
    result = containsBitwiseOp(e.unaryArg)
  of irBinOp:
    result = containsBitwiseOp(e.binLhs) or containsBitwiseOp(e.binRhs)
  of irLet:
    result = containsBitwiseOp(e.letVal) or containsBitwiseOp(e.letBody)
  of irIf:
    result = containsBitwiseOp(e.ifCond) or containsBitwiseOp(e.ifThen) or containsBitwiseOp(e.ifElse)
  of irCase:
    if containsBitwiseOp(e.caseScrutinee): return true
    for br in e.caseBranches:
      if containsBitwiseOp(br.body): return true
    if e.caseDefault != nil and containsBitwiseOp(e.caseDefault): return true
    result = false
  of irCall:
    for a in e.callArgs:
      if containsBitwiseOp(a): return true
    result = false
  of irRecCall:
    for a in e.recArgs:
      if containsBitwiseOp(a): return true
    result = false
  of irLoop:
    for init in e.loopInits:
      if containsBitwiseOp(init): return true
    if containsBitwiseOp(e.loopCond): return true
    if e.loopStep != nil and containsBitwiseOp(e.loopStep): return true
    if containsBitwiseOp(e.loopBody): return true
    for inv in e.loopInvariants:
      if containsBitwiseOp(inv): return true
    if e.loopVariant != nil and containsBitwiseOp(e.loopVariant): return true
    result = false
  of irCast:
    result = containsBitwiseOp(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    result = false

func containsBooleanOp(e: IRExpr): bool =
  if e == nil: return false
  case e.kind
  of irBinOp:
    if e.binOp in {boAnd, boOr}:
      return true
    result = containsBooleanOp(e.binLhs) or containsBooleanOp(e.binRhs)
  of irUnaryOp:
    if e.unaryOp == uoNot:
      return true
    result = containsBooleanOp(e.unaryArg)
  of irLet:
    result = containsBooleanOp(e.letVal) or containsBooleanOp(e.letBody)
  of irIf:
    result = containsBooleanOp(e.ifCond) or containsBooleanOp(e.ifThen) or containsBooleanOp(e.ifElse)
  of irCase:
    if containsBooleanOp(e.caseScrutinee): return true
    for br in e.caseBranches:
      if containsBooleanOp(br.body): return true
    if e.caseDefault != nil and containsBooleanOp(e.caseDefault): return true
    result = false
  of irCall:
    for a in e.callArgs:
      if containsBooleanOp(a): return true
    result = false
  of irRecCall:
    for a in e.recArgs:
      if containsBooleanOp(a): return true
    result = false
  of irLoop:
    for init in e.loopInits:
      if containsBooleanOp(init): return true
    if containsBooleanOp(e.loopCond): return true
    if e.loopStep != nil and containsBooleanOp(e.loopStep): return true
    if containsBooleanOp(e.loopBody): return true
    for inv in e.loopInvariants:
      if containsBooleanOp(inv): return true
    if e.loopVariant != nil and containsBooleanOp(e.loopVariant): return true
    result = false
  of irCast:
    result = containsBooleanOp(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    result = false

func containsEqualityOp(e: IRExpr): bool =
  if e == nil: return false
  case e.kind
  of irBinOp:
    if e.binOp == boEq:
      return true
    result = containsEqualityOp(e.binLhs) or containsEqualityOp(e.binRhs)
  of irUnaryOp:
    result = containsEqualityOp(e.unaryArg)
  of irLet:
    result = containsEqualityOp(e.letVal) or containsEqualityOp(e.letBody)
  of irIf:
    result = containsEqualityOp(e.ifCond) or containsEqualityOp(e.ifThen) or containsEqualityOp(e.ifElse)
  of irCase:
    if containsEqualityOp(e.caseScrutinee): return true
    for br in e.caseBranches:
      if containsEqualityOp(br.body): return true
    if e.caseDefault != nil and containsEqualityOp(e.caseDefault): return true
    result = false
  of irCall:
    for a in e.callArgs:
      if containsEqualityOp(a): return true
    result = false
  of irRecCall:
    for a in e.recArgs:
      if containsEqualityOp(a): return true
    result = false
  of irLoop:
    for init in e.loopInits:
      if containsEqualityOp(init): return true
    if containsEqualityOp(e.loopCond): return true
    if e.loopStep != nil and containsEqualityOp(e.loopStep): return true
    if containsEqualityOp(e.loopBody): return true
    for inv in e.loopInvariants:
      if containsEqualityOp(inv): return true
    if e.loopVariant != nil and containsEqualityOp(e.loopVariant): return true
    result = false
  of irCast:
    result = containsEqualityOp(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    result = false

func isLinearOrScalarMulExpr(e: IRExpr): bool =
  if e == nil: return true
  case e.kind
  of irBinOp:
    if e.binOp in {boAdd, boSub, boLt, boLe, boGt, boGe, boEq}:
      result = isLinearOrScalarMulExpr(e.binLhs) and isLinearOrScalarMulExpr(e.binRhs)
    elif e.binOp == boMul:
      if e.binLhs.kind == irLit or e.binRhs.kind == irLit:
        result = isLinearOrScalarMulExpr(e.binLhs) and isLinearOrScalarMulExpr(e.binRhs)
      else:
        result = false
    else:
      result = false
  of irUnaryOp:
    result = false
  of irLet:
    result = isLinearOrScalarMulExpr(e.letVal) and isLinearOrScalarMulExpr(e.letBody)
  of irIf:
    result = isLinearOrScalarMulExpr(e.ifCond) and isLinearOrScalarMulExpr(e.ifThen) and isLinearOrScalarMulExpr(e.ifElse)
  of irCase:
    if not isLinearOrScalarMulExpr(e.caseScrutinee): return false
    for br in e.caseBranches:
      if not isLinearOrScalarMulExpr(br.body): return false
    if e.caseDefault != nil and not isLinearOrScalarMulExpr(e.caseDefault): return false
    result = true
  of irCall:
    for a in e.callArgs:
      if not isLinearOrScalarMulExpr(a): return false
    result = true
  of irRecCall:
    for a in e.recArgs:
      if not isLinearOrScalarMulExpr(a): return false
    result = true
  of irLoop:
    for init in e.loopInits:
      if not isLinearOrScalarMulExpr(init): return false
    if not isLinearOrScalarMulExpr(e.loopCond): return false
    if e.loopStep != nil and not isLinearOrScalarMulExpr(e.loopStep): return false
    if not isLinearOrScalarMulExpr(e.loopBody): return false
    for inv in e.loopInvariants:
      if not isLinearOrScalarMulExpr(inv): return false
    if e.loopVariant != nil and not isLinearOrScalarMulExpr(e.loopVariant): return false
    result = true
  of irCast:
    result = isLinearOrScalarMulExpr(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    result = true

func isBitVecRangeExpr(e: IRExpr): bool =
  ## True when `e` is a pure BitVec relational range: only boolean connectives
  ## (boAnd/boOr/uoNot) and comparisons (boLt/boLe/boGt/boGe/boEq) over
  ## irVar/irLit leaves, with NO arithmetic (mul/div/rem/add/sub), no float,
  ## no unary bitwise ops, and no calls. This is exactly the shape of a
  ## synthesized clamp-range postcondition (e.g. result ≥ lo ∧ result ≤ hi).
  ## bv_decide bitblasts BitVec directly, so these route to it rather than
  ## omega (which would need ℕ/ℤ casts on the raw BitVec).
  if e == nil: return false
  case e.kind
  of irLit, irVar:
    true
  of irUnaryOp:
    e.unaryOp == uoNot and isBitVecRangeExpr(e.unaryArg)
  of irBinOp:
    if e.binOp in {boAnd, boOr, boLt, boLe, boGt, boGe, boEq}:
      isBitVecRangeExpr(e.binLhs) and isBitVecRangeExpr(e.binRhs)
    else:
      false
  of irLet:
    isBitVecRangeExpr(e.letVal) and isBitVecRangeExpr(e.letBody)
  of irIf:
    isBitVecRangeExpr(e.ifCond) and isBitVecRangeExpr(e.ifThen) and
      isBitVecRangeExpr(e.ifElse)
  else:
    false

func classifyPostCondition*(e: IRExpr): PostConditionClassifier {.raises: [].} =
  if containsNonLinearMul(e):
    return PostConditionClassifier(needsMathlib: true, tactic: tkNlinarith)
  if containsBitwiseOp(e):
    return PostConditionClassifier(needsMathlib: false, tactic: tkBvDecide)
  if containsBooleanOp(e) and containsEqualityOp(e):
    return PostConditionClassifier(needsMathlib: false, tactic: tkSimp)
  if isBitVecRangeExpr(e):
    # Pure BitVec range (e.g. result ≥ lo ∧ result ≤ hi): bitblast with
    # bv_decide, which handles raw BitVec 64 (omega would need .toNat casts).
    return PostConditionClassifier(needsMathlib: false, tactic: tkBvDecide)
  if isLinearOrScalarMulExpr(e):
    return PostConditionClassifier(needsMathlib: false, tactic: tkOmega)
  return PostConditionClassifier(needsMathlib: false, tactic: defaultTactic)

func selectTactic*(classifier: PostConditionClassifier, enableMathlib: bool): TacticKind {.raises: [].} =
  when defined(allowSorry):
    if classifier.needsMathlib and not enableMathlib:
      return tkSorry
    classifier.tactic
  else:
    if classifier.needsMathlib and not enableMathlib:
      return tkAesop
    classifier.tactic

func tacticToLeanString*(t: TacticKind): string {.raises: [].} =
  case t
  of tkOmega: "omega"
  of tkBvDecide: "bv_decide"
  of tkSimp: "simp"
  of tkNlinarith: "nlinarith"
  of tkAesop: "aesop"
  of tkSorry: "sorry"

func collectRequiredImports*(tactics: seq[TacticKind]): seq[string] {.raises: [].} =
  var seenBvDecide, seenNlinarith, seenAesop: bool
  for t in tactics:
    case t
    of tkBvDecide: seenBvDecide = true
    of tkNlinarith: seenNlinarith = true
    of tkAesop: seenAesop = true
    else: discard
  if seenBvDecide:
    result.add("import Std.Tactic.BVDecide")
  if seenNlinarith:
    result.add("import Mathlib.Tactic.Linarith")
  if seenAesop:
    result.add("import Aesop")

{.pop.}
