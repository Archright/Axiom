## Contract Synthesis — auto-generate preconditions from IR analysis.
##
## Analyzes function body to infer implicit contracts:
## - Division/modulo operations → denominator ≠ 0
## - Sequence/array access via irCall("[]", [seq, idx]) → 0 ≤ index ∧ index < irCall("len", [seq])
## - String char access via irCall("charAt", [s, idx]) → 0 ≤ index ∧ index < irCall("len", [s])
## - String slicing via irCall("substr", [s, start, len]) → 0 ≤ start ∧ start + len ≤ irCall("len", [s])
##
## These contracts are injected into IRFuncDef.preConditions, enabling Z3 to narrow
## the state space and Lean to prove termination.

import core/trusted/layer_declaration
axiomLayer "domain"
import axiom_ir, axiom_ir_helpers

type
  GuardSite* = object
    ## A detected safety guard together with the path condition established by
    ## the enclosing irIf / irCase / irLoop nodes.  `pathCondition` lists those
    ## conditions outermost-first and is EMPTY when the site is reached
    ## unconditionally — an unconditional site has no assumption to discharge
    ## the guard from.
    guard*: IRExpr
    pathCondition*: seq[IRExpr]

  GuardKind* = enum
    ## Which safety-guard family a collection pass recognises.
    gkDivision  ## boDiv / boRem / boRemU → ¬(divisor == 0)
    gkIndex     ## [] / charAt / substr → bounds guard

func conjoinAll(conds: seq[IRExpr]): IRExpr {.raises: [].} =
  ## Left-associative ∧-fold of `conds`; nil for an empty sequence.
  if conds.len == 0: return nil
  var acc = conds[0]
  for i in 1 ..< conds.len: acc = irBinOp(boAnd, acc, conds[i])
  acc

func divisionGuard(e: IRExpr): IRExpr {.raises: [].} =
  ## boDiv / boRem / boRemU → ¬(divisor == 0), built from the divisor
  ## sub-expression itself (there is no boNe in the IR).  boRemU is the
  ## unsigned modulo (Nim `%%`) and divides by its right operand exactly like
  ## the signed forms, so it carries the same guard.  nil for every other node.
  if e != nil and e.kind == irBinOp and e.binOp in {boDiv, boRem, boRemU}:
    return irUnaryOp(uoNot, irBinOp(boEq, e.binRhs, irLit(0)))
  nil

func indexGuard(e: IRExpr): IRExpr {.raises: [].} =
  ## Bounds guards built from the actual index/sequence sub-expressions:
  ##   irCall("[]", [seqExpr, idxExpr])    → 0 ≤ idx ∧ idx < len(seq)
  ##   irCall("charAt", [s, idxExpr])      → 0 ≤ idx ∧ idx < len(s)
  ##   irCall("substr", [s, start, len])   → 0 ≤ start ∧ start + len ≤ len(s)
  ## nil for every other node.
  if e == nil or e.kind != irCall:
    return nil
  let zero = irLit(0)
  if e.callName == "[]" and e.callArgs.len >= 2:
    let seqExpr = e.callArgs[0]
    let idxExpr = e.callArgs[^1]
    return irBinOp(boAnd,
      irBinOp(boGe, idxExpr, zero),
      irBinOp(boLt, idxExpr, irCall("len", @[seqExpr])))
  if e.callName == "charAt" and e.callArgs.len >= 2:
    let strExpr = e.callArgs[0]
    let idxExpr = e.callArgs[1]
    return irBinOp(boAnd,
      irBinOp(boGe, idxExpr, zero),
      irBinOp(boLt, idxExpr, irCall("len", @[strExpr])))
  if e.callName == "substr" and e.callArgs.len >= 3:
    let sExpr = e.callArgs[0]
    let startExpr = e.callArgs[1]
    let lenExprArg = e.callArgs[2]
    return irBinOp(boAnd,
      irBinOp(boGe, startExpr, zero),
      irBinOp(boLe, irBinOp(boAdd, startExpr, lenExprArg),
        irCall("len", @[sExpr])))
  nil

func guardFor(e: IRExpr, kind: GuardKind): IRExpr {.raises: [].} =
  ## The guard `e` induces under `kind`, or nil when it induces none.
  case kind
  of gkDivision: divisionGuard(e)
  of gkIndex: indexGuard(e)

