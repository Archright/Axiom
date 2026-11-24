## Pins the per-module declaration index that replaced the per-symbol AST walk
## in `enrichAxiomImplFlags`. The index is an optimization only: it must resolve
## exactly the names the linear `findFunctionNodeP` scan resolves, including the
## exported-declaration shape `nkPostfix(nkIdent"*", nkIdent"name")` (see
## docs/spec/nim_ast_node_shape_quirks.md Q1) that indexes as `"*"` if the
## wrapper is not unwrapped.

import std/[options, tables]
import unittest

import compiler/ast
import core/parser_utils
import core/parsers/pnode_nav
import core/types/results

proc parse(src: string): PNode =
  let res = parseNimRes(src)
  doAssert res.isOk, res.error
  res.get

suite "PNode function index — issue #355 ProcDef slice":

  test "indexed lookup agrees with the linear scan on every declaration":
    let ast = parse("""
proc exportedProc*(x: int): int = x
proc plainProc(x: int): int = x
func exportedFunc*(x: int): int = x
""")
    let index = buildFunctionNodeIndexP(ast)
    for name in ["exportedProc", "plainProc", "exportedFunc"]:
      let linear = findFunctionNodeP(ast, name)
      let indexed = findIndexedFunctionNodeP(index, name)
      check linear.isSome
      check indexed.isSome
      check indexed.get == linear.get

  test "exported declarations are keyed by their real name, not the '*' marker":
    # The index folds to `strip().toLowerAscii()` so a lookup normalizes once
    # instead of per comparison; keys are therefore folded, never the marker.
    let ast = parse("proc exportedProc*(x: int): int = x")
    let index = buildFunctionNodeIndexP(ast)
    check "exportedproc" in index
    check "*" notin index
    check findIndexedFunctionNodeP(index, "exportedProc").isSome
    check findIndexedFunctionNodeP(index, "*").isNone

  test "name matching is case-insensitive and whitespace-insensitive like the scan":
    let ast = parse("proc MixedCase*(x: int): int = x")
    let index = buildFunctionNodeIndexP(ast)
    check findIndexedFunctionNodeP(index, "mixedcase").isSome
    check findIndexedFunctionNodeP(index, "  MixedCase  ").isSome

  test "missing names and empty queries resolve to none in both paths":
    let ast = parse("proc onlyProc*(x: int): int = x")
    let index = buildFunctionNodeIndexP(ast)
    check findFunctionNodeP(ast, "absent").isNone
    check findIndexedFunctionNodeP(index, "absent").isNone
    check findIndexedFunctionNodeP(index, "").isNone
    check findIndexedFunctionNodeP(index, "   ").isNone

  test "nil AST yields an empty index and none lookups":
    let nils: PNode = nil
    let index = buildFunctionNodeIndexP(nils)
    check index.len == 0
    check findIndexedFunctionNodeP(index, "anything").isNone
    check findFunctionNodeP(nils, "anything").isNone

  test "axiomImpl pragma is reachable through the indexed node":
    # The enrichment loop asserts on pragmas of the node the index returns, so
    # the node identity — not just the name — has to match the linear result.
    let ast = parse("""
proc withPragma*(x: int): int {.axiomImpl.} = x
proc withoutPragma*(x: int): int = x
""")
    let index = buildFunctionNodeIndexP(ast)
    let withImpl = findIndexedFunctionNodeP(index, "withPragma")
    check withImpl.isSome
    check hasPragmaNamedP(withImpl.get, "axiomImpl")
    let withoutImpl = findIndexedFunctionNodeP(index, "withoutPragma")
    check withoutImpl.isSome
    check not hasPragmaNamedP(withoutImpl.get, "axiomImpl")
