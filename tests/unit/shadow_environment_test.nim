## Tests for ShadowEnvironment — env override/restore, temp dir creation/cleanup

import std/[os, strutils, tables]
import infrastructure/shadow_environment

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

var testCount = 0
var passCount = 0

template check(condition: bool, msg: string) =
  inc testCount
  if condition:
    inc passCount
  else:
    echo "FAIL: " & msg

# ---------------------------------------------------------------------------
# Test: newShadowEnvironment construction
# ---------------------------------------------------------------------------

block:
  var overrides = initTable[string, string]()
  overrides["TEST_KEY_A"] = "value_a"
  overrides["TEST_KEY_B"] = "value_b"

  let env = newShadowEnvironment(
    overrides = overrides,
    excludes = @["TEST_KEY_B"],
    cleanupOnExit = false
  )

  check(env.envOverrides.len == 2, "should have 2 overrides")
  check(env.envExcludes.len == 1, "should have 1 exclude")
  check(not env.cleanupOnExit, "cleanupOnExit should be false")
  check(env.tempDir.len == 0, "tempDir should be empty before init")

# ---------------------------------------------------------------------------
# Test: isExcluded
# ---------------------------------------------------------------------------

block:
  let env = newShadowEnvironment(
    overrides = initTable[string, string](),
    excludes = @["EXCLUDED_VAR"]
  )

  check(env.isExcluded("EXCLUDED_VAR"), "should detect excluded var")
  check(not env.isExcluded("NORMAL_VAR"), "should not exclude normal var")
  check(not env.isExcluded(""), "empty string should not be excluded")

# ---------------------------------------------------------------------------
# Test: activeOverrides filters exclusions
# ---------------------------------------------------------------------------

block:
  var overrides = initTable[string, string]()
  overrides["KEEP"] = "yes"
  overrides["DROP"] = "no"

  let env = newShadowEnvironment(
    overrides = overrides,
    excludes = @["DROP"]
  )

  let active = env.activeOverrides()
  check(active.len == 1, "activeOverrides should have 1 entry, got " & $active.len)
  check("KEEP" in active, "should contain KEEP")
  check("DROP" notin active, "should not contain DROP")

# ---------------------------------------------------------------------------
# Test: collectOriginalValues
# ---------------------------------------------------------------------------

block:
  # Set a known env var
  putEnv("SHADOW_TEST_ORIG", "original_value")

  var overrides = initTable[string, string]()
  overrides["SHADOW_TEST_ORIG"] = "new_value"
  overrides["SHADOW_TEST_EXCL"] = "should_not_collect"

  let env = newShadowEnvironment(
    overrides = overrides,
    excludes = @["SHADOW_TEST_EXCL"]
  )

  let originals = env.collectOriginalValues()
  check("SHADOW_TEST_ORIG" in originals, "should capture original value")
  check(originals["SHADOW_TEST_ORIG"] == "original_value", "original value mismatch")
  check("SHADOW_TEST_EXCL" notin originals, "excluded var should not be collected")

  # Cleanup
  delEnv("SHADOW_TEST_ORIG")

# ---------------------------------------------------------------------------
# Test: applyEnvVars and restoreEnvVars
# ---------------------------------------------------------------------------

block:
  # Ensure clean state
  delEnv("SHADOW_TEST_APPLY")
  let beforeValue = getEnv("SHADOW_TEST_APPLY")
  check(beforeValue.len == 0, "SHADOW_TEST_APPLY should not exist before test")

  var overrides = initTable[string, string]()
  overrides["SHADOW_TEST_APPLY"] = "applied_value"

  let env = newShadowEnvironment(overrides = overrides)
  let original = env.collectOriginalValues()

  env.applyEnvVars()
  let afterApply = getEnv("SHADOW_TEST_APPLY")
  check(afterApply == "applied_value", "env var should be applied, got: " & afterApply)

  env.restoreEnvVars(original)
  let afterRestore = getEnv("SHADOW_TEST_APPLY")
  check(afterRestore.len == 0, "env var should be removed after restore")

# ---------------------------------------------------------------------------
# Test: makeTempDir creation
# ---------------------------------------------------------------------------

