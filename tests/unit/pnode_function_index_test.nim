## Regression tests for the per-module ProcDef index (commit a3f5c80d).
##
## Pins that findIndexedFunctionNode(buildFunctionNodeIndexP(ast), name) agrees
## with the reference findFunctionNode(ast, name) on REAL parsed Nim source
## (commit a3f5c80d replaced a per-symbol walk with one index per module), and
## pins the index's contract details: first-declaration-wins on duplicates,
## strip + toLowerAscii normalization at both construction and lookup, misses,
## empty modules, and {.axiomImpl.} resolution through the indexed node.
##
## Current contract detail pinned as-is: declarationNameP takes the FIRST
## nkIdent inside the declaration's name node. For an exported declaration the
## name node is nkPostfix [nkIdent("*"), nkIdent("name")], so the index key is
## "*" — the reference walk applies the same rule, hence both paths agree on
## "*" and both miss the bare exported name. This predates the index commit.

import std/[options, tables, unittest]

import compiler/ast

import core/parser_utils
import core/results
import core/parsers/pnode_nav

const SampleModule = """
proc plainProc(x: int): int =
  x + 1

func plainFunc(x: int): int =
  x * 2

method plainMethod(x: int): string =
  "m"

iterator plainIterator(n: int): int =
  var i = 0
  while i < n:
    yield i
    inc i

template plainTemplate(x: int): int =
  x * 3

macro plainMacro(x: untyped): untyped =
  x

proc exportedProc*(x: int): int =
  x - 1
"""

proc parseOrFail(source: string): PNode =
  let parsed = parseNimRes(source)
  if parsed.isErr:
    raise newException(ValueError, "parseNimRes failed: " & parsed.error)
  parsed.get

func firstIdentName(node: PNode): string =
  ## Test-side mirror of the reference extraction rule (first nkIdent of the
  ## declaration's name node) — the name under which a declaration is keyed.
  let nameOpt = findFirstNodeP(node[0], {nkIdent})
  if nameOpt.isSome: nameOpt.get.ident.s else: ""

func declaredName(node: PNode): string =
  ## Declared name including the real identifier of an exported (nkPostfix)
  ## declaration, whose name node is [nkIdent("*"), nkIdent("name")].
  if node[0].kind == nkPostfix:
    if node[0].len > 1: node[0][1].ident.s else: ""
  else:
    firstIdentName(node)

func lineOf(node: PNode): int =
  int(node.info.line)

proc checkSameNode(a, b: PNode) =
  check a.kind == b.kind
  check lineOf(a) == lineOf(b)
  check firstIdentName(a) == firstIdentName(b)

