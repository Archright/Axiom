import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Helper constructors and pretty-printers for Axiom Core IR.
##
## Pure-functional: every proc is `func`, no side effects.
## Import this module to build IR trees concisely.

import core/trusted/axiom_ir
export axiom_ir

# ---------------------------------------------------------------------------
# Audit trail (opt-in: compile with -d:axiomAudit to enable)
# ---------------------------------------------------------------------------

when defined(axiomAudit):
  var smartCastCount {.global.}: int = 0
  func getSmartCastCount*(): int = smartCastCount

# ---------------------------------------------------------------------------
# Expression constructors
# ---------------------------------------------------------------------------

func irLit*(v: int64): IRExpr {.inline.} =
  ## Integer literal.
  IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: v)

func irLitU64*(v: uint64): IRExpr {.inline.} =
  ## u64-domain integer literal — the ONLY carrier for [2^63, 2^64−1];
  ## a value ≥ 2^63 is never reinterpreted into `litVal`.
  doAssert v >= 0x8000000000000000'u64
  IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0, litU64: v)

func irFloatLit*(v: float64): IRExpr {.inline.} =
  ## Float literal (fixed-point scaled to int64 during SMT encoding).
  IRExpr(typ: irTypeBitVec64(), kind: irFloatLit, floatVal: v)

func irVar*(name: string, ty: IRType): IRExpr {.inline.} =
  ## Variable reference.
  IRExpr(typ: ty, kind: irVar, varName: name, varType: ty)

func irLet*(name: string, val, body: IRExpr; isCompileTime: bool = false): IRExpr {.inline.} =
  ## Let-binding: `let name = val in body`.
  let bodyTyp = if body != nil and body.typ != nil: body.typ
                else: irTypeBitVec64()
  IRExpr(typ: bodyTyp, kind: irLet, letName: name, letVal: val, letBody: body, isCompileTime: isCompileTime)

func irIf*(cond, thenExpr, elseExpr: IRExpr): IRExpr {.inline.} =
  ## If-then-else.
  let thenTyp = if thenExpr != nil and thenExpr.typ != nil: thenExpr.typ
                else: irTypeBitVec64()
  IRExpr(typ: thenTyp, kind: irIf, ifCond: cond, ifThen: thenExpr, ifElse: elseExpr)

func irBinOp*(op: BinOpKind, lhs, rhs: IRExpr): IRExpr =
  ## Smart Constructor: enforces type rules at construction time.
  ## boAnd/boOr require Bool operands — BV64 operands are auto-wrapped
  ## in irCall("opCastToBool", ...) to produce well-typed IR trees.
  const boolBinOps = {boAnd, boOr}
  const cmpBinOps = {boEq, boLt, boLe, boGt, boGe}

  let exprTyp =
    if op in cmpBinOps: irTypeBool()
    elif op in boolBinOps: irTypeBool()
    elif lhs != nil and lhs.typ != nil: lhs.typ
    else: irTypeBitVec64()

  func autoCoerceToBool(e: IRExpr): IRExpr =
    if e != nil and e.typ != nil and e.typ.kind == irtBitVec64:
      IRExpr(typ: irTypeBool(), kind: irCall, callName: "opCastToBool", callArgs: @[e])
    else: e

  let safeLhs = if op in boolBinOps: autoCoerceToBool(lhs) else: lhs
  let safeRhs = if op in boolBinOps: autoCoerceToBool(rhs) else: rhs

  IRExpr(typ: exprTyp, kind: irBinOp, binOp: op, binLhs: safeLhs, binRhs: safeRhs)

func irUnaryOp*(op: UnaryOpKind, arg: IRExpr): IRExpr {.inline.} =
  ## Unary operation.
  let exprTyp = if op == uoNot: irTypeBool()
                elif arg != nil and arg.typ != nil: arg.typ
                else: irTypeBitVec64()
  IRExpr(typ: exprTyp, kind: irUnaryOp, unaryOp: op, unaryArg: arg)

func irCall*(name: string, args: seq[IRExpr]): IRExpr {.inline.} =
  ## Named function call.
  IRExpr(typ: nil, kind: irCall, callName: name, callArgs: args)

func irCall*(name: string, args: seq[IRExpr], retTyp: IRType): IRExpr {.inline.} =
  ## Typed irCall constructor — sets the return type explicitly.
  ## Use for builtin functions where the return type is known.
  IRExpr(typ: retTyp, kind: irCall, callName: name, callArgs: args)

