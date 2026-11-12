import std/[unittest, strutils]
import tests/sloc/golden_helpers

suite "sourceSloc PNode traversal — v9 contract (proc declaration span counted)":

  test "case 1 - ordinary code 3-line function yields 4 (proc + 3 code)":
    let src = "proc f() =\n  result = 1\n  discard\n  discard"
    check sourceSlocOf(src) == 4

  test "case 2 - comment-only line excluded from count, proc line counted":
    let src = "proc f() =\n  # this is a comment\n  result = 1"
    check sourceSlocOf(src) == 2

  test "case 3 - doc comment (##) line excluded from count, proc line counted":
    let src = "proc f() =\n  ## doc comment\n  result = 1"
    check sourceSlocOf(src) == 2

  test "case 4 - blank line excluded from count, proc line counted":
    let src = "proc f() =\n\n  result = 1"
    check sourceSlocOf(src) == 2

  test "case 5 - multiline string literal source lines included":
    let src = "let x = \"\"\"\n  hello\n  world\n\"\"\""
    check sourceSlocOf(src) == 4

  test "case 6 - pragma line included (execution effect)":
    let src = "{.warning: \"test\".}\ndiscard"
    check sourceSlocOf(src) == 2

  test "case 7 - nested comment excluded from count (ratified: proc declaration line counted)":
    let src = "proc f() =\n  #[ nested #[ comment ]# ]#\n  result = 1"
    check sourceSlocOf(src) == 2

  test "case 8 - nkEmpty/nkHidden source-less nodes excluded":
    let src = "proc f() =\n  discard"
    check sourceSlocOf(src) == 2

  test "case 9 - comment + code on same line: line included (code present)":
    let src = "proc f() =  # inline comment\n  result = 1"
    check sourceSlocOf(src) == 2

  test "case 10 - one-line multi-node statement counts as 1 line":
    let src = "let x = 1; let y = 2"
    check sourceSlocOf(src) == 1

  test "case 12 - two statements on same line: distinct line cardinality dedup":
    let src = "let x = 1; let y = 2"
    check sourceSlocOf(src) == 1