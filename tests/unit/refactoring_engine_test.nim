## Unit tests for refactoring_engine.nim — f×g×h rule engine + escape strategy.

import std/[strutils, unittest]
import core/diagnostics/refactoring_engine

suite "RefactoringEngine":
  test "classifySignals detects quantifier excess":
    let signals = classifySignals(
      quantifierCount = 2, nonLinearArithmeticCount = 0,
      dependencyDepth = 0, couplingScore = 0,
      hasLoop = false, hasRecursion = false
    )
    check signals.len == 1
    check signals[0] == rskQuantifierExcess

  test "classifySignals detects multiple signals":
    let signals = classifySignals(
      quantifierCount = 1, nonLinearArithmeticCount = 1,
      dependencyDepth = 5, couplingScore = 10,
      hasLoop = true, hasRecursion = false
    )
    check signals.len == 5

  test "classifySignals returns empty for clean code":
    let signals = classifySignals(0, 0, 0, 0, false, false)
    check signals.len == 0

  test "generateTemplates produces correct patterns":
    let templates = generateTemplates(@[rskQuantifierExcess, rskNonLinearArithmetic])
    check templates.len == 2
    check templates[0].pattern == rpkExtractPureFunction or templates[0].pattern == rpkLinearizeVariables

  test "RefactoringStagnation escalates after maxFailures":
    var stagnation = initRefactoringStagnation(maxFailures = 3)
    check stagnation.escalated == false
    recordFailure(stagnation, "Z3 rejected transformation A")
    check stagnation.escalated == false
    check stagnation.consecutiveFailures == 1
    recordFailure(stagnation, "Z3 rejected transformation B")
    check stagnation.escalated == false
    recordFailure(stagnation, "Z3 rejected transformation C")
    check stagnation.escalated == true
    check stagnation.consecutiveFailures == 3
    check stagnation.escalationReport.len > 0

  test "RefactoringStagnation resets on success":
    var stagnation = initRefactoringStagnation(maxFailures = 3)
    recordFailure(stagnation, "fail 1")
    recordFailure(stagnation, "fail 2")
    check stagnation.consecutiveFailures == 2
    recordSuccess(stagnation)
    check stagnation.consecutiveFailures == 0
    check stagnation.escalated == false

  test "formatEscalationReport contains all required sections":
    var stagnation = initRefactoringStagnation(maxFailures = 2)
    recordFailure(stagnation, "fail 1")
    recordFailure(stagnation, "fail 2")
    let templates = generateTemplates(@[rskQuantifierExcess])
    let report = formatEscalationReport(stagnation, "func test() = discard", templates, @["counterexample 1"])
    check "ESCALATION REPORT" in report
    check "Original Code" in report
    check "Attempted Transformations" in report
    check "Recommendation" in report

  test "patternNimHints are non-empty":
    for kind in RefactoringPatternKind.low .. RefactoringPatternKind.high:
      check patternNimHints[kind].len > 0