func walkGuardSites(e: IRExpr, cond: seq[IRExpr], kind: GuardKind, acc: var seq[GuardSite]) {.raises: [].} =
  ## One pre-order step of the guard-site walk, threading `cond` — the path
  ## condition holding at `e` — down to every node it reaches.
  if e == nil: return
  let g = guardFor(e, kind)
  if g != nil:
    acc.add GuardSite(guard: g, pathCondition: cond)
  case e.kind
  of irBinOp:
    walkGuardSites(e.binLhs, cond, kind, acc)
    walkGuardSites(e.binRhs, cond, kind, acc)
  of irLet:
    walkGuardSites(e.letVal, cond, kind, acc)
    walkGuardSites(e.letBody, cond, kind, acc)
  of irIf:
    walkGuardSites(e.ifCond, cond, kind, acc)
    if e.ifCond != nil:
      walkGuardSites(e.ifThen, cond & @[e.ifCond], kind, acc)
      walkGuardSites(e.ifElse, cond & @[irUnaryOp(uoNot, e.ifCond)], kind, acc)
    else:
      walkGuardSites(e.ifThen, cond, kind, acc)
      walkGuardSites(e.ifElse, cond, kind, acc)
  of irCase:
    walkGuardSites(e.caseScrutinee, cond, kind, acc)
    if e.caseScrutinee == nil:
      for b in e.caseBranches: walkGuardSites(b.body, cond, kind, acc)
      walkGuardSites(e.caseDefault, cond, kind, acc)
    else:
      let scrut = e.caseScrutinee
      var matches: seq[IRExpr]
      for b in e.caseBranches:
        let m = irBinOp(boEq, scrut, irLit(b.pattern))
        matches.add m
        walkGuardSites(b.body, cond & @[m], kind, acc)
      let matched = conjoinAll(matches)
      if matched == nil:
        walkGuardSites(e.caseDefault, cond, kind, acc)
      else:
        walkGuardSites(e.caseDefault, cond & @[irUnaryOp(uoNot, matched)], kind, acc)
  of irCall:
    for a in e.callArgs: walkGuardSites(a, cond, kind, acc)
  of irUnaryOp:
    walkGuardSites(e.unaryArg, cond, kind, acc)
  of irRecCall:
    for a in e.recArgs: walkGuardSites(a, cond, kind, acc)
  of irLoop:
    for a in e.loopInits: walkGuardSites(a, cond, kind, acc)
    walkGuardSites(e.loopCond, cond, kind, acc)
    walkGuardSites(e.loopStep, cond, kind, acc)
    walkGuardSites(e.loopBody, if e.loopCond != nil: cond & @[e.loopCond] else: cond, kind, acc)
  else: discard

func collectGuardSites*(body: IRExpr, kind: GuardKind): seq[GuardSite] {.raises: [].} =
  ## Walk `body` and tag every guard it induces with the path condition holding
  ## at that node.
  ##
  ## A branch body is only reachable under its own condition, so the condition
  ## joins the path condition there: ifThen under `ifCond`, ifElse under
  ## `¬ifCond`, a case arm under `scrutinee == pattern`, the default arm under
  ## the negation of all pattern matches, and a loop body under `loopCond`.
  ## Pure and deterministic; introduces no new IR node kind.
  result = @[]
  walkGuardSites(body, @[], kind, result)

func collectDivisionGuardSites*(body: IRExpr): seq[GuardSite] {.raises: [].} =
  ## Division safety guards, each tagged with the path condition that must hold
  ## for the division to be reached.
  collectGuardSites(body, gkDivision)

func collectDivisionGuards*(body: IRExpr): seq[IRExpr] {.raises: [].} =
  ## Find all BV64 division/modulo operations and generate denominator ≠ 0 guards.
  result = @[]
  for site in collectDivisionGuardSites(body):
    result.add site.guard

func collectIndexGuardSites*(body: IRExpr): seq[GuardSite] {.raises: [].} =
  ## Index safety guards, each tagged with the path condition that must hold for
  ## the access to be reached.
  collectGuardSites(body, gkIndex)

func collectIndexGuards*(body: IRExpr): seq[IRExpr] {.raises: [].} =
  ## Detect irCall("[]", [seqExpr, idxExpr]) and generate:
  ##   0 ≤ index ∧ index < irCall("len", [seqExpr])
  ## Detect irCall("charAt", [s, idxExpr]) and generate:
  ##   0 ≤ index ∧ index < irCall("len", [s])
  ## Detect irCall("substr", [s, start, len]) and generate:
  ##   0 ≤ start ∧ start + len ≤ irCall("len", [s])
  result = @[]
  for site in collectIndexGuardSites(body):
    result.add site.guard

type
  ClampBounds* = object
    found*: bool   ## True when the body is a recognized clamp/range pattern
    lo*: int64     ## Lower bound literal
    hi*: int64     ## Upper bound literal

func isLitVal*(e: IRExpr; v: int64): bool {.raises: [].} =
  ## True when `e` is an integer literal equal to `v`.
  e != nil and e.kind == irLit and e.litVal == v

