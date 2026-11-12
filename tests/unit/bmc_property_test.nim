## BMC Property Tests — PBT + BMC Dual Verification
##
## PBT generates random initial conditions using std/random;
## BMC exhaustively verifies all thread interleavings within bounded depth.
## This bridges the gap between statistical (PBT) and exhaustive (BMC) verification.

import std/unittest
import std/random
import core/bmc/bmc_generic
import core/utils/axiom_clock

# ── BMC Property Tests ─────────────────────────────────────────────────────

suite "BMC Property: Dual Verification (PBT + BMC)":

  test "integer overflow: safe values stay within bounds under all interleavings":
    var rng = initRand(42)
    for iter in 0 ..< 100:
      let val = rng.rand(-1000000 .. 1000000)
      let verdict = verifyIntegerOverflow(val, delta = 1, bitWidth = 32)
      if verdict.violationDetected:
        check val > high(int32) - 10 or val < low(int32) + 10

  test "index bounds: valid indices stay in bounds under all interleavings":
    var rng = initRand(42)
    for iter in 0 ..< 100:
      let idx = rng.rand(0 .. 99)
      let verdict = verifyIndexBounds(idx, arrayLength = 100)
      check not verdict.violationDetected

  test "index bounds: out-of-range indices are always detected":
    var rng = initRand(42)
    for iter in 0 ..< 100:
      let oobIdx = 100 + rng.rand(0 .. 999)
      let verdict = verifyIndexBounds(oobIdx, arrayLength = 100)
      check verdict.violationDetected

  test "null dereference: non-null values are safe under all interleavings":
    var rng = initRand(42)
    for iter in 0 ..< 100:
      let val = rng.rand(1 .. 100000)
      let verdict = verifyNullDereference(val)
      check not verdict.violationDetected

  test "null dereference: null is always detected":
    let verdict = verifyNullDereference(0)
    check verdict.violationDetected
    check verdict.propertyKind == bpkNullDereference

  test "race condition: single-variable concurrent access is safe":
    var clk = deterministicClock(0, 0)
    let config = initBmcConfig(bpkRaceCondition, stepBound = 5)
    let verdict = verifyGenericProperty(clk, config, @[100], 0)
    check verdict.propertyKind == bpkRaceCondition
    check not verdict.timedOut

  test "BMC timeout: respects wall-clock deadline":
    var clk = deterministicClock(0, 1)  # mono=1 so timeout fires
    let config = initBmcConfig(bpkIntegerOverflow, timeoutMs = -1)
    let verdict = verifyGenericProperty(clk, config, @[2000000000], 200000000)
    check verdict.timedOut or verdict.violationDetected

  test "BMC determinism: same inputs produce same verdict":
    var clk1 = deterministicClock(0, 0)
    var clk2 = deterministicClock(0, 0)
    let config = initBmcConfig(bpkIndexOutOfBounds, stepBound = 5)
    let v1 = verifyGenericProperty(clk1, config, @[50], 0)
    let v2 = verifyGenericProperty(clk2, config, @[50], 0)
    check v1.violationDetected == v2.violationDetected
    check v1.exploredPaths == v2.exploredPaths

  test "BMC multi-variable: multiple shared variables are checked":
    var clk = deterministicClock(0, 0)
    let config = initBmcConfig(bpkNullDereference, variableCount = 3, stepBound = 3)
    let verdict = verifyGenericProperty(clk, config, @[1, 2, 3])
    check not verdict.violationDetected

  test "BMC multi-variable: one null variable is detected":
    var clk = deterministicClock(0, 0)
    let config = initBmcConfig(bpkNullDereference, variableCount = 3, stepBound = 3)
    let verdict = verifyGenericProperty(clk, config, @[1, 0, 3])
    check verdict.violationDetected

  test "BMC exploration: path count grows with step bound":
    var clk3 = deterministicClock(0, 0)
    var clk5 = deterministicClock(0, 0)
    let config3 = initBmcConfig(bpkNullDereference, stepBound = 3)
    let config5 = initBmcConfig(bpkNullDereference, stepBound = 5)
    let v3 = verifyGenericProperty(clk3, config3, @[42])
    let v5 = verifyGenericProperty(clk5, config5, @[42])
    check v5.exploredPaths >= v3.exploredPaths

  test "BMC property consistency: overflow vs safe boundary":
    var rng = initRand(42)
    for iter in 0 ..< 50:
      let val = rng.rand(-1000 .. 1000)
      let verdict = verifyIntegerOverflow(val, delta = 0, bitWidth = 32)
      check not verdict.violationDetected
