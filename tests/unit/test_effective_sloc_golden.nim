import std/[unittest, options, sets, strutils, json]
import compiler/[ast, idents]
import core/results
import core/sloc_policy
import core/ast_kernel
import tests/sloc/golden_helpers

suite "effectiveSLOC golden corpus — v9 ratified oracle":

  test "case 1 - sourceSloc proc+3code = 4 [ratified: proc declaration span counted]":
    let src = "proc f() =\n  result = 1\n  discard\n  discard"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 2 - sourceSloc proc+code = 2 [ratified: proc declaration span counted]":
    let src = "proc f() =\n  # comment\n  result = 1"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 3 - sourceSloc proc+code = 2 [ratified: proc declaration span counted]":
    let src = "proc f() =\n  ## doc comment\n  result = 1"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 4 - sourceSloc proc+code = 2 [ratified: proc declaration span counted]":
    let src = "proc f() =\n\n  result = 1"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 5 - sourceSloc multiline string = 4 [ratified value retained]":
    let src = "let x = \"\"\"\n  hello\n  world\n\"\"\""
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 6 - sourceSloc pragma + code = 2 [ratified value retained]":
    let src = "{.warning: \"test\".}\ndiscard"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 7 - sourceSloc nested comment excluded = 2 [ratified value retained]":
    let src = "proc f() =\n  #[ nested #[ comment ]# ]#\n  result = 1"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 8 - sourceSloc nkEmpty excluded = 2 [ratified value retained]":
    let src = "proc f() =\n  discard"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 9 - sourceSloc inline comment + code = 2 [ratified value retained]":
    let src = "proc f() =  # inline comment\n  result = 1"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 10 - sourceSloc one-line multi = 1 [ratified value retained]":
    let src = "let x = 1; let y = 2"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 11 / sourceSloc / 4 / all syntactic when branches are counted":
    let src = "when true:\n  discard\nwhen false:\n  discard"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()

  test "case 11 / effectiveSloc / 2 / only active Tier1 branch contributes":
    let src = "when true:\n  discard\nwhen false:\n  discard"
    let res = effectiveSlocOf(src, WhenContext())
    let exp = ratifiedExpected(src, "effectiveSloc")
    check exp != nil
    check res.isOk()
    check res.get() == exp.getInt()

  test "case 11 both-branch: when true: A else: B → effectiveSloc = A (2)":
    let src = "when true:\n  discard\nelse:\n  discard"
    let res = effectiveSlocOf(src, WhenContext())
    let exp = ratifiedExpected(src, "effectiveSloc")
    check exp != nil
    check res.isOk()
    check res.get() == exp.getInt()

  test "case 11 both-branch: when false: A else: B → effectiveSloc = B (1)":
    let src = "when false:\n  discard\nelse:\n  discard"
    let res = effectiveSlocOf(src, WhenContext())
    let exp = ratifiedExpected(src, "effectiveSloc")
    check exp != nil
    check res.isOk()
    check res.get() == exp.getInt()

  test "case 12 - sourceSloc one-line multi = 1 [ratified value retained]":
    let src = "let x = 1; let y = 2"
    let exp = ratifiedExpected(src, "sourceSloc")
    check exp != nil
    check sourceSlocOf(src) == exp.getInt()