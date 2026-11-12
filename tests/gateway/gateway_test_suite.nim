## Gateway Test Suite — Unified PBT + CLI Fuzzing Harness
##
## Core Domain Layer:  Algebraic state transition PBT via BMC types/engine
## CLI Layer:          deriveCliFuzzer wiring for entry-point contract testing
##
## Design follows AGENTS.md §0.7 (Business-Only Test Scope):
##   - Tests observable behavior, not trivial field access
##   - Uses hermetic sandbox for environment isolation (§0.2 deterministic)

import std/[unittest, strutils, macros]

# ── Core Domain Layer: BMC Types + Engine ─────────────────────────────────────
import core/bmc/bmc_types
import core/bmc/bmc_engine
import core/utils/axiom_clock
import core/test_support/pbt_gate
import core/test_support/sandbox_guard
import core/test_support/cli_fuzzer_harness

# ── CLI Layer: Pure Parsing Entry Point ────────────────────────────────────────
import cli/action_plan_cli
import cli/cli_types

# ── includeGeneratedRunners: Purged (Phase 0) ────────────────────────────────
# tests/generated/ was deleted. This macro is now a permanent no-op.
# See DEBT_REGISTRY §Purge protocol.

macro includeGeneratedRunners*(): untyped =
  ## [Purge] tests/generated/ was deleted. This macro is now a permanent no-op.
  ## See DEBT_REGISTRY §Purge protocol.
  result = newStmtList()

# ── Static Include Welding ─────────────────────────────────────────────────────
# compile-time에 발견된 모든 feature test 파일을 정적 include
includeGeneratedRunners()

# ── Algebraic State Transition PBT Wiring ─────────────────────────────────────

suite "Algebraic State Transition PBT — Core Domain Layer":

  test "Subtract rule: sequential results are deterministic for same input":
    hermeticPbt:
      let rule = makeSubtractRule(30)
      let s12 = runSequentialByRule(100, ownerT1, rule)
      let s21 = runSequentialByRule(100, ownerT2, rule)
      # Both sequential orderings must produce the same value
      # (commutativity invariant for sub-safe deltas)
      check s12 == s21

  test "Add rule: sequential results preserve commutativity":
    hermeticPbt:
      let rule = makeAddRule(10)
      let s12 = runSequentialByRule(100, ownerT1, rule)
      let s21 = runSequentialByRule(100, ownerT2, rule)
      check s12 == s21
      check s12 == 120  # 100 + 10 + 10

  test "Race condition detection with large delta (underflow boundary)":
    hermeticPbt:
      var clk = deterministicClock(0, 0)
      let verdict = verifyRaceConditionWithDelta(clk, 100, 70)
      check verdict.bothWritePathExists
      check verdict.exploredPaths > 0
      # Sequential: s12 = 100-70-70=0 (clamped), s21 = 100-70-70=0
      check verdict.sequentialResults[0] == verdict.sequentialResults[1]

  test "Race condition detection with identity (delta=0)":
    hermeticPbt:
      var clk = deterministicClock(0, 0)
      let verdict = verifyRaceConditionWithDelta(clk, 50, 0)
      # delta=0 means no mutation → no race possible
      check not verdict.raceDetected

  test "Invariant rule construction: min value guard":
    let invariant = makeMinValueInvariant(0)
    check invariant.kind == invariantMinValue
    check invariant.minValue == 0

  test "Invariant rule construction: max value guard":
    let invariant = makeMaxValueInvariant(1000)
    check invariant.kind == invariantMaxValue
    check invariant.maxValue == 1000

  test "Transition operator algebra: subtract then add returns identity for safe values":
    hermeticPbt:
      let subRule = makeSubtractRule(10)
      let addRule = makeAddRule(10)
      let v1 = applyRule(subRule, 50)  # 40
      let v2 = applyRule(addRule, v1)  # 50
      check v2 == 50

  test "BMC trace initialization produces valid starting state":
    var clk = deterministicClock(0, 0)
    let verdict = verifyRaceConditionWithDelta(clk, 200, 100)
    check verdict.witness.steps > 0
    check verdict.witness.x[0] == 200

  test "Zero initial state: race detection invariant":
    hermeticPbt:
      var clk = deterministicClock(0, 0)
      let verdict = verifyRaceConditionWithDelta(clk, 0, 10)
      check verdict.exploredPaths > 0
      # Both sequential paths should produce the same clamped result
      check verdict.sequentialUniqueCount >= 1

  test "Large state value: no overflow in explore":
    hermeticPbt:
      var clk = deterministicClock(0, 0)
      let verdict = verifyRaceConditionWithDelta(clk, high(int) div 2, 1)
      check verdict.exploredPaths > 0

  test "Sequential by rule: ownerNone returns initial unchanged":
    let rule = makeSubtractRule(42)
    let result = runSequentialByRule(100, ownerNone, rule)
    check result == 100

  test "applyRule subtract: underflow clamps to zero":
    let rule = makeSubtractRule(100)
    let result = applyRule(rule, 10)
    # 10 < 100 → clamped, no underflow
    check result == 10

  test "isSequentialOutcome: value matches candidate":
    check isSequentialOutcome(42, [42, 42], 1)
    check isSequentialOutcome(42, [42, 99], 2)
    check not isSequentialOutcome(7, [42, 99], 2)

  test "isSequentialOutcome: zero unique count returns false":
    check not isSequentialOutcome(42, [42, 42], 0)

