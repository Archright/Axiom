import std/[unittest, tables, strutils]
import core/types/results
import core/encoding/smtlib2_sanitizer

suite "Type Purity Filter":

  test "sanitizeSmtAssert — well-typed expr unchanged":
    let declTypes = {"x": "Int", "y": "Int"}.toTable
    let res = sanitizeSmtAssert("(assert (>= x 0))", declTypes)
    check res.isOk
    check res.get == "(assert (>= x 0))"

  test "sanitizeSmtAssert — Bool in numeric comparison returns err":
    let declTypes = {"b": "Bool", "x": "Int"}.toTable
    let res = sanitizeSmtAssert("(assert (>= b 0))", declTypes)
    check res.isErr
    check "ill-typed-smt" in res.error

  test "sanitizeSmtAssert — mismatched types in equality returns err":
    let declTypes = {"b": "Bool", "x": "Int"}.toTable
    let res = sanitizeSmtAssert("(assert (= b x))", declTypes)
    check res.isErr
    check "ill-typed-smt" in res.error

  test "sanitizeSmtAssert — Pattern 1 numeric coercion kept":
    let declTypes = {"x": "Int"}.toTable
    let res = sanitizeSmtAssert("(assert (and 5 (>= x 0)))", declTypes)
    check res.isOk
    check "(not (= 5 0))" in res.get
