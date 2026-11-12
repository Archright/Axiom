import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## S-Expression Types — DAG leaf module
##
## Vertical-slice extraction from smt_to_lean_codegen.nim.
## Contains the SExprNode type and its parser, with zero dependencies
## on other core/encoding modules (stdlib only).

import std/strutils
import ../../core/trusted/axiom_pragmas

# ---------------------------------------------------------------------------
# S-Expression AST
# ---------------------------------------------------------------------------

type
  SExprNode* = object
    atom*: string
    children*: seq[SExprNode]
    isList*: bool

## Consume one s-expression from the beginning of raw text.
## Returns the consumed expression and the remainder.
func consumeSExpr*(raw: string): tuple[node: SExprNode; remainder: string] {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (= (str.len trimmed) 0) (< firstSpace 0) (= depth 0) (< (+ idx 1) (str.len trimmed)) (> (str.len cursor) 0) (>= (str.len raw) 0)))", "raw.length ≥ 0 ∧ trimmed.length = 0 ∧ firstSpace < 0 ∧ depth = 0 ∧ idx + 1 < trimmed.length ∧ cursor.length > 0 ∧ raw.length ≥ 0"].} =
  let trimmed = raw.strip()
  if trimmed.len == 0:
    return (SExprNode(isList: false, atom: ""), "")
  if trimmed[0] != '(':
    let firstSpace = trimmed.find({' ', '\t', '\n', '\r'})
    if firstSpace < 0:
      return (SExprNode(isList: false, atom: trimmed), "")
    return (
      SExprNode(isList: false, atom: trimmed[0 ..< firstSpace]),
      trimmed[firstSpace .. ^1].strip()
    )
  var depth = 0
  for idx, ch in trimmed:
    if ch == '(':
      inc depth
    elif ch == ')':
      dec depth
      if depth == 0:
        let inner = trimmed[1 ..< idx].strip()
        let remainder =
          if idx + 1 < trimmed.len: trimmed[idx + 1 .. ^1].strip()
          else: ""
        var children: seq[SExprNode] = @[]
        var cursor = inner
        while cursor.len > 0:
          let childRes = consumeSExpr(cursor)
          if childRes.node.atom.len == 0 and not childRes.node.isList and childRes.remainder.len == 0:
            break
          children.add(childRes.node)
          cursor = childRes.remainder
        return (SExprNode(isList: true, children: children), remainder)
  (SExprNode(isList: false, atom: trimmed), "")

## Parse a complete s-expression string into an AST.
func parseSExpr*(raw: string): SExprNode {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0)))", "raw.length ≥ 0"].} =
  let res = consumeSExpr(raw)
  res.node

{.pop.}
