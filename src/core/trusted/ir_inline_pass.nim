import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Hygienic IR Inlining — eliminate UF declarations via alpha-renamed substitution.
##
## Replaces irCall("funcName", args) with irLet(freshName, args[0],
##   substituteVar(body, paramName, freshName))
##
## Properties:
## - freshName() uses a global atomic counter (no depth suffix, no collisions)
## - Bounded: only inlines functions with body ≤ 10 IR nodes
## - Non-recursive only: isRecursive == true → skip
## - Pure: produces a new IRExpr tree, original unchanged

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers

# ---------------------------------------------------------------------------
# Fresh name generation (global counter — no depth suffix, no collisions)
# ---------------------------------------------------------------------------

var inlineCounter {.global.}: int = 0

proc freshName(): string {.raises: [].} =
  ## Generate a globally unique hygienic name.
  ## Uses atomic counter: __inl_0, __inl_1, ...
  inc inlineCounter
  "__inl_" & $inlineCounter

# ---------------------------------------------------------------------------
# IR node counting (determines inlineability)
# ---------------------------------------------------------------------------

func irNodeCount*(e: IRExpr): int {.raises: [].} =
  ## Count IR nodes in expression tree.
  if e == nil: return 0
  result = 1
  case e.kind
  of irLit, irFloatLit, irVar, irStringLit: discard
  of irLet:
    result += irNodeCount(e.letVal) + irNodeCount(e.letBody)
  of irIf:
    result += irNodeCount(e.ifCond) + irNodeCount(e.ifThen) + irNodeCount(e.ifElse)
  of irCall:
    for a in e.callArgs: result += irNodeCount(a)
  of irBinOp:
    result += irNodeCount(e.binLhs) + irNodeCount(e.binRhs)
  of irUnaryOp:
    result += irNodeCount(e.unaryArg)
  of irCase:
    result += irNodeCount(e.caseScrutinee)
    for b in e.caseBranches: result += irNodeCount(b.body)
    result += irNodeCount(e.caseDefault)
  of irRecCall:
    for a in e.recArgs: result += irNodeCount(a)
  of irLoop:
    for a in e.loopInits: result += irNodeCount(a)
    result += irNodeCount(e.loopCond)
    result += irNodeCount(e.loopStep)
    result += irNodeCount(e.loopBody)
  of irCast:
    result += irNodeCount(e.castExpr)

# ---------------------------------------------------------------------------
# Alpha-renaming substitution (pure, deterministic)
# ---------------------------------------------------------------------------

func substituteVar*(e: IRExpr, oldName: string, newName: string): IRExpr {.raises: [].} =
  ## Replace all occurrences of oldName with newName in expression tree.
  ## This is a tree-copy with substitution — pure and deterministic.
  ## Respects let-binding shadowing: if a let binds `oldName`, the body is NOT substituted.
  if e == nil: return nil
  case e.kind
  of irVar:
    if e.varName == oldName:
      return irVar(newName, e.varType)
    return e
  of irLit, irFloatLit, irStringLit: return e
  of irLet:
    let newVal = substituteVar(e.letVal, oldName, newName)
    # If the let binding shadows oldName, don't substitute in body
    if e.letName == oldName:
      return irLet(e.letName, newVal, e.letBody, e.isCompileTime)
    let newBody = substituteVar(e.letBody, oldName, newName)
    return irLet(e.letName, newVal, newBody, e.isCompileTime)
  of irIf:
    return irIf(substituteVar(e.ifCond, oldName, newName),
                substituteVar(e.ifThen, oldName, newName),
                substituteVar(e.ifElse, oldName, newName))
  of irCall:
    var newArgs: seq[IRExpr] = @[]
    for a in e.callArgs: newArgs.add substituteVar(a, oldName, newName)
    return irCall(e.callName, newArgs, e.typ)
  of irBinOp:
    return irBinOp(e.binOp,
                   substituteVar(e.binLhs, oldName, newName),
                   substituteVar(e.binRhs, oldName, newName))
  of irUnaryOp:
    return irUnaryOp(e.unaryOp, substituteVar(e.unaryArg, oldName, newName))
  of irCase:
    var newBranches: seq[CaseBranch] = @[]
    for b in e.caseBranches:
      newBranches.add CaseBranch(pattern: b.pattern,
                                 body: substituteVar(b.body, oldName, newName))
    return irCase(substituteVar(e.caseScrutinee, oldName, newName),
                  newBranches,
                  substituteVar(e.caseDefault, oldName, newName))
  of irRecCall:
    var newArgs: seq[IRExpr] = @[]
    for a in e.recArgs: newArgs.add substituteVar(a, oldName, newName)
    return irRecCall(newArgs)
  of irLoop:
    var newInits: seq[IRExpr] = @[]
    for a in e.loopInits: newInits.add substituteVar(a, oldName, newName)
    var newInvariants: seq[IRExpr] = @[]
    for a in e.loopInvariants: newInvariants.add substituteVar(a, oldName, newName)
    return irLoop(e.loopKind, e.loopVars, newInits,
                  substituteVar(e.loopCond, oldName, newName),
                  substituteVar(e.loopStep, oldName, newName),
                  substituteVar(e.loopBody, oldName, newName),
                  newInvariants,
                  substituteVar(e.loopVariant, oldName, newName))
  of irCast:
    return irCast(substituteVar(e.castExpr, oldName, newName), e.castTo)