suite "ProcDef index equivalence (findIndexedFunctionNode vs findFunctionNode)":

  test "agrees for every declaration kind in a real module":
    let tree = parseOrFail(SampleModule)
    let index = buildFunctionNodeIndexP(tree)

    var seenKinds: set[TNodeKind] = {}
    var checked = 0
    for decl in findNodesP(tree, ProcDefKinds):
      seenKinds.incl(decl.kind)
      let lookup = firstIdentName(decl)
      check lookup.len > 0
      let refOpt = findFunctionNode(tree, lookup)
      let idxOpt = findIndexedFunctionNode(index, lookup)
      check refOpt.isSome
      check idxOpt.isSome
      if refOpt.isSome and idxOpt.isSome:
        checkSameNode(refOpt.get, idxOpt.get)
      inc checked

    check checked == 7
    for kind in [nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef,
                 nkTemplateDef, nkMacroDef]:
      check kind in seenKinds

    # Exported declaration is present and indexed under the first-nkIdent rule.
    check index.len == 7
    for key in ["plainproc", "plainfunc", "plainmethod", "plainiterator",
                "plaintemplate", "plainmacro", "*"]:
      check index.hasKey(key)

  test "exported declaration: both paths agree on '*' (not the bare name)":
    let tree = parseOrFail(SampleModule)
    let index = buildFunctionNodeIndexP(tree)

    let refExport = findFunctionNode(tree, "*")
    let idxExport = findIndexedFunctionNode(index, "*")
    check refExport.isSome
    check idxExport.isSome
    if refExport.isSome and idxExport.isSome:
      checkSameNode(refExport.get, idxExport.get)
      check declaredName(refExport.get) == "exportedProc"
      check declaredName(idxExport.get) == "exportedProc"

    # Pre-existing contract quirk: the bare exported name misses both paths.
    check findFunctionNode(tree, "exportedProc").isNone
    check findIndexedFunctionNode(index, "exportedProc").isNone

  test "duplicate declarations: both paths return the FIRST declaration":
    let source = """
proc duplicated(x: int): int =
  x

proc duplicated(x: int): int =
  x + 100
"""
    let tree = parseOrFail(source)
    let decls = findNodesP(tree, {nkProcDef})
    check decls.len == 2

    let index = buildFunctionNodeIndexP(tree)
    check index.len == 1

    let refOpt = findFunctionNode(tree, "duplicated")
    let idxOpt = findIndexedFunctionNode(index, "duplicated")
    check refOpt.isSome
    check idxOpt.isSome
    if refOpt.isSome and idxOpt.isSome:
      checkSameNode(refOpt.get, idxOpt.get)
      check lineOf(refOpt.get) == lineOf(decls[0])
      check lineOf(idxOpt.get) == lineOf(decls[0])
      check lineOf(refOpt.get) != lineOf(decls[1])

  test "normalization: case and surrounding whitespace match both paths":
    let source = """
func camelCaseName(value: int): int =
  value
"""
    let tree = parseOrFail(source)
    let index = buildFunctionNodeIndexP(tree)
    check index.hasKey("camelcasename")

    for query in ["CAMELCASENAME", "CamelCaseName", "  camelCaseName  ",
                  "\tcamelcasename\n"]:
      let refOpt = findFunctionNode(tree, query)
      let idxOpt = findIndexedFunctionNode(index, query)
      check refOpt.isSome
      check idxOpt.isSome
      if refOpt.isSome and idxOpt.isSome:
        checkSameNode(refOpt.get, idxOpt.get)

  test "absent name returns none from both paths":
    let tree = parseOrFail(SampleModule)
    let index = buildFunctionNodeIndexP(tree)

    check findFunctionNode(tree, "doesNotExist").isNone
    check findIndexedFunctionNode(index, "doesNotExist").isNone
    check findFunctionNode(tree, "  PLAINPROC  EXTRA").isNone
    check findIndexedFunctionNode(index, "  PLAINPROC  EXTRA").isNone

  test "zero-proc module: index is empty and lookup returns none":
    let source = """
const answer = 42

type Holder = object
  value: int
"""
    let tree = parseOrFail(source)
    let index = buildFunctionNodeIndexP(tree)

    check index.len == 0
    check findIndexedFunctionNode(index, "answer").isNone
    check findIndexedFunctionNode(index, "holder").isNone
    check findFunctionNode(tree, "answer").isNone

  test "axiomImpl pragma is resolved through the indexed node":
    let source = """
proc certified(x: int): int {.axiomImpl.} =
  x

proc uncertified(x: int): int =
  x
"""
    let tree = parseOrFail(source)
    let index = buildFunctionNodeIndexP(tree)

    let refOpt = findFunctionNode(tree, "certified")
    let idxOpt = findIndexedFunctionNode(index, "certified")
    check refOpt.isSome
    check idxOpt.isSome
    if refOpt.isSome and idxOpt.isSome:
      checkSameNode(refOpt.get, idxOpt.get)
      check hasPragmaNamedP(idxOpt.get, "axiomImpl")
      check hasPragmaNamedP(refOpt.get, "axiomImpl")

    let plainOpt = findIndexedFunctionNode(index, "uncertified")
    check plainOpt.isSome
    if plainOpt.isSome:
      check not hasPragmaNamedP(plainOpt.get, "axiomImpl")