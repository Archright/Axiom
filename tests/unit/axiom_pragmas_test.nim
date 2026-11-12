## Axiom Compile-time Enforcement Negative Test Cases
##
## These tests verify that axiom_pragmas macros correctly reject
## code that violates architecture rules. Each test should cause
## a compile-time error when the violation is present.
##
## Run with: nim c -r tests/unit/axiom_pragmas_test.nim
## Expected: compile-time errors for each violation case
##
## NOTE: 5 stub tests removed (DEBT#119). The "rejects raw X" tests
## were `check true` placeholders that tested nothing. Compile-time
## rejection testing requires a separate test harness (nim check + expect-failure).

import std/strutils as su
import std/[
  os,
  tables,
  sets
]
import std/unittest
import core/trusted/axiom_pragmas
import core/parsers/safe_parsers

compositionRootGuard(@[
  "std/strutils",
  "std/os",
  "std/tables",
  "std/sets"
])

suite "axiomSafeParse enforcement":
  test "allows safeParseInt":
    axiomSafeParse:
      let r = safeParseInt("123")
      check r.ok

  test "allows safeParseFloat":
    axiomSafeParse:
      let r = safeParseFloat("3.14")
      check r.ok

suite "axiomAcyclic enforcement":
  test "allows ref object with acyclic":
    axiomAcyclic:
      type
        MyObj {.acyclic.} = ref object
          data: string
    # Compile-time success IS the verification: axiomAcyclic allows this type.
    # Runtime assertion would test Nim's type system, not the macro.
    doAssert MyObj is ref object

suite "composition root guard":
  test "alias import recognized":
    check "hello".toUpperAscii == "HELLO"
  test "multi-line indented import recognized":
    # Use one symbol from each bracket-imported module to avoid unused-import warnings.
    discard os.getCurrentDir()
    discard tables.initTable[string, string]().len
    discard sets.initHashSet[string]().len
