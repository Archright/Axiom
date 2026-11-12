## Unit tests for boundary_extraction_main.nim — pure functions + PNode-based extraction.
import std/strutils
import std/sets
import compiler/ast
import core/parser_utils
import core/boundary/boundary_extraction_main
import core/boundary/boundary_extraction_types

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  initParserUtils()

  echo "=== sanitizeLeanIdentifier ==="

  check "dot to underscore":
    let id1 = sanitizeLeanIdentifier("my.field.name")
    doAssert id1 == "my_field_name"

  check "multiple dots":
    let id2 = sanitizeLeanIdentifier("a.b.c.d")
    doAssert id2 == "a_b_c_d"

  check "no dots unchanged":
    let id3 = sanitizeLeanIdentifier("normalIdentifier")
    doAssert id3 == "normalIdentifier"

  check "underscore preserved":
    let id4 = sanitizeLeanIdentifier("my_field_name")
    doAssert id4 == "my_field_name"

  check "single segment":
    let id5 = sanitizeLeanIdentifier("x")
    doAssert id5 == "x"

  echo ""
  echo "=== sequenceElementBinderName ==="

  check "empty params returns baseIdx":
    let emptyParams: seq[ParamBoundary] = @[]
    let name1 = sequenceElementBinderName("my", emptyParams)
    doAssert name1 == "myIdx"

  check "single param returns baseIdx":
    let name2 = sequenceElementBinderName("item", @[ParamBoundary(name: "x", nimType: "int")])
    doAssert name2 == "itemIdx"

  check "duplicate base name increments suffix":
    let name3 = sequenceElementBinderName("idx", @[
      ParamBoundary(name: "idxIdx", nimType: "int")
    ])
    doAssert name3 == "idxIdx2"

  check "multiple duplicates":
    let name4 = sequenceElementBinderName("i", @[
      ParamBoundary(name: "iIdx", nimType: "int"),
      ParamBoundary(name: "iIdx2", nimType: "int")
    ])
    doAssert name4 == "iIdx3"

  echo ""
  echo "=== computeInformationGain ==="

  check "bool param with equality constraint high IG":
    let params1 = @[ParamBoundary(name: "b", nimType: "bool")]
    let smts1 = @[" (= b true)"]
    let ig1 = computeInformationGain(params1, smts1)
    doAssert ig1 > 0.0

  check "int param with range constraint":
    let params2 = @[ParamBoundary(name: "n", nimType: "int")]
    let smts2 = @["(and (>= n 0) (<= n 100))"]
    let ig2 = computeInformationGain(params2, smts2)
    doAssert ig2 > 0.0

  check "string param with low constraint":
    let params3 = @[ParamBoundary(name: "s", nimType: "string")]
    let smts3 = @["(>= (str.len s) 0)"]
    let ig3 = computeInformationGain(params3, smts3)
    doAssert ig3 >= 0.0

  check "empty params returns 0":
    let emptyParams: seq[ParamBoundary] = @[]
    let emptySmts: seq[string] = @[]
    let ig4 = computeInformationGain(emptyParams, emptySmts)
    doAssert ig4 == 0.0

  check "multiple params with constraints":
    let params5 = @[
      ParamBoundary(name: "a", nimType: "int"),
      ParamBoundary(name: "b", nimType: "int")
    ]
    let smts5 = @["(>= a 0)", "(<= b 100)"]
    let ig5 = computeInformationGain(params5, smts5)
    doAssert ig5 > 0.0

  echo ""
  echo "=== extractPathConditions nil input ==="

  check "nil fnNode returns empty seq":
    let pcs1 = extractPathConditions(nil)
    doAssert pcs1.len == 0

  echo ""
  echo "=== computeInformationGain edge cases ==="

  check "seq param with length constraint":
    let params6 = @[ParamBoundary(name: "items", nimType: "seq[int]")]
    let smts6 = @["(>= (seq.len items) 0)"]
    let ig6 = computeInformationGain(params6, smts6)
    doAssert ig6 >= 0.0

  check "float param":
    let params7 = @[ParamBoundary(name: "f", nimType: "float")]
    let smts7: seq[string] = @[]
    let ig7 = computeInformationGain(params7, smts7)
    doAssert ig7 == 0.0

  check "range param with tight bounds":
    let params8 = @[ParamBoundary(name: "idx", nimType: "range[0..10]")]
    let smts8 = @["(and (>= idx 0) (<= idx 10))"]
    let ig8 = computeInformationGain(params8, smts8)
    doAssert ig8 > 0.0

  echo ""
  echo "=== sanitizeLeanIdentifier edge cases ==="

  check "empty string":
    let id6 = sanitizeLeanIdentifier("")
    doAssert id6 == ""

  check "trailing dot":
    let id7 = sanitizeLeanIdentifier("field.")
    doAssert id7 == "field_"

  check "leading dot":
    let id8 = sanitizeLeanIdentifier(".field")
    doAssert id8 == "_field"

  echo ""
  echo "Result: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()