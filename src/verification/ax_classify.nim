import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/trusted/axiom_ir
import std/options

type
  VerificationTier* = enum
    vtSmtNative    ## Tier 1: int/bitvec/bool → Z3 BMC + Lean replay
    vtStructural   ## Tier 2: complex structures → LLM invariant + dual-solving
    vtNonDecidable ## Tier 3: float/string/external → PBT / isolation

  TierClassification* = object
    tier*: VerificationTier
    reason*: string
    isBmcSkippable*: bool
    loopBound*: Option[int]  ## Static upper bound for tier-2 loops (Some iff all
                             ## loops in the body have a resolved bound <= 10).

func hasStringType*(ty: IRType): bool {.raises: [].} =
  if ty == nil: return false
  ty.kind == irtString

func hasListType*(ty: IRType): bool {.raises: [].} =
  if ty == nil: return false
  ty.kind == irtList

func bodyContainsListType*(e: IRExpr): bool {.raises: [].} =
  if e == nil: return false
  case e.kind
  of irCall:
    if e.callName in ["len", "[]", "add", "del"]:
      for a in e.callArgs:
        if a != nil and a.typ != nil and a.typ.kind == irtList:
          return true
    for a in e.callArgs:
      if bodyContainsListType(a): return true
  of irBinOp:
    result = bodyContainsListType(e.binLhs) or bodyContainsListType(e.binRhs)
  of irUnaryOp:
    result = bodyContainsListType(e.unaryArg)
  of irLet:
    result = bodyContainsListType(e.letVal) or bodyContainsListType(e.letBody)
  of irIf:
    result = bodyContainsListType(e.ifCond) or bodyContainsListType(e.ifThen) or bodyContainsListType(e.ifElse)
  of irCase:
    for b in e.caseBranches:
      if bodyContainsListType(b.body): return true
    result = bodyContainsListType(e.caseDefault)
  of irRecCall:
    for a in e.recArgs:
      if bodyContainsListType(a): return true
  of irVar:
    result = e.varType != nil and e.varType.kind == irtList
  else: discard

func hasUnsupportedType*(ty: IRType): bool {.raises: [].} =
  hasStringType(ty)

func isSmtLoopSound*(bound: int): bool {.raises: [].} =
  ## Whether a resolved static loop bound is SMT-eligible. The emitter unrolls
  ## loops to a FIXED depth `irLoopBmcBound = 10` (src/core/trusted/ir_to_smt.nim:28).
  ## A bound is sound only when the loop provably executes at most that many
  ## iterations; unrolling exactly `bound` iterations is a faithful (not
  ## under-approximating) encoding. Bounds beyond the fixed depth are NOT
  ## soundly encodable and must be honestly skipped.
  bound >= 0 and bound <= 10

func loopBoundOf*(e: IRExpr): Option[int] {.raises: [].} =
  ## Detect a STATIC upper bound for a `lkFor` loop of the form
  ##   init = literal c (c >= 0),  cond = `i < L`  or  `i <= L`,  step = `i + 1`
  ## where L is a compile-time int64 literal. Returns Some(L) (or Some(L+1) for
  ## `i <= L`) when the analysis is deterministic and sound; None for ANY other
  ## shape (while loops, symbolic bounds, calls, mismatched step, etc.).
  ## Conservative by design — ambiguity yields None (honest skip).
  if e == nil or e.kind != irLoop or e.loopKind != lkFor: return none(int)
  if e.loopCond == nil or e.loopCond.kind != irBinOp: return none(int)
  if e.loopCond.binOp notin {boLt, boLe}: return none(int)
  let condLhs = e.loopCond.binLhs
  let condRhs = e.loopCond.binRhs
  if condLhs == nil or condRhs == nil: return none(int)
  if condLhs.kind != irVar or condRhs.kind != irLit: return none(int)
  let loopVar = condLhs.varName
  let bound = condRhs.litVal
  # step must be `i + 1` with the same loop variable
  if e.loopStep == nil or e.loopStep.kind != irBinOp: return none(int)
  if e.loopStep.binOp != boAdd: return none(int)
  if e.loopStep.binLhs == nil or e.loopStep.binRhs == nil: return none(int)
  if e.loopStep.binLhs.kind != irVar or e.loopStep.binLhs.varName != loopVar: return none(int)
  if e.loopStep.binRhs.kind != irLit or e.loopStep.binRhs.litVal != 1: return none(int)
  # init must be a non-negative literal so that iterations (`L - c` or `L - c + 1`)
  # never exceed the claimed bound (a negative init would make a larger bound unsound)
  if e.loopInits.len == 0 or e.loopInits[0] == nil or e.loopInits[0].kind != irLit: return none(int)
  if e.loopInits[0].litVal < 0: return none(int)
  if e.loopCond.binOp == boLe:
    if bound == high(int64): return none(int)
    return some(int(bound + 1))
  some(int(bound))

