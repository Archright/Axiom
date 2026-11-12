import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## IR Tree Operations — pure-functional transformations on IRExpr trees.
##
## Extracted from ir_to_smt_chunk1.nim to enable import by bmc_lower.nim
## without circular dependencies.
##
## Functions:
##   substVarsInExpr  — rename variables in an expression tree
##   resolveRecCalls  — replace irRecCall nodes with irCall(funcName, ...)
##   buildSubstMap    — build substitution map for BMC loop unrolling
##   genTerminationRef — generate termination reference for BMC unrolling
##
## Properties:
##   - Pure-functional: no side effects, no I/O
##   - All functions are `func` with `{.raises: [].}`
##   - resolveRecCalls returns a NEW tree (deep copy with transformation)

import core/trusted/axiom_ir

# ---------------------------------------------------------------------------
# Variable substitution in IRExpr (for loop unrolling)
# ---------------------------------------------------------------------------

func substVarsInExpr*(e: IRExpr, subst: openArray[(string, string)]): IRExpr {.raises: [].} =
  ## Rename variables in an IRExpr tree according to a substitution mapping.
  ## Each pair (oldName, newName) replaces varName == oldName with newName.
  ## Returns a new IRExpr tree — the original is not mutated.
  case e.kind
  of irLit:
    IRExpr(typ: e.typ, kind: irLit, litVal: e.litVal, litU64: e.litU64)
  of irFloatLit:
    IRExpr(typ: e.typ, kind: irFloatLit, floatVal: e.floatVal)
  of irVar:
    for (oldName, newName) in subst:
      if e.varName == oldName:
        return IRExpr(typ: e.typ, kind: irVar, varName: newName, varType: e.varType)
    IRExpr(typ: e.typ, kind: irVar, varName: e.varName, varType: e.varType)
  of irLet:
    IRExpr(typ: e.typ, kind: irLet, letName: e.letName,
           letVal: substVarsInExpr(e.letVal, subst),
           letBody: substVarsInExpr(e.letBody, subst),
           isCompileTime: e.isCompileTime)
  of irIf:
    IRExpr(typ: e.typ, kind: irIf,
           ifCond: substVarsInExpr(e.ifCond, subst),
           ifThen: substVarsInExpr(e.ifThen, subst),
           ifElse: substVarsInExpr(e.ifElse, subst))
  of irCase:
    var newBranches: seq[CaseBranch]
    for br in e.caseBranches:
      newBranches.add(CaseBranch(pattern: br.pattern,
                                 body: substVarsInExpr(br.body, subst)))
    let newDefault = if e.caseDefault != nil:
                       substVarsInExpr(e.caseDefault, subst)
                     else: nil
    IRExpr(typ: e.typ, kind: irCase,
           caseScrutinee: substVarsInExpr(e.caseScrutinee, subst),
           caseBranches: newBranches,
           caseDefault: newDefault)
  of irCall:
    var newArgs: seq[IRExpr]
    for a in e.callArgs:
      newArgs.add(substVarsInExpr(a, subst))
    IRExpr(typ: e.typ, kind: irCall, callName: e.callName, callArgs: newArgs)
  of irBinOp:
    IRExpr(typ: e.typ, kind: irBinOp, binOp: e.binOp,
           binLhs: substVarsInExpr(e.binLhs, subst),
           binRhs: substVarsInExpr(e.binRhs, subst))
  of irUnaryOp:
    IRExpr(typ: e.typ, kind: irUnaryOp, unaryOp: e.unaryOp,
           unaryArg: substVarsInExpr(e.unaryArg, subst))
  of irRecCall:
    var newArgs: seq[IRExpr]
    for a in e.recArgs:
      newArgs.add(substVarsInExpr(a, subst))
    IRExpr(typ: e.typ, kind: irRecCall, recArgs: newArgs)
  of irStringLit:
    IRExpr(typ: e.typ, kind: irStringLit, stringVal: e.stringVal)
  of irLoop:
    var newInits: seq[IRExpr]
    for init in e.loopInits:
      newInits.add(substVarsInExpr(init, subst))
    var newInvariants: seq[IRExpr]
    for inv in e.loopInvariants:
      newInvariants.add(substVarsInExpr(inv, subst))
    let newStep = if e.loopStep != nil:
                    substVarsInExpr(e.loopStep, subst)
                  else: nil
    let newVariant = if e.loopVariant != nil:
                       substVarsInExpr(e.loopVariant, subst)
                     else: nil
    IRExpr(typ: e.typ, kind: irLoop, loopKind: e.loopKind, loopVars: e.loopVars,
           loopInits: newInits,
           loopCond: substVarsInExpr(e.loopCond, subst),
           loopStep: newStep,
           loopBody: substVarsInExpr(e.loopBody, subst),
           loopInvariants: newInvariants,
           loopVariant: newVariant)
  of irCast:
    IRExpr(typ: e.typ, kind: irCast,
           castExpr: substVarsInExpr(e.castExpr, subst),
           castFrom: e.castFrom, castTo: e.castTo)