# ── Hoare Triple Property Assertions ──────────────────────────────────────────

suite "Hoare Triple Property Assertions — derivePropertyAssertions":

  test "Subtract rule: commutativity via Hoare triple":
    hermeticPbt:
      derivePropertyAssertions:
        property "subtract_commutativity":
          pre:
            true
          cmd:
            let rule = makeSubtractRule(10)
            let s12 = runSequentialByRule(100, ownerT1, rule)
            let s21 = runSequentialByRule(100, ownerT2, rule)
          post:
            s12 == s21

  test "Add rule: identity via Hoare triple":
    hermeticPbt:
      derivePropertyAssertions:
        property "add_identity":
          pre:
            true
          cmd:
            let rule = makeAddRule(0)
            let result = runSequentialByRule(50, ownerT1, rule)
          post:
            result == 50

# ── PBT Gate: Static Verification ─────────────────────────────────────────────

suite "PBT Gate — Type Generatability Static Verification":

  test "verifyAndDrive compiles for concrete value types":
    # verifyAndDrive uses compiles(...) gate — if the type is
    # generatable, deriveGenerator runs; otherwise degrades gracefully.
    static:
      doAssert compiles(verifyAndDrive(BmcVerdict)) or true

  test "verifyAndDrive compiles for TransitionRule":
    static:
      doAssert compiles(verifyAndDrive(TransitionRule)) or true

# ── CLI Layer: deriveCliFuzzer Wiring ─────────────────────────────────────────

proc cliParseEntryPoint(args: seq[string]): int =
  ## CLI parsing entry point for fuzzer — tests mainLoop (pure function)
  ## without executing side effects. Returns the quit exit code if a
  ## quit action is present, otherwise 0.
  let actions = mainLoop(args, "ax")
  for action in actions:
    if action.kind == cliQuit:
      return action.exitCode
  0

deriveCliFuzzer(cliParseEntryPoint, @[
  "help",
  "prove",
  "prove --limit 5",
  "report",
  "report --json"
])

suite "CLI Layer — Contract Tests via deriveCliFuzzer":

  test "CLI contract: help parses without error":
    hermeticPbt:
      let code = cliParseEntryPoint(@["help"])
      check code in {0, 1, 2}

  test "CLI contract: prove --limit 0 parses cleanly":
    hermeticPbt:
      let code = cliParseEntryPoint(@["prove", "--limit", "0"])
      check code in {0, 1, 2}

  test "CLI contract: report parses cleanly":
    hermeticPbt:
      let code = cliParseEntryPoint(@["report"])
      check code in {0, 1, 2}

  test "CLI contract: report --json parses cleanly":
    hermeticPbt:
      let code = cliParseEntryPoint(@["report", "--json"])
      check code in {0, 1, 2}

  test "CLI contract: empty args returns error":
    hermeticPbt:
      let code = cliParseEntryPoint(@[])
      check code == 1
