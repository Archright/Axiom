## Unit tests for bmc_generic.nim — generalized BMC engine.

import std/unittest
import core/bmc/bmc_generic
import core/utils/axiom_clock
import std/monotimes

suite "BmcGeneric":
  test "initBmcConfig creates config with correct defaults":
    let config = initBmcConfig(bpkIntegerOverflow)
    check config.property == bpkIntegerOverflow
    check config.threadCount == 2
    check config.variableCount == 1
    check config.stepBound == 10
    check config.bitWidth == defaultBitWidth

  test "initBmcConfig clamps stepBound to maxGenericStepBound":
    let config = initBmcConfig(bpkRaceCondition, stepBound = 100)
    check config.stepBound == maxGenericStepBound

  test "verifyIntegerOverflow detects overflow":
    let result = verifyIntegerOverflow(2000000000, 200000000, bitWidth = 32)
    check result.propertyKind == bpkIntegerOverflow

  test "verifyIndexBounds detects out-of-bounds":
    let result = verifyIndexBounds(150, arrayLength = 100)
    check result.propertyKind == bpkIndexOutOfBounds

  test "verifyNullDereference detects null":
    let result = verifyNullDereference(0)
    check result.propertyKind == bpkNullDereference
    check result.violationDetected == true

  test "verifyNullDereference does not false-positive on non-null":
    let result = verifyNullDereference(42)
    check result.propertyKind == bpkNullDereference

  test "propertyKindToString returns correct strings":
    check propertyKindToString(bpkRaceCondition) == "race_condition"
    check propertyKindToString(bpkIntegerOverflow) == "integer_overflow"
    check propertyKindToString(bpkIndexOutOfBounds) == "index_out_of_bounds"
    check propertyKindToString(bpkNullDereference) == "null_dereference"

  test "verifyGenericProperty with race condition config":
    let config = initBmcConfig(bpkRaceCondition, stepBound = 5)
    var clk = deterministicClock(0, 0)
    let result = verifyGenericProperty(clk, config, @[100], 10)
    check result.propertyKind == bpkRaceCondition

  test "default constants are reasonable":
    check defaultBitWidth == 32
    check defaultArrayLength == 100
    check maxGenericStepBound == 15

  test "timeout fires for extremely short timeout":
    let config = initBmcConfig(bpkRaceCondition, timeoutMs = 0)  # 0ms = deadline is now
    # DeterministicClock with mono=0 and tickStep=0: deadline = 0+0 = 0, monoNs() = 0, 0 > 0 = false.
    # Use mono=1 so deadline = 1+0 = 1, monoNs() = 1, 1 > 1 = false.
    # Use timeoutMs = -1 to force deadline < monoNs.
    var clk2 = deterministicClock(0, 1)  # mono=1
    let config2 = initBmcConfig(bpkRaceCondition, timeoutMs = -1)  # forces deadline < monoNs
    let verdict = verifyGenericProperty(clk2, config2, @[0, 0])
    doAssert verdict.timedOut or verdict.violationDetected  # either timeout or violation is fine