# ---------------------------------------------------------------------------
# Self-recursive call resolution
# ---------------------------------------------------------------------------

func resolveRecCalls*(e: IRExpr, funcName: string): IRExpr {.raises: [].} =
  ## Replace irRecCall nodes with irCall(funcName, ...) for SMT-LIB2 emission.
  ## Self-recursive calls have no function name in IR; this resolves them to
  ## a named call so irExprToSmt emits valid SMT-LIB2 `(funcName args...)`.
  ## Calls recomputeTyp to ensure all types are synthesized after deep copy.
  if e == nil: return nil
  result = case e.kind
  of irRecCall:
    var newArgs: seq[IRExpr]
    for a in e.recArgs:
      newArgs.add(resolveRecCalls(a, funcName))
    IRExpr(typ: e.typ, kind: irCall, callName: funcName, callArgs: newArgs)
  of irLet:
    IRExpr(typ: e.typ, kind: irLet, letName: e.letName,
           letVal: resolveRecCalls(e.letVal, funcName),
           letBody: resolveRecCalls(e.letBody, funcName),
           isCompileTime: e.isCompileTime)
  of irIf:
    IRExpr(typ: e.typ, kind: irIf,
           ifCond: resolveRecCalls(e.ifCond, funcName),
           ifThen: resolveRecCalls(e.ifThen, funcName),
           ifElse: resolveRecCalls(e.ifElse, funcName))
  of irCase:
    var newBranches: seq[CaseBranch]
    for br in e.caseBranches:
      newBranches.add(CaseBranch(pattern: br.pattern,
                                 body: resolveRecCalls(br.body, funcName)))
    let newDefault = if e.caseDefault != nil:
                       resolveRecCalls(e.caseDefault, funcName)
                     else: nil
    IRExpr(typ: e.typ, kind: irCase,
           caseScrutinee: resolveRecCalls(e.caseScrutinee, funcName),
           caseBranches: newBranches,
           caseDefault: newDefault)
  of irCall:
    var newArgs: seq[IRExpr]
    for a in e.callArgs:
      newArgs.add(resolveRecCalls(a, funcName))
    IRExpr(typ: e.typ, kind: irCall, callName: e.callName, callArgs: newArgs)
  of irBinOp:
    IRExpr(typ: e.typ, kind: irBinOp, binOp: e.binOp,
           binLhs: resolveRecCalls(e.binLhs, funcName),
           binRhs: resolveRecCalls(e.binRhs, funcName))
  of irUnaryOp:
    IRExpr(typ: e.typ, kind: irUnaryOp, unaryOp: e.unaryOp,
           unaryArg: resolveRecCalls(e.unaryArg, funcName))
  of irLoop:
    var newInits: seq[IRExpr]
    for init in e.loopInits:
      newInits.add(resolveRecCalls(init, funcName))
    var newInvariants: seq[IRExpr]
    for inv in e.loopInvariants:
      newInvariants.add(resolveRecCalls(inv, funcName))
    IRExpr(typ: e.typ, kind: irLoop, loopKind: e.loopKind, loopVars: e.loopVars,
           loopInits: newInits,
           loopCond: resolveRecCalls(e.loopCond, funcName),
           loopStep: if e.loopStep != nil: resolveRecCalls(e.loopStep, funcName) else: nil,
           loopBody: resolveRecCalls(e.loopBody, funcName),
           loopInvariants: newInvariants,
           loopVariant: if e.loopVariant != nil: resolveRecCalls(e.loopVariant, funcName) else: nil)
  of irCast:
    IRExpr(typ: e.typ, kind: irCast,
           castExpr: resolveRecCalls(e.castExpr, funcName),
           castFrom: e.castFrom, castTo: e.castTo)
  of irLit, irFloatLit, irVar, irStringLit:
    e  # Leaf nodes — return as-is
  recomputeTyp(result)

# ---------------------------------------------------------------------------
# BMC loop unrolling helpers (no dependency on irExprToSmt)
# ---------------------------------------------------------------------------

func buildSubstMap*(loopVars: seq[string], k: int): seq[(string, string)] {.raises: [].} =
  ## Creates substitution map: [("var0", "var0_3"), ("var1", "var1_3"), ...]
  for v in loopVars:
    result.add((v, v & "_" & $k))

func genTerminationRef*(loopVars: seq[string], k: int): string {.raises: [].} =
  ## Final step reference — returns the result variable at step k.
  ## Convention: loopVars[^1] is the accumulator/result.
  if loopVars.len == 0:
    "true"  # Degenerate loop (no state vars) → tautological termination ref
  elif loopVars.len == 1:
    loopVars[0] & "_" & $k
  else:
    loopVars[^1] & "_" & $k

{.pop.}
