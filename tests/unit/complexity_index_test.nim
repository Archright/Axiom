## Unit tests for complexity_index.nim — PNode-based ACI computation.
import std/strutils
import compiler/ast
import core/parser_utils
import core/boundary/complexity_index

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

  echo "=== initTypeRegistry ==="

  check "initTypeRegistry creates empty registry":
    let reg = initTypeRegistry()
    doAssert reg.get("AnyType", -1) == -1

  check "setFieldCount stores value":
    var reg2 = initTypeRegistry()
    setFieldCount(reg2, "MyType", 5)
    doAssert reg2.get("MyType", -1) == 5

  echo ""
  echo "=== canonicalizeTypeName ==="

  check "strips var modifier":
    doAssert canonicalizeTypeName("var int") == "int"

  check "strips ref modifier":
    doAssert canonicalizeTypeName("ref ProgressDisplay") == "ProgressDisplay"

  check "strips ptr modifier":
    doAssert canonicalizeTypeName("ptr SomeType") == "SomeType"

  check "strips generic parameters":
    doAssert canonicalizeTypeName("Table[string, int]").toLowerAscii() == "table"

  check "strips nested generics":
    doAssert canonicalizeTypeName("seq[int]").toLowerAscii() == "seq"

  check "preserves base name":
    doAssert canonicalizeTypeName("MyType") == "MyType"

  echo ""
  echo "=== heuristicFieldWeight ==="

  check "known stdlib types - Table":
    doAssert heuristicFieldWeight("Table") == 2
    doAssert heuristicFieldWeight("table") == 2

  check "known stdlib types - seq":
    doAssert heuristicFieldWeight("seq") == 1

  check "primitives - int":
    doAssert heuristicFieldWeight("int") == 1

  check "primitives - string":
    doAssert heuristicFieldWeight("string") == 1

  check "primitives - bool":
    doAssert heuristicFieldWeight("bool") == 1

  check "data-derived - JsonNode":
    doAssert heuristicFieldWeight("JsonNode") == 4

  check "name-suffix - State":
    doAssert heuristicFieldWeight("MyState") == 5

  check "unknown type fallback":
    doAssert heuristicFieldWeight("UnknownType") == 3

  check "empty string returns 0":
    doAssert heuristicFieldWeight("") == 0

  echo ""
  echo "=== lookupTypeFields ==="

  check "registry hit returns field count":
    var reg3 = initTypeRegistry()
    setFieldCount(reg3, "MyObject", 8)
    doAssert lookupTypeFields(reg3, "MyObject") == 8

  check "missing type uses heuristic":
    var reg4 = initTypeRegistry()
    doAssert lookupTypeFields(reg4, "JsonNode") == 4

  echo ""
  echo "=== isComplexType ==="

  check "weight >= threshold is complex":
    var reg5 = initTypeRegistry()
    setFieldCount(reg5, "Complex", 5)
    doAssert isComplexType(reg5, "Complex", 4) == true

  check "weight < threshold is not complex":
    var reg6 = initTypeRegistry()
    setFieldCount(reg6, "Simple", 2)
    doAssert isComplexType(reg6, "Simple", 4) == false

  echo ""
  echo "=== computeCyclomaticComplexity ==="

  check "nil PNode returns 1":
    doAssert computeCyclomaticComplexity(nil) == 1

  echo ""
  echo "=== computeCognitiveComplexity ==="

  echo ""
  echo "=== computeAxiomComplexityIndex ==="

  check "nil PNode returns default ACI":
    let aci = computeAxiomComplexityIndex(nil)
    doAssert aci.total == 0
    doAssert aci.conservativeTrigger == ctNone

  echo ""
  echo "=== isConservativeTriggered ==="

  check "default has no trigger":
    let aci = computeAxiomComplexityIndex(nil)
    doAssert isConservativeTriggered(aci) == false

  echo ""
  echo "=== aciToString ==="

  check "ACI string contains ACI=":
    let aci = computeAxiomComplexityIndex(nil)
    let s = aciToString(aci)
    doAssert s.startsWith("ACI=")

  echo ""
  echo "=== aciCategoryToTimeoutMs ==="

  check "ccSimple maps to 25000ms":
    doAssert aciCategoryToTimeoutMs(ccSimple) == 25_000

  check "ccMedium maps to 30000ms":
    doAssert aciCategoryToTimeoutMs(ccMedium) == 30_000

  check "ccComplex maps to 60000ms":
    doAssert aciCategoryToTimeoutMs(ccComplex) == 60_000

  check "ccCritical maps to 120000ms":
    doAssert aciCategoryToTimeoutMs(ccCritical) == 120_000

  echo ""
  echo "=== computeCyclomaticComplexity regression tests ==="

  check "elif chain counts if+elif branches (expands to 4 with base)":
    let actualElif = computeCyclomaticComplexity(parseStringAST("proc f(x: int): int =\n  if x > 0:\n    result = 1\n  elif x < 0:\n    result = 2\n  elif x == 0:\n    result = 3\n  else:\n    result = 4"))
    doAssert actualElif == 4

  check "try/except counts 2 except branches (expands to 3 with base)":
    let actualTry = computeCyclomaticComplexity(parseStringAST("proc g(): int =\n  try:\n    result = 1\n  except ValueError:\n    result = 2\n  except:\n    result = 3"))
    doAssert actualTry == 3

  check "when statement counts 1 when branch (expands to 2 with base)":
    let actualWhen = computeCyclomaticComplexity(parseStringAST("proc h(): int =\n  when defined(debug):\n    result = 1\n  else:\n    result = 2"))
    doAssert actualWhen == 2

  check "simple if counts 1 if branch (expands to 2 with base)":
    let actualIf = computeCyclomaticComplexity(parseStringAST("proc i(): int =\n  if true:\n    result = 1"))
    doAssert actualIf == 2

  check "case/of counts base + 3 of branches":
    let actualCase = computeCyclomaticComplexity(parseStringAST("proc k(x: int): int =\n  case x:\n  of 1:\n    result = 1\n  of 2:\n    result = 2\n  else:\n    result = 0"))
    doAssert actualCase == 3

  echo ""
  echo "Result: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()