func irRecCall*(args: seq[IRExpr]): IRExpr {.inline.} =
  ## Self-recursive call.
  IRExpr(typ: irTypeBitVec64(), kind: irRecCall, recArgs: args)

func irCase*(scrutinee: IRExpr, branches: seq[CaseBranch],
             default: IRExpr = nil): IRExpr {.inline.} =
  ## Case / pattern match.
  var branchTyp = irTypeBitVec64()
  if branches.len > 0 and branches[0].body != nil and branches[0].body.typ != nil:
    branchTyp = branches[0].body.typ
  elif default != nil and default.typ != nil:
    branchTyp = default.typ
  IRExpr(typ: branchTyp, kind: irCase, caseScrutinee: scrutinee,
         caseBranches: branches, caseDefault: default)

func irLoop*(loopKind: LoopKind, loopVars: seq[string],
             loopInits: seq[IRExpr], loopCond: IRExpr,
             loopStep: IRExpr = nil, loopBody: IRExpr,
             loopInvariants: seq[IRExpr] = @[],
             loopVariant: IRExpr = nil): IRExpr {.inline.} =
  ## Loop with state-passing frame.
  IRExpr(typ: irTypeBitVec64(), kind: irLoop, loopKind: loopKind, loopVars: loopVars,
         loopInits: loopInits, loopCond: loopCond, loopStep: loopStep,
         loopBody: loopBody, loopInvariants: loopInvariants,
         loopVariant: loopVariant)

# ---------------------------------------------------------------------------
# Shortcut constructors (common patterns)
# ---------------------------------------------------------------------------

func irAdd*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boAdd, a, b)

func irSub*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boSub, a, b)

func irMul*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boMul, a, b)

func irDiv*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boDiv, a, b)

func irRem*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boRem, a, b)

func irRemU*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boRemU, a, b)

func irLt*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boLt, a, b)

func irLe*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boLe, a, b)

func irGt*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boGt, a, b)

func irGe*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boGe, a, b)

func irEq*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boEq, a, b)

func irAnd*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boAnd, a, b)

func irOr*(a, b: IRExpr): IRExpr {.inline.} =
  irBinOp(boOr, a, b)

func irNot*(a: IRExpr): IRExpr {.inline.} =
  irUnaryOp(uoNot, a)

func irBvNot*(a: IRExpr): IRExpr {.inline.} =
  irUnaryOp(uoBvNot, a)

func irBvNeg*(a: IRExpr): IRExpr {.inline.} =
  irUnaryOp(uoBvNeg, a)

func irCast*(expr: IRExpr, toSort: IRType): IRExpr {.inline.} =
  ## Explicit type coercion (e.g. BV64→Bool).
  ## Returns expr unchanged if toSort matches expr.typ.
  if expr == nil or expr.typ == nil: return expr
  if expr.typ.kind == toSort.kind: return expr
  IRExpr(typ: toSort, kind: irCast,
         castExpr: expr, castFrom: expr.typ, castTo: toSort)

# ---------------------------------------------------------------------------
# Function definition constructor
# ---------------------------------------------------------------------------

func irFuncDef*(name: string, params: seq[(string, IRType)],
                ret: IRType, body: IRExpr,
                isRec: bool = false): IRFuncDef {.inline.} =
  ## Construct a function definition.
  var ps: seq[IRFuncParam]
  for (n, t) in params:
    ps.add(IRFuncParam(name: n, ty: t))
  IRFuncDef(name: name, params: ps, retType: ret,
            body: body, isRecursive: isRec)

# ---------------------------------------------------------------------------
# Type name helper
# ---------------------------------------------------------------------------

func irTypeName*(t: IRType): string {.inline.} =
  ## Human-readable type name.
  case t.kind
  of irtBitVec64: "BitVec 64"
  of irtBool: "Bool"
  of irtList: "List " & irTypeName(t.elemType)
  of irtString: "String"
  of irtEnum: "Enum " & t.enumName
  of irtVariant: "Variant " & t.variantName

# ---------------------------------------------------------------------------
# Expression pretty-printer
# ---------------------------------------------------------------------------

