import std/algorithm
import core/trusted/scope_identity
import core/trusted/semantic_profile

## Wave 0e — canonical scope identity tests.
## Verifies: order-independence, determinism, content sensitivity, config digest.

var failures = 0
proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

echo "=== scope_identity tests ==="

block:
  # Same semantic scope, different symbol ORDER in the lock -> same digest.
  let a = scopeInputFromSynthetic(
    @["mod2::fun_b", "mod1::fun_a"], @["mod1::skip"], 5, 3,
    SemanticProfileV1Hash, "v3")
  let b = scopeInputFromSynthetic(
    @["mod1::fun_a", "mod2::fun_b"], @["mod1::skip"], 5, 3,
    SemanticProfileV1Hash, "v3")
  expect(canonicalScopeDigest(a) == canonicalScopeDigest(b),
         "scope digest order-independent (canonical semantic serialize)")
  echo "Test 1 PASSED: canonical scope digest order-independent"

# Determinism
block:
  let a = scopeInputFromSynthetic(@["m::f"], @[], 2, 1, "prof", "v3")
  let b = scopeInputFromSynthetic(@["m::f"], @[], 2, 1, "prof", "v3")
  expect(canonicalScopeDigest(a) == canonicalScopeDigest(b),
         "scope digest deterministic")
  echo "Test 2 PASSED: scope digest deterministic"

# Content sensitivity
block:
  let base = scopeInputFromSynthetic(@["m::f"], @[], 2, 1, "prof", "v3")
  let changedKernel = scopeInputFromSynthetic(@["m::f", "m::g"], @[], 2, 1, "prof", "v3")
  let changedExempt = scopeInputFromSynthetic(@["m::f"], @["m::x"], 2, 1, "prof", "v3")
  let changedTotal = scopeInputFromSynthetic(@["m::f"], @[], 3, 1, "prof", "v3")
  let changedVks = scopeInputFromSynthetic(@["m::f"], @[], 2, 2, "prof", "v3")
  let changedProfile = scopeInputFromSynthetic(@["m::f"], @[], 2, 1, "other", "v3")
  let changedProto = scopeInputFromSynthetic(@["m::f"], @[], 2, 1, "prof", "v4")
  expect(canonicalScopeDigest(base) != canonicalScopeDigest(changedKernel), "kernel add changes digest")
  expect(canonicalScopeDigest(base) != canonicalScopeDigest(changedExempt), "exempt changes digest")
  expect(canonicalScopeDigest(base) != canonicalScopeDigest(changedTotal), "kernelTotal changes digest")
  expect(canonicalScopeDigest(base) != canonicalScopeDigest(changedVks), "vksTotal changes digest")
  expect(canonicalScopeDigest(base) != canonicalScopeDigest(changedProfile), "profile changes digest")
  expect(canonicalScopeDigest(base) != canonicalScopeDigest(changedProto), "protocol changes digest")
  echo "Test 3 PASSED: scope digest content-sensitive across all components"

# configIdentityDigest
block:
  expect(configIdentityDigest("p", "s") == configIdentityDigest("p", "s"),
         "config identity deterministic")
  expect(configIdentityDigest("p", "s") != configIdentityDigest("p", "s2"),
         "config identity scope-sensitive")
  echo "Test 4 PASSED: config identity digest"

echo ""
if failures == 0:
  echo "=== All scope_identity tests PASSED ==="
else:
  echo "=== " & $failures & " scope_identity test(s) FAILED ==="
  quit(1)