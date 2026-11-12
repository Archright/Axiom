import std/os
import std/json
import std/tempfiles
import core/proof/proof_integrity

## Wave-Gate: loadKernelScope failClosed parameter (I5 fix).
## Verifies that loadKernelScope with failClosed=true raises on missing/corrupt
## lock files, while failClosed=false preserves the existing degraded-mode behavior.

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

echo "=== loadKernelScope failClosed tests ==="

# --- Test 1: valid lock file returns symbols ---
block:
  let d = getTempDir() / "axiom_scope_test" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  # Write a valid v2-compatible lock file
  let jsonContent = %*{
    "kernel_total": 3,
    "vksTotal": 2,
    "kernel_symbols": ["mod1::funcA", "mod1::funcB", "mod2::funcC"],
    "kernel_exempt_symbols": ["mod1::funcB"]
  }
  writeFile(lockFile, $jsonContent)
  # failClosed=false (default) must return full scope
  let scope = loadKernelScope(lockFile)
  expect(scope.kernelTotal == 3, "valid lock: kernelTotal == 3")
  expect(scope.vksTotal == 2, "valid lock: vksTotal == 2")
  expect(scope.kernelSymbols.len == 3, "valid lock: 3 kernelSymbols")
  expect(scope.kernelSymbols[0] == "mod1::funcA", "valid lock: symbol[0] matches")
  expect(scope.kernelSymbols[1] == "mod1::funcB", "valid lock: symbol[1] matches")
  expect(scope.kernelSymbols[2] == "mod2::funcC", "valid lock: symbol[2] matches")
  expect(scope.kernelExemptSymbols.len == 1, "valid lock: 1 exempt symbol")
  expect(scope.kernelExemptSymbols[0] == "mod1::funcB", "valid lock: exempt symbol matches")
  # failClosed=true must also return full scope for a valid lock
  let scopeStrict = loadKernelScope(lockFile, failClosed = true)
  expect(scopeStrict.kernelSymbols.len == 3, "valid lock + failClosed=true: 3 kernelSymbols")
  expect(scopeStrict.kernelTotal == 3, "valid lock + failClosed=true: kernelTotal == 3")
  echo "Test 1 PASSED: valid lock file returns symbols (both modes)"

# --- Test 2: missing lock file degrades (failClosed=false default) ---
block:
  let lockFile = getTempDir() / "axiom_scope_missing" & $getCurrentProcessId() & ".lock"
  # File does not exist
  let scope = loadKernelScope(lockFile)
  expect(scope.kernelTotal == 0, "missing lock + failClosed=false: kernelTotal == 0")
  expect(scope.kernelSymbols.len == 0, "missing lock + failClosed=false: empty symbols")
  echo "Test 2 PASSED: missing lock degrades (failClosed=false default)"

# --- Test 3: missing lock file fails closed (failClosed=true) ---
block:
  let lockFile = getTempDir() / "axiom_scope_missing_strict" & $getCurrentProcessId() & ".lock"
  # File does not exist — must raise
  expectRaises(proc() =
    discard loadKernelScope(lockFile, failClosed = true)
  )
  echo "Test 3 PASSED: missing lock fails closed (failClosed=true)"

# --- Test 4: corrupt lock file degrades (failClosed=false default) ---
block:
  let d = getTempDir() / "axiom_scope_corrupt" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  writeFile(lockFile, "NOT VALID JSON {{{{{")
  let scope = loadKernelScope(lockFile)
  expect(scope.kernelTotal == 0, "corrupt lock + failClosed=false: kernelTotal == 0")
  expect(scope.kernelSymbols.len == 0, "corrupt lock + failClosed=false: empty symbols")
  echo "Test 4 PASSED: corrupt lock degrades (failClosed=false default)"

# --- Test 5: corrupt lock file fails closed (failClosed=true) ---
block:
  let d = getTempDir() / "axiom_scope_corrupt_strict" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  writeFile(lockFile, "NOT VALID JSON {{{{{")
  expectRaises(proc() =
    discard loadKernelScope(lockFile, failClosed = true)
  )
  echo "Test 5 PASSED: corrupt lock fails closed (failClosed=true)"

# --- Test 6: lock file with empty kernel_symbols fails closed (failClosed=true) ---
block:
  let d = getTempDir() / "axiom_scope_empty_symbols" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  # Valid JSON but kernel_symbols array is empty
  let jsonContent = %*{
    "kernel_total": 0,
    "vksTotal": 0,
    "kernel_symbols": []
  }
  writeFile(lockFile, $jsonContent)
  expectRaises(proc() =
    discard loadKernelScope(lockFile, failClosed = true)
  )
  echo "Test 6 PASSED: empty kernel_symbols fails closed (failClosed=true)"

# --- Test 7: lock file missing kernel_symbols field fails closed (failClosed=true) ---
block:
  let d = getTempDir() / "axiom_scope_no_field" & $getCurrentProcessId()
  if not dirExists(d):
    createDir(d)
  let lockFile = d / "verification_scope.lock"
  # JSON object but no kernel_symbols key
  let jsonContent = %*{
    "kernel_total": 5,
    "vksTotal": 3
  }
  writeFile(lockFile, $jsonContent)
  expectRaises(proc() =
    discard loadKernelScope(lockFile, failClosed = true)
  )
  echo "Test 7 PASSED: missing kernel_symbols field fails closed (failClosed=true)"

echo ""
if failures == 0:
  echo "=== All loadKernelScope failClosed tests PASSED ==="
else:
  echo "=== " & $failures & " loadKernelScope failClosed test(s) FAILED ==="
  quit(1)