func isSameVar*(a, b: IRExpr): bool {.raises: [].} =
  ## True when both expressions are the same non-empty variable reference.
  a != nil and b != nil and a.kind == irVar and b.kind == irVar and
    a.varName.len > 0 and a.varName == b.varName

func matchLowerOnlyBound*(e: IRExpr): ClampBounds {.raises: [].} =
  ## Detect a lower-only clamp: `if x < lo then lo else x` (or `x <= lo`).
  ## Postcondition: result >= lo (when x < lo → lo; when x >= lo → x >= lo).
  ## Conservative — recognizes ONLY the literal shape; never fabricates a bound
  ## the body does not saturate to (§0.9 theater rule).
  result = ClampBounds(found: false, lo: 0, hi: 0)
  if e == nil or e.kind != irIf: return
  let c = e.ifCond
  if c.kind != irBinOp or c.binOp notin {boLt, boLe}: return
  let x = c.binLhs
  let loNode = c.binRhs
  if loNode.kind != irLit: return
  let loV = loNode.litVal
  if not isLitVal(e.ifThen, loV): return
  if not isSameVar(e.ifElse, x): return
  result = ClampBounds(found: true, lo: loV, hi: 0)

func matchUpperOnlyBound*(e: IRExpr): ClampBounds {.raises: [].} =
  ## Detect an upper-only clamp: `if x > hi then hi else x` (or `x >= hi`).
  ## Postcondition: result <= hi (when x > hi → hi; when x <= hi → x <= hi).
  ## Conservative — recognizes ONLY the literal shape; never fabricates a bound.
  result = ClampBounds(found: false, lo: 0, hi: 0)
  if e == nil or e.kind != irIf: return
  let c = e.ifCond
  if c.kind != irBinOp or c.binOp notin {boGt, boGe}: return
  let x = c.binLhs
  let hiNode = c.binRhs
  if hiNode.kind != irLit: return
  let hiV = hiNode.litVal
  if not isLitVal(e.ifThen, hiV): return
  if not isSameVar(e.ifElse, x): return
  result = ClampBounds(found: true, lo: 0, hi: hiV)

func matchClampBounds*(e: IRExpr): ClampBounds {.raises: [].} =
  ## Detect a clamp/range pattern in a BitVec64-returning body.
  ## Recognized forms:
  ##   - `if x < lo then lo else (if x > hi then hi else x)`
  ##   - `min(max(x, lo), hi)` via irCall("min", [irCall("max", [x, lo]), hi])
  ## Returns found=true with (lo, hi) bounds when recognized; conservative
  ## (found=false) for any other body shape — we never fabricate a constraint
  ## the body does not actually saturate to.
  result = ClampBounds(found: false, lo: 0, hi: 0)
  if e == nil: return
  # Form 2: min(max(x, lo), hi)
  if e.kind == irCall and e.callName == "min" and e.callArgs.len == 2:
    let inner = e.callArgs[0]
    let hiNode = e.callArgs[1]
    if inner.kind == irCall and inner.callName == "max" and inner.callArgs.len == 2:
      let loNode = inner.callArgs[1]
      if loNode.kind == irLit and hiNode.kind == irLit:
        result = ClampBounds(found: true, lo: loNode.litVal, hi: hiNode.litVal)
    return
  # Form 1: if x < lo then lo else (if x > hi then hi else x)
  if e.kind != irIf: return
  let c1 = e.ifCond
  if c1.kind != irBinOp or c1.binOp notin {boLt, boLe}: return
  let x = c1.binLhs
  let loNode = c1.binRhs
  if loNode.kind != irLit: return
  let loV = loNode.litVal
  if not isLitVal(e.ifThen, loV): return
  let elseE = e.ifElse
  if elseE.kind == irIf:
    let c2 = elseE.ifCond
    if c2.kind == irBinOp and c2.binOp in {boGt, boGe} and isSameVar(c2.binLhs, x):
      let hiNode = c2.binRhs
      if hiNode.kind == irLit:
        let hiV = hiNode.litVal
        if isLitVal(elseE.ifThen, hiV) and isSameVar(elseE.ifElse, x):
          result = ClampBounds(found: true, lo: loV, hi: hiV)