func binOpSymbol*(op: BinOpKind): string {.inline.} =
  ## SMT-LIB-style operator name.
  case op
  of boAdd: "bvadd"
  of boSub: "bvsub"
  of boMul: "bvmul"
  of boDiv: "bvsdiv"
  of boRem: "bvsrem"
  of boRemU: "bvurem"
  of boShl: "UNSUPPORTED"
  of boShr: "UNSUPPORTED"
  of boUnsupported: "UNSUPPORTED"
  of boLt: "bvslt"
  of boLe: "bvsle"
  of boGt: "bvsgt"
  of boGe: "bvsge"
  of boAnd: "and"
  of boOr: "or"
  of boEq: "="
  of boLtU: "bvult"

func binOpSmt*(op: BinOpKind, lhsTyp, rhsTyp: IRType): string {.inline.} =
  ## Sort-aware SMT-LIB2 operator dispatch.
  ## For boAnd/boOr: if both operands are Bool → and/or,
  ##                  else → bvand/bvor (BitVec64 path).
  ## For arithmetic/comparisons/boEq: standard mapping regardless of sorts.
  case op
  of boAnd:
    if lhsTyp != nil and rhsTyp != nil and
       lhsTyp.kind == irtBool and rhsTyp.kind == irtBool: "and"
    else: "bvand"
  of boOr:
    if lhsTyp != nil and rhsTyp != nil and
       lhsTyp.kind == irtBool and rhsTyp.kind == irtBool: "or"
    else: "bvor"
  of boAdd: "bvadd"
  of boSub: "bvsub"
  of boMul: "bvmul"
  of boDiv: "bvsdiv"
  of boRem: "bvsrem"
  of boRemU: "bvurem"
  of boShl: "UNSUPPORTED"
  of boShr: "UNSUPPORTED"
  of boUnsupported: "UNSUPPORTED"
  of boLt: "bvslt"
  of boLe: "bvsle"
  of boGt: "bvsgt"
  of boGe: "bvsge"
  of boEq: "="
  of boLtU: "bvult"

func unaryOpSymbol*(op: UnaryOpKind): string {.inline.} =
  ## SMT-LIB-style unary operator name.
  case op
  of uoNot: "not"
  of uoBvNot: "bvnot"
  of uoBvNeg: "bvneg"

func `$`*(expr: IRExpr): string =
  ## Debug pretty-printer for IRExpr.
  case expr.kind
  of irLit:
    if expr.litU64 != 0'u64: $expr.litU64
    else: $expr.litVal
  of irFloatLit:
    $expr.floatVal
  of irVar:
    expr.varName & ":" & irTypeName(expr.varType)
  of irLet:
    "(let " & expr.letName & " = " & $expr.letVal & "\n  " & $expr.letBody & ")"
  of irIf:
    "(if " & $expr.ifCond & "\n  then " & $expr.ifThen & "\n  else " & $expr.ifElse & ")"
  of irCase:
    var s = "(case " & $expr.caseScrutinee & "\n"
    for br in expr.caseBranches:
      s.add("  | " & $br.pattern & " => " & $br.body & "\n")
    if expr.caseDefault != nil:
      s.add("  | default => " & $expr.caseDefault & "\n")
    s.add(")")
    s
  of irCall:
    var s = "(" & expr.callName
    for a in expr.callArgs:
      s.add(" " & $a)
    s.add(")")
    s
  of irBinOp:
    "(" & binOpSymbol(expr.binOp) & " " & $expr.binLhs & " " & $expr.binRhs & ")"
  of irUnaryOp:
    "(" & unaryOpSymbol(expr.unaryOp) & " " & $expr.unaryArg & ")"
  of irRecCall:
    var s = "(rec"
    for a in expr.recArgs:
      s.add(" " & $a)
    s.add(")")
    s
  of irLoop:
    var s = "(loop " & $expr.loopKind & " ("
    for i, v in expr.loopVars:
      if i > 0: s.add(" ")
      s.add(v)
    s.add(") (")
    for i, init in expr.loopInits:
      if i > 0: s.add(" ")
      s.add($init)
    s.add(") ")
    s.add($expr.loopCond)
    if expr.loopStep != nil:
      s.add(" ")
      s.add($expr.loopStep)
    else:
      s.add(" nil")
    s.add(" ")
    s.add($expr.loopBody)
    if expr.loopInvariants.len > 0:
      s.add(" [")
      for i, inv in expr.loopInvariants:
        if i > 0: s.add(" ")
        s.add($inv)
      s.add("]")
    if expr.loopVariant != nil:
      s.add(" {variant: " & $expr.loopVariant & "}")
    s.add(")")
    s
  of irStringLit:
    "\"" & expr.stringVal & "\""
  of irCast:
    "(cast:" & $expr.castTo.kind & " " & $expr.castExpr & ")"

