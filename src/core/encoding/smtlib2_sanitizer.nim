import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.pragma: axiomPure.}
{.push noSideEffect.}
import std/strutils
import std/tables
import core/types/results
import core/encoding/smt_types

## Convert an S-Expression AST back to its string representation.
func sexprToString(node: SExprNode): string {.raises: [].} =
  if not node.isList:
    return node.atom
  result = "("
  for i, child in node.children:
    if i > 0: result.add(" ")
    result.add(sexprToString(child))
  result.add(")")

## Infer the SMT type of an S-Expression node using declared parameter types.
func inferSmtType(node: SExprNode; declTypes: Table[string, string]): string {.raises: [].} =
  if not node.isList:
    if node.atom == "true" or node.atom == "false":
      return "Bool"
    if node.atom.len > 0 and node.atom[0].isDigit:
      return "Int"
    if declTypes.hasKey(node.atom):
      return declTypes.getOrDefault(node.atom, "")
    return ""
  if node.children.len == 0:
    return ""
  let op = node.children[0].atom
  if op == "str.len" or op == "seq.len":
    return "Int"
  if op in ["and", "or", "not", "=>", ">=", "<", ">", "<=", "="]:
    return "Bool"
  return ""

## Type Purity Filter: sanitize an S-Expression by rewriting
## garbage-in patterns into well-typed equivalents.
##
## Pattern 1: numeric literal in and/or context -> (not (= literal 0))
##   KEPT: semantic-preserving coercion (truthy/falsy), not vacuous.
## Pattern 2: Bool in numeric comparison           -> err (fail-closed)
## Pattern 3: incompatible type equality           -> err (fail-closed)
func sanitizeSmtExpr(node: SExprNode; declTypes: Table[string, string]): Result[SExprNode, string] {.raises: [].} =
  if not node.isList:
    return ok(node)
  if node.children.len == 0:
    return ok(node)
  let op = node.children[0].atom

  # Pattern 1 — semantic coercion, keep
  if op in ["and", "or"] and node.children.len >= 2:
    var newChildren: seq[SExprNode] = @[]
    newChildren.add(node.children[0])
    for i in 1 ..< node.children.len:
      let child = node.children[i]
      if not child.isList and child.atom.len > 0 and child.atom[0].isDigit:
        newChildren.add(SExprNode(
          isList: true,
          children: @[
            SExprNode(isList: false, atom: "not"),
            SExprNode(isList: true, children: @[
              SExprNode(isList: false, atom: "="),
              SExprNode(isList: false, atom: child.atom),
              SExprNode(isList: false, atom: "0")
            ])
          ]
        ))
      else:
        let childRes = sanitizeSmtExpr(child, declTypes)
        if childRes.isErr: return err(childRes.error)
        newChildren.add(childRes.get)
    return ok(SExprNode(isList: true, children: newChildren))

  # Pattern 2 — Bool operand in numeric comparison: fail-closed
  if op in [">=", "<", ">", "<="] and node.children.len >= 3:
    let leftType = inferSmtType(node.children[1], declTypes)
    let rightType = inferSmtType(node.children[2], declTypes)
    if leftType == "Bool" or rightType == "Bool":
      return err("ill-typed-smt: " & op & " " & leftType & " vs " & rightType)

  # Pattern 3 — mismatched types in equality: fail-closed
  if op == "=" and node.children.len >= 3:
    let leftType = inferSmtType(node.children[1], declTypes)
    let rightType = inferSmtType(node.children[2], declTypes)
    if leftType.len > 0 and rightType.len > 0 and leftType != rightType:
      return err("ill-typed-smt: " & op & " " & leftType & " vs " & rightType)

  # Recurse into children
  var newChildren: seq[SExprNode] = @[]
  for child in node.children:
    let childRes = sanitizeSmtExpr(child, declTypes)
    if childRes.isErr: return err(childRes.error)
    newChildren.add(childRes.get)
  return ok(SExprNode(isList: true, children: newChildren))

## Sanitize a full SMT-LIB2 assert string.
func sanitizeSmtAssert*(assertStr: string; declTypes: Table[string, string]): Result[string, string] {.raises: [].} =
  let sexpr = parseSExpr(assertStr)
  if not sexpr.isList or sexpr.children.len < 2 or sexpr.children[0].atom != "assert":
    return ok(assertStr)
  let sanitizedRes = sanitizeSmtExpr(sexpr.children[1], declTypes)
  if sanitizedRes.isErr: return err(sanitizedRes.error)
  let sanitized = sanitizedRes.get
  return ok("(assert " & sexprToString(sanitized) & ")")

{.pop.}
{.pop.}