block:
  let tempDir = makeTempDir("axiom_test_shadow_")
  check(tempDir.len > 0, "temp dir path should not be empty")
  check(dirExists(tempDir), "temp dir should exist: " & tempDir)
  check(tempDir.startsWith("/tmp/"), "temp dir should be under /tmp/")
  check("axiom_test_shadow_" in tempDir, "temp dir should have correct prefix")

  # Cleanup
  if dirExists(tempDir):
    removeDir(tempDir)
  check(not dirExists(tempDir), "temp dir should be removed after cleanup")

# ---------------------------------------------------------------------------
# Test: cleanup removes temp dir
# ---------------------------------------------------------------------------

block:
  var env = newShadowEnvironment(
    overrides = initTable[string, string](),
    cleanupOnExit = true
  )
  env.init()
  check(env.tempDir.len > 0, "tempDir should be set after init")
  check(dirExists(env.tempDir), "temp dir should exist after init")

  env.cleanup()
  check(not dirExists(env.tempDir), "temp dir should be removed after cleanup")

# ---------------------------------------------------------------------------
# Test: withShadow sets, runs, and restores
# ---------------------------------------------------------------------------

block:
  # Clean state
  delEnv("SHADOW_TEST_WITH")
  let beforeVal = getEnv("SHADOW_TEST_WITH")
  check(beforeVal.len == 0, "SHADOW_TEST_WITH should not exist before withShadow")

  var overrides = initTable[string, string]()
  overrides["SHADOW_TEST_WITH"] = "shadow_value"

  var env = newShadowEnvironment(
    overrides = overrides,
    cleanupOnExit = true
  )

  var capturedValue = ""
  let res = env.withShadow(proc(e: ShadowEnvironment): string =
    capturedValue = getEnv("SHADOW_TEST_WITH")
    check(capturedValue == "shadow_value", "env should be set inside withShadow")
    "done"
  )

  check(res == "done", "withShadow should return body result")
  check(capturedValue == "shadow_value", "env should have been set during body")

  # After withShadow: env should be restored
  let afterVal = getEnv("SHADOW_TEST_WITH")
  check(afterVal.len == 0, "env should be restored after withShadow")
  check(not dirExists(env.tempDir), "temp dir should be cleaned up")

# ---------------------------------------------------------------------------
# Test: withShadow exception safety — env still restored
# ---------------------------------------------------------------------------

block:
  delEnv("SHADOW_TEST_EXC")
  var overrides = initTable[string, string]()
  overrides["SHADOW_TEST_EXC"] = "exc_value"

  var env = newShadowEnvironment(
    overrides = overrides,
    cleanupOnExit = true
  )

  try:
    discard env.withShadow(proc(e: ShadowEnvironment): string =
      let val = getEnv("SHADOW_TEST_EXC")
      check(val == "exc_value", "env should be set even when body will throw")
      raise newException(CatchableError, "test exception")
    )
  except CatchableError:
    discard

  let afterExc = getEnv("SHADOW_TEST_EXC")
  check(afterExc.len == 0, "env should be restored even after exception")

# ---------------------------------------------------------------------------
# Test: multiple overrides
# ---------------------------------------------------------------------------

block:
  var overrides = initTable[string, string]()
  overrides["MULTI_A"] = "alpha"
  overrides["MULTI_B"] = "beta"
  overrides["MULTI_C"] = "gamma"

  var env = newShadowEnvironment(overrides = overrides)

  var allSet = false
  discard env.withShadow(proc(e: ShadowEnvironment): string =
    allSet = getEnv("MULTI_A") == "alpha" and
             getEnv("MULTI_B") == "beta" and
             getEnv("MULTI_C") == "gamma"
    "ok"
  )

  check(allSet, "all multiple overrides should be set simultaneously")

  check(getEnv("MULTI_A").len == 0, "MULTI_A should be restored")
  check(getEnv("MULTI_B").len == 0, "MULTI_B should be restored")
  check(getEnv("MULTI_C").len == 0, "MULTI_C should be restored")

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "ShadowEnvironment tests: " & $passCount & "/" & $testCount & " passed"
if passCount < testCount:
  quit(1)