func collectLoopBounds(e: IRExpr; allSound: var bool; bounds: var seq[int]) {.raises: [].} =
  ## Collect static loop bounds across a body. `allSound` flips to false if any
  ## loop lacks a resolvable bound (nested loops included).
  if e == nil: return
  case e.kind
  of irLoop:
    let b = loopBoundOf(e)
    if b.isNone:
      allSound = false
    else:
      bounds.add(b.get)
    for init in e.loopInits: collectLoopBounds(init, allSound, bounds)
    collectLoopBounds(e.loopCond, allSound, bounds)
    collectLoopBounds(e.loopStep, allSound, bounds)
    collectLoopBounds(e.loopBody, allSound, bounds)
    for inv in e.loopInvariants: collectLoopBounds(inv, allSound, bounds)
    collectLoopBounds(e.loopVariant, allSound, bounds)
  of irBinOp:
    collectLoopBounds(e.binLhs, allSound, bounds)
    collectLoopBounds(e.binRhs, allSound, bounds)
  of irUnaryOp:
    collectLoopBounds(e.unaryArg, allSound, bounds)
  of irLet:
    collectLoopBounds(e.letVal, allSound, bounds)
    collectLoopBounds(e.letBody, allSound, bounds)
  of irIf:
    collectLoopBounds(e.ifCond, allSound, bounds)
    collectLoopBounds(e.ifThen, allSound, bounds)
    collectLoopBounds(e.ifElse, allSound, bounds)
  of irCase:
    collectLoopBounds(e.caseScrutinee, allSound, bounds)
    for b in e.caseBranches: collectLoopBounds(b.body, allSound, bounds)
    collectLoopBounds(e.caseDefault, allSound, bounds)
  of irCall:
    for a in e.callArgs: collectLoopBounds(a, allSound, bounds)
  of irRecCall:
    for a in e.recArgs: collectLoopBounds(a, allSound, bounds)
  of irCast:
    collectLoopBounds(e.castExpr, allSound, bounds)
  of irLit, irFloatLit, irVar, irStringLit: discard

func classifyFunction*(f: IRFuncDef): TierClassification {.raises: [].} =
  if hasStringType(f.retType):
    return TierClassification(tier: vtNonDecidable, reason: "string return type", isBmcSkippable: true)
  for p in f.params:
    if hasStringType(p.ty):
      return TierClassification(tier: vtNonDecidable, reason: "string parameter: " & p.name, isBmcSkippable: true)
  if hasFloatLit(f.body) or hasStringLit(f.body):
    return TierClassification(tier: vtNonDecidable, reason: "float/string literal in body", isBmcSkippable: true)
  if f.isRecursive:
    return TierClassification(tier: vtStructural, reason: "recursive function", isBmcSkippable: false)
  func hasComplexOps(e: IRExpr): bool {.raises: [].} =
    if e == nil: return false
    case e.kind
    of irCall: true
    of irRecCall: true
    of irLoop: true
    of irBinOp: hasComplexOps(e.binLhs) or hasComplexOps(e.binRhs)
    of irUnaryOp: hasComplexOps(e.unaryArg)
    of irLet: hasComplexOps(e.letVal) or hasComplexOps(e.letBody)
    of irIf: hasComplexOps(e.ifCond) or hasComplexOps(e.ifThen) or hasComplexOps(e.ifElse)
    of irCase:
      for b in e.caseBranches:
        if hasComplexOps(b.body): return true
      hasComplexOps(e.caseDefault)
    else: false
  if hasComplexOps(f.body):
    # Tier-2 structural body. Loop BMC (SMT) eligibility: SMT-eligible ONLY when
    # every loop in the body resolves to a static bound AND all bounds <= 10
    # (irToSmt's fixed unroll depth, isSmtLoopSound). Store the MINIMUM observed
    # bound; None when any loop is unresolvable or exceeds the emitter depth
    # (honest skip — under-approximation would be unsound).
    var allSound = true
    var bounds: seq[int] = @[]
    collectLoopBounds(f.body, allSound, bounds)
    var loopBound = none(int)
    if allSound and bounds.len > 0:
      var allWithin = true
      var m = bounds[0]
      for b in bounds:
        if b < m: m = b
        if not isSmtLoopSound(b): allWithin = false
      if allWithin: loopBound = some(m)
    var reason = "complex body operations"
    if loopBound.isSome:
      reason = "complex body operations (loop bounds resolved, min=" & $loopBound.get & ")"
    elif bounds.len > 0:
      reason = "complex body operations (loop bound: unresolved/unsound)"
    return TierClassification(tier: vtStructural, reason: reason,
                              isBmcSkippable: false, loopBound: loopBound)
  TierClassification(tier: vtSmtNative, reason: "simple bitvec/bool operations", isBmcSkippable: false)

func bodyHasLoop*(e: IRExpr): bool {.raises: [].} =
  ## True when the expression tree contains at least one irLoop node.
  if e == nil: return false
  case e.kind
  of irLoop: return true
  of irBinOp:
    result = bodyHasLoop(e.binLhs) or bodyHasLoop(e.binRhs)
  of irUnaryOp:
    result = bodyHasLoop(e.unaryArg)
  of irIf:
    result = bodyHasLoop(e.ifCond) or bodyHasLoop(e.ifThen) or bodyHasLoop(e.ifElse)
  of irCall:
    for a in e.callArgs:
      if bodyHasLoop(a): return true
  of irRecCall:
    for a in e.recArgs:
      if bodyHasLoop(a): return true
  of irLet:
    result = bodyHasLoop(e.letVal) or bodyHasLoop(e.letBody)
  of irCase:
    if bodyHasLoop(e.caseScrutinee): return true
    for br in e.caseBranches:
      if bodyHasLoop(br.body): return true
    result = bodyHasLoop(e.caseDefault)
  of irCast:
    result = bodyHasLoop(e.castExpr)
  else:
    discard

{.pop.}
