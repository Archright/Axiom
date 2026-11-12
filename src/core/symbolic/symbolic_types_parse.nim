import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/parsers/safe_parsers
import core/parsers/pnode_nav
import compiler/ast
import core/types/results
import core/symbolic/symbolic_types_expr
import std/options
import std/strutils

type
  SymOperator* = enum
    symOpAdd
    symOpSub
    symOpMul
    symOpEq
    symOpLt
    symOpLe
    symOpGt
    symOpGe

  BinSymOp = proc(a, b: SymSExpr): SymSExpr {.nimcall, noSideEffect, raises: [].}

func parseSymOperator*(opName: string): Option[SymOperator] {.raises: [].} =
  case opName
  of "+": result = some(symOpAdd)
  of "-": result = some(symOpSub)
  of "*": result = some(symOpMul)
  of "==": result = some(symOpEq)
  of "<": result = some(symOpLt)
  of "<=": result = some(symOpLe)
  of ">": result = some(symOpGt)
  of ">=": result = some(symOpGe)
  else: result = none[SymOperator]()

func handleSymOpAdd(a, b: SymSExpr): SymSExpr {.raises: [].} = sAdd(a, b)
func handleSymOpSub(a, b: SymSExpr): SymSExpr {.raises: [].} = sSub(a, b)
func handleSymOpMul(a, b: SymSExpr): SymSExpr {.raises: [].} = sMul(a, b)
func handleSymOpEq(a, b: SymSExpr): SymSExpr {.raises: [].} = sEq(a, b)
func handleSymOpLt(a, b: SymSExpr): SymSExpr {.raises: [].} = sLt(a, b)
func handleSymOpLe(a, b: SymSExpr): SymSExpr {.raises: [].} = sLe(a, b)
func handleSymOpGt(a, b: SymSExpr): SymSExpr {.raises: [].} = sGt(a, b)
func handleSymOpGe(a, b: SymSExpr): SymSExpr {.raises: [].} = sGe(a, b)

const dispatchTable: array[SymOperator, BinSymOp] = [
  symOpAdd: handleSymOpAdd,
  symOpSub: handleSymOpSub,
  symOpMul: handleSymOpMul,
  symOpEq: handleSymOpEq,
  symOpLt: handleSymOpLt,
  symOpLe: handleSymOpLe,
  symOpGt: handleSymOpGt,
  symOpGe: handleSymOpGe,
]

static:
  doAssert dispatchTable.len == ord(high(SymOperator)) + 1

## PNode-compatible extractIdentifierName
func extractIdentifierNameP*(node: PNode): string {.raises: [].} =
  if node.isNil: return ""
  if node.kind in {nkIdent, nkSym}:
    return if node.kind == nkIdent: node.ident.s else: node.sym.name.s
  # Leaf/literal nodes have no children — iterating sons raises Defect.
  if node.kind in {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
                   nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
                   nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
                   nkStrLit, nkTripleStrLit, nkCharLit, nkNilLit, nkCommentStmt,
                   nkNone}:
    return ""
  for child in node:
    if not child.isNil and child.kind in {nkIdent, nkSym}:
      return if child.kind == nkIdent: child.ident.s else: child.sym.name.s
  ""

## PNode-compatible nimExprToSymSExpr
func nimExprToSymSExprP*(node: PNode): Result[SymSExpr, string] {.raises: [].} =
  if node.isNil:
    return err("nil node")
  case node.kind
  of nkIdent, nkSym:
    let name = if node.kind == nkIdent: node.ident.s else: node.sym.name.s
    let parsed = safeParseInt(name)
    if parsed.isOk: return ok(sConst(parsed.get))
    return ok(sVar(name))
  of nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit, nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit:
    let text = $node.intVal
    let parsed = safeParseInt(text)
    if parsed.isOk: return ok(sConst(parsed.get))
    return err("invalid integer: " & text)
  of nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit:
    let text = $node.floatVal
    let parsed = safeParseFloat(text)
    if parsed.isOk: return ok(sConst(int(parsed.get)))
    return ok(sVar(text))
  of nkInfix:
    if node.len > 1 and not node[1].isNil:
      let opText = pNodeText(node[1]).toLowerAscii()
      let opEnum = parseSymOperator(opText)
      if opEnum.isSome:
        if node.len > 0 and not node[0].isNil and node.len > 2 and not node[2].isNil:
          let lhs = nimExprToSymSExprP(node[0])
          let rhs = nimExprToSymSExprP(node[2])
          if lhs.isErr(): return err(lhs.error())
          if rhs.isErr(): return err(rhs.error())
          return ok(dispatchTable[opEnum.get()](lhs.get(), rhs.get()))
        return err("infix requires 2 operands")
      return err("unsupported operator: " & opText)
    return err("malformed infix expression")
  of nkCall:
    if node.len > 0 and not node[0].isNil:
      let callName = pNodeText(node[0]).toLowerAscii()
      let opEnum = parseSymOperator(callName)
      if opEnum.isSome:
        var args: seq[PNode] = @[]
        for i in 1 ..< node.len:
          if not node[i].isNil: args.add(node[i])
        if args.len != 2:
          return err("binary " & callName & " requires 2 args")
        let lhs = nimExprToSymSExprP(args[0])
        let rhs = nimExprToSymSExprP(args[1])
        if lhs.isErr(): return err(lhs.error())
        if rhs.isErr(): return err(rhs.error())
        return ok(dispatchTable[opEnum.get()](lhs.get(), rhs.get()))
      return err("call without name")
    return err("malformed call")
  else:
    # Try to get text content as fallback
    let text = pNodeText(node).strip()
    if text.len == 0:
      return err("empty node")
    let parsed = safeParseInt(text)
    if parsed.isOk: return ok(sConst(parsed.get))
    return ok(sVar(text))

{.pop.}

