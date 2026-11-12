## Phase 2B: Tests for pure_func_guard — Syntactic Guard for {.axiom.} funcs.
##
## Test 1: Pure func with let/if → passes guard
## Test 2: Func with var → compile error (verified via compiles())
## Test 3: Func with while → compile error (verified via compiles())

import core/trusted/pure_func_guard
import std/macros
import std/strutils
proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      body
      inc passed
      echo "  PASS: " & name

  echo "=== Pure Func Guard Tests ==="
  echo ""

  # ═══════════════════════════════════════════════════════════════════════════
  # Test 1: Pure constructs pass the guard
  # ═══════════════════════════════════════════════════════════════════════════
  echo "1. Pure constructs pass the guard"

  # 1a: let bindings + if expression
  block:
    func pureAdd(x, y: int): int =
      pureFuncGuard:
        let sum = x + y
        if sum > 0: sum else: 0

    check "pureAdd(1, 2) == 3":
      doAssert pureAdd(1, 2) == 3
    check "pureAdd(-5, 3) == 0":
      doAssert pureAdd(-5, 3) == 0

  # 1b: case expression
  block:
    func classify(n: int): string =
      pureFuncGuard:
        let val = n
        case val
        of 0: "zero"
        of 1..10: "small"
        else: "large"

    check "classify(0) == 'zero'":
      doAssert classify(0) == "zero"
    check "classify(5) == 'small'":
      doAssert classify(5) == "small"
    check "classify(100) == 'large'":
      doAssert classify(100) == "large"

  # 1c: nested let bindings with operator expressions
  block:
    func compute(x: int): int =
      pureFuncGuard:
        let a = x + 1
        let b = a * 2
        let c = b - x
        if c > 0: c else: 0

    check "compute(5) == 7":
      # (5+1)*2 - 5 = 7
      doAssert compute(5) == 7
    check "compute(-10) == 0":
      # (-10+1)*2 - (-10) = -18+10 = -8, <= 0
      doAssert compute(-10) == 0

  # 1d: pure func with function calls
  block:
    func double(x: int): int =
      pureFuncGuard:
        x * 2

    func applyDouble(x: int): int =
      pureFuncGuard:
        let d = double(x)
        d + 1

    check "double(5) == 10":
      doAssert double(5) == 10
    check "applyDouble(5) == 11":
      doAssert applyDouble(5) == 11

  echo ""

  # ═══════════════════════════════════════════════════════════════════════════
  # Test 2: var declarations are rejected at compile time
  # ═══════════════════════════════════════════════════════════════════════════
  echo "2. var declarations are rejected"

  # Verify forbidden set includes nnkVarSection
  static:
    doAssert nnkVarSection in forbiddenNodeKinds,
      "nnkVarSection must be in forbiddenNodeKinds"

  # Verify guard rejects var via compiles() — parenthesized form avoids
  # the parsing ambiguity that `pureFuncGuard: var ...` triggers inside compiles().
  check "var rejected by guard":
    doAssert(not compiles(pureFuncGuard((var x = 1; x))),
      "pureFuncGuard must reject var declarations")

  echo ""

  # ═══════════════════════════════════════════════════════════════════════════
  # Test 3: while loops are rejected at compile time
  # ═══════════════════════════════════════════════════════════════════════════
  echo "3. while loops are rejected"

  # Verify forbidden set includes nnkWhileStmt
  static:
    doAssert nnkWhileStmt in forbiddenNodeKinds,
      "nnkWhileStmt must be in forbiddenNodeKinds"

  # Verify guard rejects while via compiles()
  check "while rejected by guard":
    doAssert(not compiles(pureFuncGuard((while true: discard))),
      "pureFuncGuard must reject while loops")

  echo ""

  # ═══════════════════════════════════════════════════════════════════════════
  # Bonus: verify all forbidden node kinds are in the set
  # ═══════════════════════════════════════════════════════════════════════════
  echo "4. Forbidden set completeness"

  check "nnkForStmt in forbiddenNodeKinds":
    static: doAssert nnkForStmt in forbiddenNodeKinds

  check "nnkAsgn in forbiddenNodeKinds":
    static: doAssert nnkAsgn in forbiddenNodeKinds

  echo ""

  # ═══════════════════════════════════════════════════════════════════════════
  # Summary
  # ═══════════════════════════════════════════════════════════════════════════
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
