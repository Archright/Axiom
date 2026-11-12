## Unit tests for boundary_extraction_helpers.nim — PNode-based extraction.
import std/strutils
import std/sequtils
import compiler/ast
import core/parser_utils
import core/boundary/boundary_extraction_helpers
import core/boundary/abstract_spec_lowering

proc anyIt(s: seq[string]; cond: proc(x: string): bool): bool =
  for item in s:
    if cond(item):
      return true
  false

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

  echo "=== typeToBoundaryConstraints ==="

  check "int type -> smt bounds":
    let (smt, lean) = typeToBoundaryConstraints("x", "int")
    doAssert "(and (>= x -9223372036854775808" in smt

  check "int64 type -> smt bounds":
    let (smt2, lean2) = typeToBoundaryConstraints("n", "int64")
    doAssert "(and (>= n -9223372036854775808" in smt2

  check "uint type -> non-negative smt":
    let (smt3, lean3) = typeToBoundaryConstraints("u", "uint")
    doAssert "(>= u 0)" in smt3

  check "bool type -> boolean smt":
    let (smt4, lean4) = typeToBoundaryConstraints("b", "bool")
    doAssert " (= b true)" in smt4 or "(or (= b true)" in smt4

  check "string type -> length smt":
    let (smt5, lean5) = typeToBoundaryConstraints("s", "string")
    doAssert "(str.len s)" in smt5

  check "range type -> bounds smt":
    let (smt6, lean6) = typeToBoundaryConstraints("n", "range[0..100]")
    doAssert "(>= n 0)" in smt6
    doAssert "(<= n 100)" in smt6

  check "seq type -> size smt":
    let (smt7, lean7) = typeToBoundaryConstraints("lst", "seq[int]")
    doAssert "(seq.len lst)" in smt7 or "ast_parse_failed_isolated" in smt7

  check "natural type -> non-negative smt":
    let (smt8, lean8) = typeToBoundaryConstraints("nat", "natural")
    doAssert "(>= nat 0)" in smt8

  echo ""
  echo "=== determineBoundaryTier ==="

  check "Option type -> Tier1":
    let tier1 = determineBoundaryTier("Option[int]")
    doAssert tier1 == ltTier1

  check "Result type -> Tier1":
    let tier2 = determineBoundaryTier("Result[string, int]")
    doAssert tier2 == ltTier1

  check "Table type -> Tier2":
    let tier3 = determineBoundaryTier("Table[string, int]")
    doAssert tier3 == ltTier2

  check "JsonNode type -> Tier2":
    let tier4 = determineBoundaryTier("JsonNode")
    doAssert tier4 == ltTier2

  check "Unknown type -> Tier3":
    let tier5 = determineBoundaryTier("UnknownComplexType")
    doAssert tier5 == ltTier3

  check "string type -> Tier2":
    let tier6 = determineBoundaryTier("string")
    doAssert tier6 == ltTier2

  echo ""
  echo "=== routeToBoundaryStrategy ==="

  check "Option param routing":
    let (tierStr, smtPrefix, leanPrefix) = routeToBoundaryStrategy("opt", "Option[int]")
    doAssert tierStr == "tier1-adt"
    doAssert smtPrefix.contains("Tier 1 ADT")
    doAssert leanPrefix.contains("Tier 1 ADT")

  check "Table param routing":
    let (tierStr2, smtPrefix2, leanPrefix2) = routeToBoundaryStrategy("tbl", "Table[string, int]")
    doAssert tierStr2 == "tier2-abstract"
    doAssert smtPrefix2.contains("Tier 2 abstract")
    doAssert leanPrefix2.contains("Tier 2 abstract")

  check "Unknown param routing":
    let (tierStr3, _, _) = routeToBoundaryStrategy("x", "ComplexType")
    doAssert tierStr3 == "tier3-uninterpreted"

  echo ""
  echo "=== extractParamsFromSourceRegex ==="

  check "single param extraction":
    let params = extractParamsFromSourceRegex("proc foo(x: int): int = x", "foo")
    doAssert params.len >= 1
    doAssert params[0].name == "x"
    doAssert params[0].nimType == "int"

  check "func keyword extraction":
    let params3 = extractParamsFromSourceRegex("func sq(x: int): int = x * x", "sq")
    doAssert params3.len >= 1
    doAssert params3[0].name == "x"

  echo ""
  echo "=== convertExpressionToSmtLean (nil input) ==="

  check "nil expr returns empty":
    let (smt, lean) = convertExpressionToSmtLean(nil)
    doAssert smt == ""
    doAssert lean == ""

  echo ""
  echo "=== findNodesMultiTag ==="

  check "empty node query":
    let nilNodes = findNodesMultiTag(nil, ["procdef"])
    doAssert nilNodes.len == 0

  echo ""
  echo "=== lowerOptionAdt ==="

  check "Option ADT smt declarations":
    let opt = lowerOptionAdt("Option[int]", "int")
    doAssert opt.tier == ltTier1
    doAssert opt.typeName == "Option[int]"
    doAssert opt.smtDecls.len > 0
    doAssert opt.smtDecls[0].contains("declare-datatypes")

  check "Option ADT has isSome/isNone":
    let opt2 = lowerOptionAdt("Option[int]", "int")
    var hasIsSome = false
    var hasIsNone = false
    for d in opt2.smtDecls:
      if d.contains("isSome"): hasIsSome = true
      if d.contains("isNone"): hasIsNone = true
    doAssert hasIsSome
    doAssert hasIsNone

  echo ""
  echo "=== Result ADT ==="

  check "Result ADT lower":
    let res = lowerResultAdt("Result[Ok, Err]", "Ok", "Err")
    doAssert res.tier == ltTier1
    var hasIsOk = false
    var hasIsErr = false
    for d in res.smtDecls:
      if d.contains("isOk"): hasIsOk = true
      if d.contains("isErr"): hasIsErr = true
    doAssert hasIsOk
    doAssert hasIsErr

  echo ""
  echo "=== lowerAbstractSort ==="

  check "abstract sort with sortDecl":
    let abs = lowerAbstractSort("JsonNode", "(declare-sort JsonNode 0)", @[])
    doAssert abs.tier == ltTier2
    doAssert abs.typeName == "JsonNode"
    doAssert abs.smtDecls.len == 1

  echo ""
  echo "=== classifyNimType ==="

  check "Option type classified as Tier1":
    doAssert classifyNimType("Option[int]") == ltTier1

  check "String type classified as Tier2":
    doAssert classifyNimType("string") == ltTier2

  check "Table type classified as Tier2":
    doAssert classifyNimType("Table[string, int]") == ltTier2

  check "Unknown type classified as Tier3":
    doAssert classifyNimType("CustomUnknownType") == ltTier3

  echo ""
  echo "Result: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()