# ---------------------------------------------------------------------------
# Tree walks for binding-name collection (shared by semantic_environment
# and external_ir_materializer — both import axiom_ir_helpers).
# ---------------------------------------------------------------------------

func collectLetNames*(e: IRExpr): seq[string] =
  ## Walk the IRExpr tree and collect all irLet.letName values
  ## in traversal order. Duplicates are preserved.
  if e == nil: return @[]
  case e.kind
  of irLet:
    result.add(e.letName)
    result.add collectLetNames(e.letVal)
    result.add collectLetNames(e.letBody)
  of irBinOp:
    result = collectLetNames(e.binLhs)
    result.add collectLetNames(e.binRhs)
  of irUnaryOp:
    result = collectLetNames(e.unaryArg)
  of irIf:
    result = collectLetNames(e.ifCond)
    result.add collectLetNames(e.ifThen)
    result.add collectLetNames(e.ifElse)
  of irCase:
    result = collectLetNames(e.caseScrutinee)
    for br in e.caseBranches:
      result.add collectLetNames(br.body)
    if e.caseDefault != nil:
      result.add collectLetNames(e.caseDefault)
  of irCall:
    for a in e.callArgs:
      result.add collectLetNames(a)
  of irRecCall:
    for a in e.recArgs:
      result.add collectLetNames(a)
  of irLoop:
    for init in e.loopInits:
      result.add collectLetNames(init)
    result.add collectLetNames(e.loopCond)
    if e.loopStep != nil:
      result.add collectLetNames(e.loopStep)
    result.add collectLetNames(e.loopBody)
    for inv in e.loopInvariants:
      result.add collectLetNames(inv)
    if e.loopVariant != nil:
      result.add collectLetNames(e.loopVariant)
  of irCast:
    result = collectLetNames(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    discard

func collectLoopVarNames*(funcDef: IRFuncDef): seq[string] =
  ## Walk funcDef.body and collect all irLoop.loopVars.
  ## Nested loops contribute their loopVars too.
  func walk(e: IRExpr): seq[string] =
    if e == nil: return @[]
    case e.kind
    of irLoop:
      result = e.loopVars
      for init in e.loopInits:
        result.add walk(init)
      result.add walk(e.loopCond)
      if e.loopStep != nil: result.add walk(e.loopStep)
      result.add walk(e.loopBody)
      for inv in e.loopInvariants:
        result.add walk(inv)
      if e.loopVariant != nil: result.add walk(e.loopVariant)
    of irLet:
      result = walk(e.letVal)
      result.add walk(e.letBody)
    of irBinOp:
      result = walk(e.binLhs)
      result.add walk(e.binRhs)
    of irUnaryOp:
      result = walk(e.unaryArg)
    of irIf:
      result = walk(e.ifCond)
      result.add walk(e.ifThen)
      result.add walk(e.ifElse)
    of irCase:
      result = walk(e.caseScrutinee)
      for br in e.caseBranches:
        result.add walk(br.body)
      if e.caseDefault != nil: result.add walk(e.caseDefault)
    of irCall:
      for a in e.callArgs: result.add walk(a)
    of irRecCall:
      for a in e.recArgs: result.add walk(a)
    of irCast:
      result = walk(e.castExpr)
    else: discard
  result = walk(funcDef.body)

func irPretty*(expr: IRExpr): string {.inline.} =
  ## Public alias for the `$` debug pretty-printer.
  $expr

# ---------------------------------------------------------------------------
# Function definition pretty-printer
# ---------------------------------------------------------------------------

func `$`*(def: IRFuncDef): string =
  ## Debug pretty-printer for IRFuncDef.
  var s = "func " & def.name & "("
  for i, p in def.params:
    if i > 0: s.add(", ")
    s.add(p.name & ": " & irTypeName(p.ty))
  s.add("): " & irTypeName(def.retType))
  if def.isRecursive:
    s.add(" [recursive]")
  s.add(" =\n  " & $def.body)
  s

{.pop.}

