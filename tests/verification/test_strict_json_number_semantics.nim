import std/[json, math, strutils, unittest]
import core/results
import verification/evidence_bundle/strict_json

## Regression: strict JSON float tokens must go through the sanctioned
## `safeParseFloat` wrapper and must never materialize a non-finite JFloat.
##
## Before this guard, `parseStrictJson("1e400")` returned a JFloat holding
## `inf`; re-serialization then emitted the non-number `"inf"`, so a verifier
## could accept a document whose parsed type does not round-trip.

proc parseOk(text: string): JsonNode =
  let r = parseStrictJson(text)
  doAssert r.isOk, text & " rejected: " & (if r.isOk: "" else: r.error)
  r.get

suite "strict_json number semantics":
  test "finite float tokens parse identically to strutils.parseFloat":
    for token in ["0.0", "-0.0", "0.1", "3.14", "1e0", "1E+2", "1e-2",
                  "-2.5e+3", "1.7976931348623157e308",
                  "2.2250738585072014e-308", "5e-324",
                  "123456789012345678901234567890.5", "1e-400"]:
      let node = parseOk(token)
      check node.kind == JFloat
      check node.getFloat == strutils.parseFloat(token)
    check classify(parseOk("-0.0").getFloat) == fcNegZero

  test "integer tokens keep the integer path":
    check parseOk("42").kind == JInt
    check parseOk("-0").kind == JInt

  test "float overflow is rejected, never inf":
    for token in ["1e400", "-1e400", "1e309", "1e999999999999999999999999",
                  "1" & repeat('0', 400) & ".0"]:
      let r = parseStrictJson(token)
      check r.isErr
      check r.error.startsWith("number out of range")

  test "overflow inside a container rejects the whole document":
    let r = parseStrictJson("""{"x":[1, 1e400]}""")
    check r.isErr
    check r.error.startsWith("number out of range")

  test "integer overflow stays rejected":
    let r = parseStrictJson("99999999999999999999999999")
    check r.isErr
    check r.error.startsWith("integer out of range")

  test "non-finite spellings are not JSON numbers":
    for token in ["nan", "NaN", "inf", "Inf", "Infinity", "-Infinity"]:
      check parseStrictJson(token).isErr

  test "malformed number tokens stay rejected":
    for token in ["1.", ".5", "1e", "1e+", "+1", "01", "-", "--1", "1e400x"]:
      check parseStrictJson(token).isErr