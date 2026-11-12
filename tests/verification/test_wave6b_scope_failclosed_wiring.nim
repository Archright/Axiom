import std/os
import std/json
import std/tempfiles
import core/proof/proof_integrity
import cli/shared/proof_hydration

## Wave6b: Verification ASI aggregation path must fail-closed on a
## missing/corrupt kernel scope lock — never silently produce empty scope
## that zeros out ASI.

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc expectRaises(body: proc()) =
  ## Expect body to raise CatchableError; fail the test if it does not.
  var raised = false
  try:
    body()
  except CatchableError:
    raised = true
  except Exception:
    inc failures
    echo "  FAIL: expected CatchableError but got a different exception"
    return
  if not raised:
    inc failures
    echo "  FAIL: expected CatchableError but no exception raised"

echo "=== Wave6b: failClosed wiring tests ==="

# --- Test 1: loadKernelScope(path, failClosed=true) raises on missing file ---
block:
  let lockFile = getTempDir() / "axiom_wave6b_missing" & $getCurrentProcessId() & ".lock"
  expectRaises(proc() =
    discard loadKernelScope(lockFile, failClosed = true)
  )
  echo "Test 1 PASSED: loadKernelScope(failClosed=true) raises on missing lock file"

# --- Test 2: loadKernelScope(path, failClosed=true) raises on corrupt JSON ---
block:
  let d = getTempDir() / "axiom_wave6b_corrupt" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  writeFile(lockFile, "NOT VALID JSON {{{{{")
  expectRaises(proc() =
    discard loadKernelScope(lockFile, failClosed = true)
  )
  echo "Test 2 PASSED: loadKernelScope(failClosed=true) raises on corrupt lock file"

# --- Test 3: loadKernelScope(path, failClosed=true) raises on missing kernel_symbols ---
block:
  let d = getTempDir() / "axiom_wave6b_no_field" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  let jsonContent = %*{
    "kernel_total": 5,
    "vksTotal": 3
  }
  writeFile(lockFile, $jsonContent)
  expectRaises(proc() =
    discard loadKernelScope(lockFile, failClosed = true)
  )
  echo "Test 3 PASSED: loadKernelScope(failClosed=true) raises when kernel_symbols field is missing"

# --- Test 4: loadKernelScope(path, failClosed=true) raises on empty kernel_symbols ---
block:
  let d = getTempDir() / "axiom_wave6b_empty_symbols" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  let jsonContent = %*{
    "kernel_total": 0,
    "vksTotal": 0,
    "kernel_symbols": []
  }
  writeFile(lockFile, $jsonContent)
  expectRaises(proc() =
    discard loadKernelScope(lockFile, failClosed = true)
  )
  echo "Test 4 PASSED: loadKernelScope(failClosed=true) raises on empty kernel_symbols"

# --- Test 5: getCanonicalVkdMetrics returns failed=true when lock is missing ---
block:
  let d = getTempDir() / "axiom_wave6b_metrics_fail" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  # Deliberately do NOT create the lock file
  let metrics = getCanonicalVkdMetrics(d)
  expect(metrics.failed == true, "getCanonicalVkdMetrics: failed==true when lock is missing")
  expect(metrics.totalCount == 0, "getCanonicalVkdMetrics: totalCount==0 on failure (not negative)")
  echo "Test 5 PASSED: getCanonicalVkdMetrics returns failed=true on missing lock"

# --- Test 6: getCanonicalVkdMetrics returns failed=true when lock is corrupt ---
block:
  let d = getTempDir() / "axiom_wave6b_metrics_corrupt" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  writeFile(lockFile, "CORRUPT DATA")
  let metrics = getCanonicalVkdMetrics(d)
  expect(metrics.failed == true, "getCanonicalVkdMetrics: failed==true when lock is corrupt")
  echo "Test 6 PASSED: getCanonicalVkdMetrics returns failed=true on corrupt lock"

# --- Test 7: loadKernelScope(path, failClosed=false) still degrades (backward compat) ---
block:
  let lockFile = getTempDir() / "axiom_wave6b_degrade" & $getCurrentProcessId() & ".lock"
  let scope = loadKernelScope(lockFile, failClosed = false)
  expect(scope.kernelTotal == 0, "failClosed=false: missing lock degrades to kernelTotal==0")
  expect(scope.kernelSymbols.len == 0, "failClosed=false: missing lock degrades to empty symbols")
  echo "Test 7 PASSED: loadKernelScope(failClosed=false) preserves degraded fallback"

echo ""
if failures == 0:
  echo "=== All Wave6b failClosed wiring tests PASSED ==="
else:
  echo "=== " & $failures & " Wave6b failClosed wiring test(s) FAILED ==="
  quit(1)
