## Unit tests for OGR/PAR metrics computation (metrics.nim).
## Uses custom main() pattern to avoid unittest framework cleanup crashes.

import std/[options, strutils, sequtils]
import verification/obligation/metrics

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

  template assertEq(a, b: untyped) =
    assert a == b, "Expected " & $b & " but got " & $a

  template assertApproxEq(a, b: float, tol: float = 1e-9) =
    assert abs(a - b) < tol, "Expected ~" & $b & " but got " & $a

  # -----------------------------------------------------------------------
  # 1. Basic computation — all non-zero denominators
  # -----------------------------------------------------------------------
  echo "=== Basic OGR/PAR computation ==="

  check "OGR = 3/5 = 0.6 when 3 of 5 targets have obligations":
    let m = computeOgrPar(eligibleTargets = 5, targetsWithObligations = 3,
                          generated = 10, attempted = 8)
    assertApproxEq(m.ogr, 0.6)

  check "PAR = 8/10 = 0.8 when 8 of 10 generated obligations were attempted":
    let m = computeOgrPar(eligibleTargets = 5, targetsWithObligations = 3,
                          generated = 10, attempted = 8)
    assertApproxEq(m.par, 0.8)

  check "OGR = 1.0 when all eligible targets have obligations":
    let m = computeOgrPar(eligibleTargets = 4, targetsWithObligations = 4,
                          generated = 5, attempted = 5)
    assertApproxEq(m.ogr, 1.0)

  check "PAR = 1.0 when all generated obligations were attempted":
    let m = computeOgrPar(eligibleTargets = 4, targetsWithObligations = 4,
                          generated = 5, attempted = 5)
    assertApproxEq(m.par, 1.0)

  check "OGR = 0.0 when no targets have obligations":
    let m = computeOgrPar(eligibleTargets = 5, targetsWithObligations = 0,
                          generated = 0, attempted = 0)
    assertApproxEq(m.ogr, 0.0)

  check "PAR = 0.0 when no obligations were generated":
    let m = computeOgrPar(eligibleTargets = 5, targetsWithObligations = 0,
                          generated = 0, attempted = 0)
    assertApproxEq(m.par, 0.0)

  # -----------------------------------------------------------------------
  # 2. Zero-denominator guards (deterministic)
  # -----------------------------------------------------------------------
  echo "=== Zero-denominator guards ==="

  check "OGR = 0.0 when eligibleTargets = 0 (no VKS)":
    let m = computeOgrPar(eligibleTargets = 0, targetsWithObligations = 0,
                          generated = 10, attempted = 5)
    assertApproxEq(m.ogr, 0.0)

  check "PAR = 0.0 when generated = 0 (no obligations produced)":
    let m = computeOgrPar(eligibleTargets = 5, targetsWithObligations = 3,
                          generated = 0, attempted = 0)
    assertApproxEq(m.par, 0.0)

  check "Both metrics = 0.0 when all denominators are 0":
    let m = computeOgrPar(eligibleTargets = 0, targetsWithObligations = 0,
                          generated = 0, attempted = 0)
    assertApproxEq(m.ogr, 0.0)
    assertApproxEq(m.par, 0.0)

  # -----------------------------------------------------------------------
  # 3. Determinism — same inputs always produce same outputs
  # -----------------------------------------------------------------------
  echo "=== Determinism ==="

  check "deterministic: same inputs produce identical results":
    let m1 = computeOgrPar(10, 7, 20, 15)
    let m2 = computeOgrPar(10, 7, 20, 15)
    assertApproxEq(m1.ogr, m2.ogr)
    assertApproxEq(m1.par, m2.par)

  check "deterministic: OGR changes with targetsWithObligations":
    let m1 = computeOgrPar(10, 7, 20, 15)
    let m2 = computeOgrPar(10, 5, 20, 15)
    assert m1.ogr > m2.ogr, "more targets with obligations → higher OGR"

  check "deterministic: PAR changes with attempted count":
    let m1 = computeOgrPar(10, 7, 20, 15)
    let m2 = computeOgrPar(10, 7, 20, 10)
    assert m1.par > m2.par, "more attempted → higher PAR"

  # -----------------------------------------------------------------------
  # 4. Bounds — 0.0 <= metric <= 1.0
  # -----------------------------------------------------------------------
  echo "=== Bounds ==="

  check "OGR is always in [0.0, 1.0]":
    for t in 0 .. 10:
      for e in 1 .. 10:
        let m = computeOgrPar(eligibleTargets = e, targetsWithObligations = min(t, e),
                              generated = 10, attempted = 5)
        assert m.ogr >= 0.0 and m.ogr <= 1.0,
          "OGR out of bounds: " & $m.ogr & " (eligible=" & $e & ", with=" & $t & ")"

  check "PAR is always in [0.0, 1.0]":
    for a in 0 .. 10:
      for g in 1 .. 10:
        let m = computeOgrPar(eligibleTargets = 5, targetsWithObligations = 3,
                              generated = g, attempted = min(a, g))
        assert m.par >= 0.0 and m.par <= 1.0,
          "PAR out of bounds: " & $m.par & " (generated=" & $g & ", attempted=" & $a & ")"

  # -----------------------------------------------------------------------
  # Summary
  # -----------------------------------------------------------------------
  echo ""
  echo "=== Results ==="
  echo "  Passed: " & $passed
  echo "  Failed: " & $failed
  if failed > 0:
    echo "  FAILED"
    quit(1)
  else:
    echo "  ALL PASSED"

when isMainModule:
  main()
