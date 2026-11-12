## Unit tests for src/core/parsers/safe_parsers.nim — integer parse contracts.
##
## Locks the two distinct consumption contracts the codebase relies on:
##  - safeParseInt: std/parseutils prefix semantics (consumed-length
##    return value; "1abc" -> ok(1)). Broad-consumer contract — must NOT
##    be tightened in place.
##  - strictParseInt: whole-string consumption (the strutils.parseInt
##    contract as a Result). Regression guard for the f9305a902
##    safeParseInt substitution that let "e - 1abc" evaluate as "e - 1".
##
## Run from repo root:
##   nim c -r --hints:off tests/unit/safe_parsers_test.nim

import std/unittest
import core/parsers/safe_parsers
import core/types/results

suite "safeParseInt prefix semantics (broad-consumer contract)":
  test "prefix parse succeeds and drops trailing garbage":
    check safeParseInt("1abc").isOk
    check safeParseInt("1abc").get() == 1
    check safeParseInt("4x").get() == 4

  test "plain integers and signs parse":
    check safeParseInt("42").get() == 42
    check safeParseInt("-7").get() == -7
    check safeParseInt("+3").get() == 3

  test "no leading digit is an error":
    check safeParseInt("abc").isErr
    check safeParseInt("").isErr

suite "strictParseInt whole-string semantics":
  test "exact integers parse (strutils.parseInt contract)":
    check strictParseInt("42").get() == 42
    check strictParseInt("-7").get() == -7
    check strictParseInt("-0042").get() == -42
    check strictParseInt("+3").get() == 3

  test "trailing garbage is rejected (evalLinearRhs regression)":
    check strictParseInt("1abc").isErr
    check strictParseInt("4x").isErr
    check strictParseInt("1 abc").isErr
    check strictParseInt("1.5").isErr

  test "leading garbage, whitespace and empty are rejected":
    check strictParseInt(" 42").isErr
    check strictParseInt("abc").isErr
    check strictParseInt("").isErr

  test "underscore digit separators keep strutils.parseInt behavior":
    check strictParseInt("1_0").get() == 10
    check strictParseInt("2024_05_02").get() == 20240502
    check strictParseInt("1_").get() == 1

  test "out-of-range is an error, not a crash":
    check strictParseInt("99999999999999999999999").isErr
    check strictParseInt("-99999999999999999999999").isErr

suite "safeParseNatural (derived from safeParseInt)":
  test "prefix semantics preserved":
    check safeParseNatural("2x").get() == 2
    check safeParseNatural("-2").isErr
