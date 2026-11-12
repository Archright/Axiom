## test_verification_tier.nim — Unit tests for Phase 4A VerificationTier.
## Tests the pure functional mapping between Z3/Lean results and tier classification.
##
## Run: nim c --hints:off -d:skipImportLint -r tests/core/types/test_verification_tier.nim

import core/types/verification_tier
proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, cond: bool) =
    if cond:
      inc passed
      echo "  PASS: " & name
    else:
      inc failed
      echo "  FAIL: " & name

  echo "=== VerificationTier Tests (Phase 4A) ==="
  echo ""

  # ── Test 1: tierFromResults(true, false) → vtZ3Only ──────────────────
  echo "Test 1: Z3-only (z3=true, lean=false)"
  let t1 = tierFromResults(true, false)
  check("tier == vtZ3Only", t1 == vtZ3Only)
  check("label == z3-verified", tierLabel(t1) == "z3-verified")
  check("$ == z3-verified", $t1 == "z3-verified")
  check("isValid == true", t1.isValid)
  check("requiresFallback == true", t1.requiresFallback)

  # ── Test 2: tierFromResults(false, true) → vtLeanOnly ────────────────
  echo ""
  echo "Test 2: Lean-only (z3=false, lean=true)"
  let t2 = tierFromResults(false, true)
  check("tier == vtLeanOnly", t2 == vtLeanOnly)
  check("label == lean-verified", tierLabel(t2) == "lean-verified")
  check("$ == lean-verified", $t2 == "lean-verified")
  check("isValid == true", t2.isValid)
  check("requiresFallback == false", not t2.requiresFallback)

  # ── Test 3: tierFromResults(true, true) → vtDual ────────────────────
  echo ""
  echo "Test 3: Dual (z3=true, lean=true)"
  let t3 = tierFromResults(true, true)
  check("tier == vtDual", t3 == vtDual)
  check("label == dual-verified", tierLabel(t3) == "dual-verified")
  check("$ == dual-verified", $t3 == "dual-verified")
  check("isValid == true", t3.isValid)
  check("requiresFallback == false", not t3.requiresFallback)

  # ── Test 4: tierFromResults(false, false) → vtNone ───────────────────
  echo ""
  echo "Test 4: None (z3=false, lean=false)"
  let t4 = tierFromResults(false, false)
  check("tier == vtNone", t4 == vtNone)
  check("label == none", tierLabel(t4) == "none")
  check("$ == none", $t4 == "none")
  check("isValid == false", not t4.isValid)
  check("requiresFallback == false", not t4.requiresFallback)

  # ── Test 5: All enum values have labels ──────────────────────────────
  echo ""
  echo "Test 5: Exhaustive enum label coverage"
  for t in [vtNone, vtZ3Only, vtLeanOnly, vtDual]:
    let label = tierLabel(t)
    check($t & " has non-empty label", label.len > 0)

  # ── Summary ──────────────────────────────────────────────────────────
  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