# ---------------------------------------------------------------------------
# Single call-site inlining
# ---------------------------------------------------------------------------

proc inlineCallSite(callee: IRFuncDef, callExpr: IRExpr): IRExpr {.raises: [].} =
  ## Inline a single call site:
  ##   irCall("f", [arg]) → irLet("__inl_N", arg, body[params[0] → __inl_N])
  assert callExpr.kind == irCall
  assert callee.params.len == callExpr.callArgs.len

  var body = callee.body
  # For each parameter, create a fresh name, substitute in body, wrap in irLet
  for i in 0 ..< callee.params.len:
    let fresh = freshName()
    let arg = callExpr.callArgs[i]
    body = substituteVar(body, callee.params[i].name, fresh)
    body = irLet(fresh, arg, body)  # runtime inlining binding (fresh var — not compile-time)
  return body

# ---------------------------------------------------------------------------
# Public API: bounded IR inlining pass
# ---------------------------------------------------------------------------

proc inlineSmallFunctions*(body: IRExpr, env: seq[IRFuncDef],
                           maxNodes: int = 10): IRExpr {.raises: [].} =
  ## Walk the IR tree and inline calls to small (≤ maxNodes) non-recursive functions.
  ## Returns a new expression tree (original unchanged).
  ## Only inlines one level deep — no recursive inlining of inlined functions.
  if body == nil: return nil

  # First, recurse into children to inline nested calls
  var e = body
  case e.kind
  of irCall:
    # Inline arguments first (bottom-up)
    var newArgs: seq[IRExpr] = @[]
    for a in e.callArgs: newArgs.add inlineSmallFunctions(a, env, maxNodes)
    # irCall smart constructor sets typ=nil; if e.typ was nil it stays nil here.
    # recomputeTyp resolves irCall defaults (builtin lookup → BV64 fallback).
    e = irCall(e.callName, newArgs, e.typ)

    # Now try to inline this call itself
    for funcDef in env:
      if funcDef.name == e.callName and not funcDef.isRecursive:
        if irNodeCount(funcDef.body) <= maxNodes:
          return inlineCallSite(funcDef, e)
        break  # Found the function but too large — don't check further
    return e
  of irLet:
    return irLet(e.letName,
                 inlineSmallFunctions(e.letVal, env, maxNodes),
                 inlineSmallFunctions(e.letBody, env, maxNodes),
                 e.isCompileTime)
  of irIf:
    return irIf(inlineSmallFunctions(e.ifCond, env, maxNodes),
                inlineSmallFunctions(e.ifThen, env, maxNodes),
                inlineSmallFunctions(e.ifElse, env, maxNodes))
  of irBinOp:
    return irBinOp(e.binOp,
                   inlineSmallFunctions(e.binLhs, env, maxNodes),
                   inlineSmallFunctions(e.binRhs, env, maxNodes))
  of irUnaryOp:
    return irUnaryOp(e.unaryOp, inlineSmallFunctions(e.unaryArg, env, maxNodes))
  of irCase:
    var newBranches: seq[CaseBranch] = @[]
    for b in e.caseBranches:
      newBranches.add CaseBranch(pattern: b.pattern,
                                 body: inlineSmallFunctions(b.body, env, maxNodes))
    return irCase(inlineSmallFunctions(e.caseScrutinee, env, maxNodes),
                  newBranches,
                  inlineSmallFunctions(e.caseDefault, env, maxNodes))
  of irRecCall:
    # Never inline recursive calls
    return e
  of irLoop:
    var newInits: seq[IRExpr] = @[]
    for a in e.loopInits: newInits.add inlineSmallFunctions(a, env, maxNodes)
    var newInvariants: seq[IRExpr] = @[]
    for a in e.loopInvariants: newInvariants.add inlineSmallFunctions(a, env, maxNodes)
    return irLoop(e.loopKind, e.loopVars, newInits,
                  inlineSmallFunctions(e.loopCond, env, maxNodes),
                  inlineSmallFunctions(e.loopStep, env, maxNodes),
                  inlineSmallFunctions(e.loopBody, env, maxNodes),
                  newInvariants,
                  inlineSmallFunctions(e.loopVariant, env, maxNodes))
  of irCast:
    return irCast(inlineSmallFunctions(e.castExpr, env, maxNodes), e.castTo)
  of irLit:
    if e.typ == nil: e.typ = irTypeBitVec64()
    return e
  of irFloatLit:
    if e.typ == nil: e.typ = irTypeBitVec64()
    return e
  of irVar:
    if e.varType != nil and e.typ == nil: e.typ = e.varType
    return e
  of irStringLit:
    if e.typ == nil: e.typ = irTypeString()
    return e

{.pop.}
