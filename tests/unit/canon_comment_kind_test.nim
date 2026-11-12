## tests/unit/canon_comment_kind_test.nim
## `toCanonKind` (PNode frontend) and `nimKindToCanon` (NimNode frontend) are
## two tables that must name the same canonical kind for the same source
## construct. They disagreed on `nkCommentStmt`: the NimNode table mapped it to
## `ckCommentStmt`, the PNode table fell through to `ckUnknown`.
##
## A `ckUnknown` statement node is not neutral in ast_to_ir's body converter —
## it is the arm that records a translation loss, so a documentation comment
## made every documented function look lossy and every such candidate failed
## the proposition-region gate. This file pins the agreement and pins the
## property that matters: a doc comment changes nothing a caller can observe.

import std/[macros, sequtils, unittest]
import compiler/[ast, idents]
import core/parser_utils
import core/trusted/pnode_to_canon
import core/trusted/ast_to_ir
import core/trusted/axiom_ir
import shared/canonical_ast

const Documented = """
func documented(a: int): int =
  ## A doc comment describing the function.
  let b = a + 1
  b + 1
"""

const Undocumented = """
func documented(a: int): int =
  let b = a + 1
  b + 1
"""

func hasNoSons(nk: TNodeKind): bool =
  ## The kinds pnodeToCanon refuses to index: `sons` is not accessible on these.
  ## nkCommentStmt is NOT one of them — a comment node is indexable and simply
  ## has no children.
  nk in {nkEmpty, nkIdent, nkSym, nkCharLit,
         nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
         nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit,
         nkTripleStrLit, nkNilLit}

func collectCommentNodes(root: PNode): seq[PNode] =
  var stack: seq[PNode] = @[root]
  while stack.len > 0:
    let n = stack.pop()
    if n.isNil or hasNoSons(n.kind): continue
    if n.kind == nkCommentStmt: result.add n
    for i in 0 ..< n.len:
      stack.add(n[i])

func canonicalComments(root: CanonNode): seq[CanonNode] =
  if root.kind == ckCommentStmt: result.add root
  for i in 0 ..< getChildCount(root):
    result.add canonicalComments(getChild(root, i))

proc funcDefOf(fixture: string): IRFuncDef =
  let ast = parseStringAST(fixture)
  check not ast.isNil
  let defNode = findFuncDefP(ast, "documented", "")
  check not defNode.isNil
  axiomBodyCanon(pnodeToCanon(defNode))

suite "pnode_to_canon: comment kind agrees with nimKindToCanon":

  test "a doc comment is a ckCommentStmt, not a ckUnknown":
    # The parser really does emit nkCommentStmt for `##`; the fixture is not
    # vacuously passing because there is nothing to convert.
    let ast = parseStringAST(Documented)
    let defNode = findFuncDefP(ast, "documented", "")
    check not defNode.isNil
    let comments = collectCommentNodes(defNode)
    check comments.len == 1
    check pnodeToCanon(comments[0]).kind == ckCommentStmt
    check pnodeToCanon(comments[0]).kind != ckUnknown

  test "the two frontends name the same kind for a comment":
    check nimKindToCanon(nnkCommentStmt) == ckCommentStmt
    check pnodeToCanon(collectCommentNodes(
      findFuncDefP(parseStringAST(Documented), "documented", ""))[0]).kind ==
        nimKindToCanon(nnkCommentStmt)

  test "the comment survives pnodeToCanon as its own node":
    let ast = parseStringAST(Documented)
    let canon = pnodeToCanon(findFuncDefP(ast, "documented", ""))
    check canonicalComments(canon).len == 1

  test "a doc comment changes nothing a caller can observe":
    # translationLossFree, the scoped evidence and the recorded bindings are
    # all identical with and without the comment. This is the property the
    # mismatch broke: a comment is not a statement form, it holds no
    # declaration, and nothing downstream may be able to tell it was there.
    let withDoc = funcDefOf(Documented)
    let withoutDoc = funcDefOf(Undocumented)
    check serializeIRFuncDef(withDoc) == serializeIRFuncDef(withoutDoc)
    check withDoc.propositionRegionLossFree == withoutDoc.propositionRegionLossFree
    check withDoc.lossOutsideBindingRegions == withoutDoc.lossOutsideBindingRegions
    check withDoc.translationLossFree == withoutDoc.translationLossFree
    check withDoc.recordedBindings.len == withoutDoc.recordedBindings.len
    check withDoc.recordedBindings.mapIt(it.name) ==
          withoutDoc.recordedBindings.mapIt(it.name)
    check withDoc.recordedBindings.allIt(it.lossFree)
    # The comment is a leaf: it is recorded as a loss of the leaf, never as a
    # dropped statement region, because a region drop would say bindings below
    # it are missing when it has none.
    check withDoc.propositionRegionLossFree