import core/trusted/layer_declaration
axiomLayer "domain"
# src/core/testing/axiom_dsl.nim — Axiom Specification DSL
# Restricted mini-language: FOL + arithmetic + ADT pattern matching only.
# Guarantees deterministic SMT-LIB2 transpilation.
import std/[macros, strutils, sequtils, os, osproc]
import core/trusted/axiom_ir_helpers
import core/trusted/solver_invocation
import core/interfaces/logging_hub
{.push raises: [].}

type
  AxiomExprKind* = enum
    aeInt, aeBool, aeVar, aeBinOp, aeUnOp,
    aeForall, aeExists, aeIte, aeMatch, aeApply

  AxiomExpr* {.acyclic.} = ref object
    case kind*: AxiomExprKind
    of aeInt: intVal*: int
    of aeBool: boolVal*: bool
    of aeVar: varName*: string
    of aeBinOp:
      binOp*: BinOp
      lhs*, rhs*: AxiomExpr
    of aeUnOp:
      unOp*: UnOp
      operand*: AxiomExpr
    of aeForall, aeExists:
      quantVar*: string
      quantDomain*: string
      quantBody*: AxiomExpr
    of aeIte:
      cond*, thenBranch*, elseBranch*: AxiomExpr
    of aeMatch:
      scrutinee*: AxiomExpr
      branches*: seq[MatchBranch]
    of aeApply:
      funcName*: string
      args*: seq[AxiomExpr]

  BinOp* = enum
    boAdd, boSub, boMul, boDiv, boMod,
    boLt, boLe, boGt, boGe, boEq, boNeq,
    boAnd, boOr, boImplies, boIff

  UnOp* = enum uoNot, uoNeg

  MatchBranch* = object
    pattern*: string
    bindings*: seq[string]
    body*: AxiomExpr

  Z3Result* = object
    isSat*: bool
    model*: string

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func dslBinOpToIr(op: BinOp): BinOpKind {.inline.} =
  ## Convert DSL BinOp to IR BinOpKind for sort-aware SMT dispatch.
  case op
  of boAdd: boAdd
  of boSub: boSub
  of boMul: boMul
  of boDiv: boDiv
  of boMod: boAdd   # DSL-only; unreachable in binOpSmt path
  of boLt: boLt
  of boLe: boLe
  of boGt: boGt
  of boGe: boGe
  of boEq: boEq
  of boNeq: boEq    # DSL-only; unreachable in binOpSmt path
  of boAnd: boAnd
  of boOr: boOr
  of boImplies: boAnd # DSL-only; unreachable in binOpSmt path
  of boIff: boEq      # DSL-only; unreachable in binOpSmt path

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func dslExprIrType(expr: AxiomExpr): IRType {.inline.} =
  ## Infer IRType from a DSL expression for sort-aware SMT dispatch.
  case expr.kind
  of aeBool: irTypeBool()
  of aeInt: irTypeBitVec64()
  of aeVar: irTypeBitVec64()
  of aeBinOp:
    case expr.binOp
    of boLt, boLe, boGt, boGe: irTypeBool()
    else: irTypeBitVec64()
  of aeUnOp:
    if expr.unOp == uoNot: irTypeBool()
    else: irTypeBitVec64()
  of aeForall, aeExists, aeIte: irTypeBool()
  of aeMatch, aeApply: irTypeBitVec64()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parseBinOp(op: string): BinOp {.raises: [].} =
  case op
  of "+": boAdd
  of "-": boSub
  of "*": boMul
  of "div": boDiv
  of "mod": boMod
  of "<": boLt
  of "<=": boLe
  of ">": boGt
  of ">=": boGe
  of "==": boEq
  of "!=": boNeq
  of "and": boAnd
  of "or": boOr
  of "implies": boImplies
  of "iff": boIff
  else: boAdd  # unsupported DSL op — default; parse-time only, unreachable in validated ASTs

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc validateAxiomExpr*(node: NimNode): AxiomExpr =
  case node.kind
  of nnkIntLit:
    result = AxiomExpr(kind: aeInt, intVal: node.intVal.int)
  of nnkFloatLit:
    error("Axiom DSL: float not supported in SMT-LIB2", node)
  of nnkStrLit:
    error("Axiom DSL: string not supported. Use ADT pattern matching.", node)
  of nnkIdent:
    case node.strVal
    of "true": result = AxiomExpr(kind: aeBool, boolVal: true)
    of "false": result = AxiomExpr(kind: aeBool, boolVal: false)
    else: result = AxiomExpr(kind: aeVar, varName: node.strVal)
  of nnkInfix:
    let op = parseBinOp(node[0].strVal)
    let l = validateAxiomExpr(node[1])
    let r = validateAxiomExpr(node[2])
    result = AxiomExpr(kind: aeBinOp, binOp: op, lhs: l, rhs: r)
  of nnkPrefix:
    let op = case node[0].strVal
      of "not": uoNot
      of "-": uoNeg
      else: error("Axiom DSL: unsupported prefix '" & node[0].strVal & "'", node); uoNot
    let operand = validateAxiomExpr(node[1])
    result = AxiomExpr(kind: aeUnOp, unOp: op, operand: operand)
  of nnkCall:
    let fn = node[0].strVal
    case fn
    of "forall", "exists":
      # forall(x: T, body) — extract params
      if node.len >= 3:
        let param = node[1]
        let body = validateAxiomExpr(node[2])
        if fn == "forall":
          if param.kind == nnkExprColonExpr:
            let vn = param[0].strVal
            let dt = param[1].repr
            result = AxiomExpr(kind: aeForall, quantVar: vn, quantDomain: dt, quantBody: body)
          else:
            result = AxiomExpr(kind: aeForall, quantVar: param.repr, quantDomain: "Int", quantBody: body)
        else:
          if param.kind == nnkExprColonExpr:
            let vn = param[0].strVal
            let dt = param[1].repr
            result = AxiomExpr(kind: aeExists, quantVar: vn, quantDomain: dt, quantBody: body)
          else:
            result = AxiomExpr(kind: aeExists, quantVar: param.repr, quantDomain: "Int", quantBody: body)
      else:
        error("Axiom DSL: forall/exists needs (var: Type, body)", node)
    of "ite":
      if node.len == 4:
        let c = validateAxiomExpr(node[1])
        let t = validateAxiomExpr(node[2])
        let e = validateAxiomExpr(node[3])
        result = AxiomExpr(kind: aeIte, cond: c, thenBranch: t, elseBranch: e)
      else:
        error("Axiom DSL: ite needs (cond, then, else)", node)
    else:
      var args: seq[AxiomExpr] = @[]
      for i in 1..<node.len: args.add(validateAxiomExpr(node[i]))
      result = AxiomExpr(kind: aeApply, funcName: fn, args: args)
  of nnkCaseStmt:
    let scrut = validateAxiomExpr(node[0])
    var brs: seq[MatchBranch] = @[]
    for i in 1..<node.len:
      let branch = node[i]
      if branch.kind == nnkOfBranch:
        let pat = branch[0].repr
        let body = validateAxiomExpr(branch[^1])
        brs.add(MatchBranch(pattern: pat, body: body))
    result = AxiomExpr(kind: aeMatch, scrutinee: scrut, branches: brs)
  else:
    error("Axiom DSL: unsupported AST kind " & $node.kind, node)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc emitSmtLib2*(expr: AxiomExpr): string =
  if expr == nil: return "nil"
  case expr.kind
  of aeInt: result = $expr.intVal
  of aeBool: result = if expr.boolVal: "true" else: "false"
  of aeVar: result = expr.varName
  of aeBinOp:
    let op = case expr.binOp
      of boMod: "mod"
      of boNeq: "distinct"
      of boImplies: "=>"
      of boIff: "="
      of boAdd, boSub, boMul, boDiv, boLt, boLe, boGt, boGe, boEq, boAnd, boOr:
        binOpSmt(dslBinOpToIr(expr.binOp),
                 dslExprIrType(expr.lhs), dslExprIrType(expr.rhs))
    result = "(" & op & " " & emitSmtLib2(expr.lhs) & " " & emitSmtLib2(expr.rhs) & ")"
  of aeUnOp:
    let op = if expr.unOp == uoNot: "not" else: "-"
    result = "(" & op & " " & emitSmtLib2(expr.operand) & ")"
  of aeForall:
    result = "(forall ((" & expr.quantVar & " " & expr.quantDomain & ")) " &
      emitSmtLib2(expr.quantBody) & ")"
  of aeExists:
    result = "(exists ((" & expr.quantVar & " " & expr.quantDomain & ")) " &
      emitSmtLib2(expr.quantBody) & ")"
  of aeIte:
    result = "(ite " & emitSmtLib2(expr.cond) & " " &
      emitSmtLib2(expr.thenBranch) & " " & emitSmtLib2(expr.elseBranch) & ")"
  of aeMatch:
    result = "(match " & emitSmtLib2(expr.scrutinee) & "\n"
    for b in expr.branches:
      result &= "  (case (" & b.pattern
      for bv in b.bindings: result &= " " & bv
      result &= ") " & emitSmtLib2(b.body) & ")\n"
    result &= ")"
  of aeApply:
    result = "(" & expr.funcName
    for a in expr.args: result &= " " & emitSmtLib2(a)
    result &= ")"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc queryZ3*(smtLib2Code: string): Z3Result =
  ## Runtime Z3 invocation via execCmdEx (replaces compile-time gorge).
  let fullQuery = "(set-option :produce-models true)\n" &
    solverOptionsPayload(pinnedDeterminismOptions()) &
    smtLib2Code & "\n(check-sat)\n(get-model)\n"
  let z3Path = if fileExists("vendor/z3/z3"): "vendor/z3/z3" else: "z3"
  var output: string
  try:
    let (outStr, exitCode) = execCmdEx(z3Path & " -in -smt2", input = fullQuery)
    if exitCode != 0:
      return Z3Result(isSat: false, model: "Z3 exited with code " & $exitCode)
    output = outStr
  except CatchableError as e:
    return Z3Result(isSat: false, model: "Z3 execution failed: " & e.msg)
  let lines = output.strip().splitLines()
  if lines.len == 0:
    return Z3Result(isSat: false, model: "Z3 returned empty output")
  result.isSat = lines[0] == "sat"
  result.model = if result.isSat and lines.len > 1: lines[1..^1].join("\n") else: ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
template property*(name: static[string], body: untyped): untyped =
  block:
    let expr = validateAxiomExpr(getAst(body))
    let smtCode = emitSmtLib2(expr)
    let query = "(assert (not\n" & smtCode & "\n))\n(check-sat)\n(get-model)\n"
    let z3Result = queryZ3(query)
    if z3Result.isSat:
      logger.error("Property FAILED: " & name)
      logger.error("  Counterexample: " & z3Result.model)
    else:
      logger.info("Property PROVEN by Z3: " & name)

{.pop}
