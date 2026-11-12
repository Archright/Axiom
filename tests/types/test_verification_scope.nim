## test_verification_scope.nim — Unit tests for Verification Density.
## Tests the deterministic Kernel/Shell predicate and density computation.
##
## Run: nim c --hints:off -d:skipImportLint -r tests/types/test_verification_scope.nim

import std/[strutils, unicode]
import core/axiom_pragmas
import core/telemetry/verification_scope

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string; cond: bool) =
    if cond:
      inc passed
      echo "  PASS: " & name
    else:
      inc failed
      echo "  FAIL: " & name

  echo "=== VKD (Verified Kernel Density) Tests ==="
  echo ""

  # ── Test 1: classifyScope — axiom + Pure → Kernel ────────────────────
  echo "Test 1: classifyScope(axiom=true, Pure) → skKernel"
  let s1 = classifyScope(true, Pure)
  check("scope == skKernel", s1 == skKernel)

  # ── Test 2: classifyScope — axiom + IOEffect → Shell ─────────────────
  echo ""
  echo "Test 2: classifyScope(axiom=true, IOEffect) → skShell"
  let s2 = classifyScope(true, IOEffect)
  check("scope == skShell", s2 == skShell)

  # ── Test 3: classifyScope — no axiom + Pure → Shell ──────────────────
  echo ""
  echo "Test 3: classifyScope(axiom=false, Pure) → skShell"
  let s3 = classifyScope(false, Pure)
  check("scope == skShell", s3 == skShell)

  # ── Test 4: classifyScope — no axiom + IOEffect → Shell ──────────────
  echo ""
  echo "Test 4: classifyScope(axiom=false, IOEffect) → skShell"
  let s4 = classifyScope(false, IOEffect)
  check("scope == skShell", s4 == skShell)

  # ── Test 5: computeDensity — basic ───────────────────────────────────
  echo ""
  echo "Test 5: computeDensity(75, 100) = 75.0"
  let d1 = computeDensity(75, 100)
  check("density == 75.0", d1 == 75.0)

  # ── Test 6: computeDensity — zero total ──────────────────────────────
  echo ""
  echo "Test 6: computeDensity(0, 0) = 0.0 (no div-by-zero)"
  let d2 = computeDensity(0, 0)
  check("density == 0.0", d2 == 0.0)

  # ── Test 7: computeDensity — 100% ────────────────────────────────────
  echo ""
  echo "Test 7: computeDensity(165, 165) = 100.0"
  let d3 = computeDensity(165, 165)
  check("density == 100.0", d3 == 100.0)

  # ── Test 8: computeDensity — partial ──────────────────────────────────
  echo ""
  echo "Test 8: computeDensity(121, 165) ≈ 73.33"
  let d4 = computeDensity(121, 165)
  check("density ≈ 73.33", abs(d4 - 73.3333) < 0.01)

  # ── Test 9: densityStatus — COMPLETE ─────────────────────────────────
  echo ""
  echo "Test 9: densityStatus(100.0) = COMPLETE"
  check("status == COMPLETE", densityStatus(100.0) == "COMPLETE")

  # ── Test 10: densityStatus — PARTIAL ─────────────────────────────────
  echo ""
  echo "Test 10: densityStatus(73.3) = PARTIAL"
  check("status == PARTIAL", densityStatus(73.3) == "PARTIAL")

  # ── Test 11: buildVerificationScope ──────────────────────────────────
  echo ""
  echo "Test 11: buildVerificationScope constructs correctly"
  let vs = buildVerificationScope(165, 121, 959)
  check("kernelTotal == 165", vs.kernelTotal == 165)
  check("kernelVerified == 121", vs.kernelVerified == 121)
  check("shellTotal == 959", vs.shellTotal == 959)
  check("densityPct ≈ 73.33", abs(vs.densityPct - 73.3333) < 0.01)

  # ── Test 12: formatDensityBar (Unicode blocks) ──────────────────────
  echo ""
  echo "Test 12: formatDensityBar(50.0, 10)"
  let bar = formatDensityBar(50.0, 10)
  check("bar length == 12", bar.runeLen == 12)
  check("bar starts with [", bar[0] == '[')
  check("bar ends with ]", bar[^1] == ']')
  check("bar contains full block", "\u2588" in bar)
  check("bar contains light shade", "\u2591" in bar)

  # ── Summary ──────────────────────────────────────────────────────────
  echo ""
  echo "============================="
  echo "Passed: " & $passed & " / " & $(passed + failed)
  if failed > 0:
    echo "FAILED: " & $failed
    quit(1)
  else:
    echo "All tests passed."

main()
