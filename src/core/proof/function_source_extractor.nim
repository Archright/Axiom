## Function Source Extractor
##
## Deterministically extracts a single function/proc/func/method declaration
## from full Nim source code using tree-sitter XML span attributes.
##
## This is the first step of Compiler-Integrated Type-Directed Proposition
## Synthesis: the AST gives the exact source span, so downstream VC generation
## cannot accidentally consume unrelated code or domain templates.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/options
import std/strutils
import core/parser_utils
import core/parsers/pnode_nav
import compiler/ast
{.push raises: [].}
# axiomIoBoundary

func lineStartOffsets(s: string): seq[int] {.raises: [].} =
  ## Build a table of byte offsets where each source line begins.
  result.add(0)
  var i = 0
  while i < s.len:
    if s[i] == '\n':
      result.add(i + 1)
    inc i

func sourceSlice*(sourceCode: string; srow, scol, erow, ecol: int): Option[string] {.raises: [].} =
  ## Extract a source substring from 0-based row/column coordinates.
  if srow < 0 or scol < 0 or erow < 0 or ecol < 0:
    return none(string)
  let offsets = lineStartOffsets(sourceCode)
  if srow >= offsets.len or erow >= offsets.len:
    return none(string)
  let startOffset = offsets[srow] + scol
  let endOffset = min(offsets[erow] + ecol, sourceCode.len)
  if endOffset <= startOffset:
    return none(string)
  some(sourceCode[startOffset ..< endOffset])

func findNamedDeclaration*(ast: PNode; functionName: string): Option[PNode] {.raises: [].} =
  ## Locate a declaration whose identifier matches `functionName` (case-insensitive).
  ## PNode version using compiler AST node kinds.
  if ast.isNil: return none(PNode)
  let target = functionName.strip().toLowerAscii()
  for decl in findNodesP(ast, ProcDefKinds):
    if decl.len > 0 and not decl[0].isNil:
      let nameNodeOpt = findFirstNodeP(decl[0], {nkIdent, nkSym})
      if nameNodeOpt.isSome:
        let name = pNodeText(nameNodeOpt.get)
        if name.strip().toLowerAscii() == target:
          return some(decl)
  none(PNode)

func nodeSpanP(node: PNode): tuple[srow, scol, erow, ecol: int] {.raises: [].} =
  ## Approximate source span from PNode line info.
  ## The Nim compiler AST keeps only the start position; the end line is
  ## derived from the deepest descendant's line info.
  let srow = max(int(node.info.line) - 1, 0)
  let scol = int(node.info.col)
  var erow = srow
  proc maxLine(n: PNode) =
    if n.isNil:
      return
    let ln = int(n.info.line)
    if ln > erow:
      erow = ln
    # Leaf/literal nodes have no children — iterating sons raises Defect
    # (same invariant B4-A enforced in pnode_nav.nim).
    if n.kind in {nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
                  nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
                  nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit,
                  nkStrLit, nkTripleStrLit, nkCharLit, nkNilLit, nkCommentStmt,
                  nkNone}:
      return
    for child in n:
      maxLine(child)
  maxLine(node)
  (srow, scol, erow, 0)

proc extractFunctionSource*(sourceCode, functionName: string): Option[string] =
  ## Extract the exact source text of `functionName` from `sourceCode`.
  ## Returns none if parsing fails or the function is not found.
  ## Uses Nim compiler AST (PNode) via parser_utils.
  let ast = parseStringAST(sourceCode)
  if ast.isNil:
    return none(string)
  let declOpt = findNamedDeclaration(ast, functionName)
  if declOpt.isNone():
    return none(string)
  let (srow, scol, erow, ecol) = nodeSpanP(declOpt.get)
  sourceSlice(sourceCode, srow, scol, erow, ecol)

{.pop}