func collectPostconditions*(funcDef: IRFuncDef): seq[IRExpr] {.raises: [].} =
  ## Auto-synthesize implicit safety postconditions when none are explicitly specified.
  ## For enum/variant return types: constrain return value to valid ordinal range.
  ## For BitVec64 (int) return types: synthesize a range postcondition when the
  ## body is a recognizable clamp pattern.
  ## For other types: no constraint needed (trivially safe).
  result = @[]
  case funcDef.retType.kind
  of irtEnum:
    if funcDef.retType.enumOrdinals.len > 0:
      var maxOrd = funcDef.retType.enumOrdinals[0]
      for o in funcDef.retType.enumOrdinals:
        if o > maxOrd: maxOrd = o
      # Postcondition: return value <= max ordinal
      result.add(irBinOp(boLe, irVar("result", irTypeBitVec64()), irLit(maxOrd)))
  of irtVariant:
    if funcDef.retType.variantOrdinals.len > 0:
      var maxOrd = funcDef.retType.variantOrdinals[0]
      for o in funcDef.retType.variantOrdinals:
        if o > maxOrd: maxOrd = o
      # Postcondition: tag bits <= max ordinal
      result.add(irBinOp(boLe, irVar("result", irTypeBitVec64()), irLit(maxOrd)))
  of irtBitVec64:
    # For plain BitVec64 (int): synthesize a range postcondition when the body
    # is a recognizable clamp pattern (e.g. `if x < lo then lo else if x > hi
    # then hi else x`). This populates postConditions for int clamp kernels so
    # the IR pipeline emits a Z3 query and a Lean theorem. If the body is NOT a
    # recognizable clamp/range pattern, leave empty (conservative — never
    # fabricate a constraint the body does not actually saturate to).
    let bounds = matchClampBounds(funcDef.body)
    if bounds.found:
      let resultVar = irVar("result", irTypeBitVec64())
      result.add(irBinOp(boAnd,
        irBinOp(boGe, resultVar, irLit(bounds.lo)),
        irBinOp(boLe, resultVar, irLit(bounds.hi))))
    else:
      # Lower-only clamp: `if x < lo then lo else x` → result >= lo.
      let loBounds = matchLowerOnlyBound(funcDef.body)
      if loBounds.found:
        let resultVar = irVar("result", irTypeBitVec64())
        result.add(irBinOp(boGe, resultVar, irLit(loBounds.lo)))
      else:
        # Upper-only clamp: `if x > hi then hi else x` → result <= hi.
        let hiBounds = matchUpperOnlyBound(funcDef.body)
        if hiBounds.found:
          let resultVar = irVar("result", irTypeBitVec64())
          result.add(irBinOp(boLe, resultVar, irLit(hiBounds.hi)))
  of irtBool:
    # For Bool: no implicit postcondition needed. Bool postconditions are
    # supplied explicitly via the `{.axiom: [post: ...].}` pragma (Rule A),
    # which bypasses this implicit-synthesis engine (see §0.9 anti-theater —
    # this engine never guesses a constraint an unannotated body does not
    # provably saturate to).
    discard
  of irtList:
    # For List: no implicit postcondition needed
    discard
  of irtString:
    # For String: no implicit postcondition needed (BMC-skipped anyway)
    discard

func collectAssertGuards*(body: IRExpr): seq[IRExpr] {.raises: [].} =
  ## Find irCall("doAssert", [condition]) / irCall("assert", [condition])
  ## and extract the condition as a precondition.
  result = @[]
  func walk(e: IRExpr, acc: var seq[IRExpr]) {.raises: [].} =
    if e == nil: return
    case e.kind
    of irCall:
      if e.callName in ["doAssert", "assert"] and e.callArgs.len > 0:
        acc.add e.callArgs[0]
      for a in e.callArgs: walk(a, acc)
    of irBinOp:
      walk(e.binLhs, acc)
      walk(e.binRhs, acc)
    of irLet:
      walk(e.letVal, acc)
      walk(e.letBody, acc)
    of irIf:
      walk(e.ifCond, acc)
      walk(e.ifThen, acc)
      walk(e.ifElse, acc)
    of irCase:
      walk(e.caseScrutinee, acc)
      for b in e.caseBranches: walk(b.body, acc)
      walk(e.caseDefault, acc)
    of irUnaryOp:
      walk(e.unaryArg, acc)
    of irRecCall:
      for a in e.recArgs: walk(a, acc)
    of irLoop:
      for a in e.loopInits: walk(a, acc)
      walk(e.loopCond, acc)
      walk(e.loopStep, acc)
      walk(e.loopBody, acc)
    else: discard
  walk(body, result)

func synthesizeContracts*(funcDef: var IRFuncDef) {.raises: [].} =
  ## Main entry: analyze funcDef body and populate preConditions + postConditions.
  funcDef.preConditions.add(collectDivisionGuards(funcDef.body))
  funcDef.preConditions.add(collectIndexGuards(funcDef.body))
  funcDef.preConditions.add(collectAssertGuards(funcDef.body))
  # Auto-synthesize implicit safety postconditions if none exist
  if funcDef.postConditions.len == 0:
    funcDef.postConditions.add(collectPostconditions(funcDef))

