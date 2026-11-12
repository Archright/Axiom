## Unit tests for boundary_phases.nim — function extraction phases.
import std/strutils
import core/parser_utils
import core/boundary/private/boundary_phases
import core/boundary/boundary_extraction_types
import core/boundary/private/trivial_filter

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

  echo "=== extractFunctionDefsFromSource ==="

  check "extracts simple proc - finds at least one":
    let src = "proc foo(): int = 42"
    let defs = extractFunctionDefsFromSource(src)
    doAssert defs.len >= 1

  check "extracts simple func - finds at least one":
    let src = "func bar(x: int): int = x * 2"
    let defs = extractFunctionDefsFromSource(src)
    doAssert defs.len >= 1

  check "extracts params when present":
    let src = "proc add(a: int; b: string): int = 0"
    let defs = extractFunctionDefsFromSource(src)
    if defs.len > 0 and defs[0].params.len > 0:
      doAssert defs[0].params[0].name.len > 0

  check "empty source returns empty seq":
    let defs = extractFunctionDefsFromSource("")
    doAssert defs.len == 0

  check "extracts from multi-line source":
    let src = "proc foo(): void = discard\nproc bar(): int = 1"
    let defs = extractFunctionDefsFromSource(src)
    doAssert defs.len >= 1

  echo ""
  echo "=== isTrivialConstraint ==="

  check "depth constraint is non-trivial":
    doAssert isTrivialConstraint("(>= depth 0)", "depth >= 0") == false

  check "integer overflow bounds are trivial":
    doAssert isTrivialConstraint(
      "(and (>= x -9223372036854775808) (<= x 9223372036854775807))", ""
    ) == true

  check "length constraint with strict operator is non-trivial":
    doAssert isTrivialConstraint("(> (str.len s) 0)", "s.length > 0") == false

  check "length constraint without strict operator is trivial":
    doAssert isTrivialConstraint("(>= (str.len s) 0)", "s.length >= 0") == true

  check "boolean literal is trivial":
    doAssert isTrivialConstraint("true", "true") == true

  check "self-equality is non-trivial":
    doAssert isTrivialConstraint("(= x x)", "x = x") == false

  check "variable constraint is non-trivial":
    doAssert isTrivialConstraint("(> n 0)", "n > 0") == false

  echo ""
  echo "=== countNonTrivial ==="

  check "counts non-trivial constraints":
    let smts = @["(> x 0)", "(< y 10)", "(>= z 0)"]
    let leans = @["x > 0", "y < 10", "z >= 0"]
    doAssert countNonTrivial(smts, leans) == 3

  check "all trivial returns 0":
    let smts2 = @["true", "true"]
    let leans2 = @["true", "true"]
    doAssert countNonTrivial(smts2, leans2) == 0
    doAssert countNonTrivial(@[], @[]) == 0

  check "all non-trivial returns full count":
    let smts3 = @["(> x 0)", "(< y 10)"]
    let leans3 = @["x > 0", "y < 10"]
    doAssert countNonTrivial(smts3, leans3) == 2

  echo ""
  echo "=== filterNonTrivialParts ==="

  check "filters out trivial constraints":
    let smts = @["(> x 0)", "(>= (str.len s) 0)"]
    let leans = @["x > 0", "s.length >= 0"]
    let (nonTrivialSmt, nonTrivialLean) = filterNonTrivialParts(smts, leans)
    doAssert nonTrivialSmt.len == 1
    doAssert nonTrivialLean.len == 1

  check "handles empty input":
    let (s, l) = filterNonTrivialParts(@[], @[])
    doAssert s.len == 0
    doAssert l.len == 0

  check "all non-trivial preserved":
    let smts2 = @["(> x 0)", "(< y 10)"]
    let leans2 = @["x > 0", "y < 10"]
    let (s2, l2) = filterNonTrivialParts(smts2, leans2)
    doAssert s2.len == 2

  echo ""
  echo "Result: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()