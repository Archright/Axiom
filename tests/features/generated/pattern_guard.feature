@generated @critical
Feature: pattern_guard
  # generated | src/core/diagnostics/pattern_guard.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/diagnostics/pattern_guard" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types PatternKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/diagnostics/pattern_guard" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs detectSideEffects, detectIoCalls, detectExistingInvariant, detectExistingMeasure, countCallDepth, detectDivisionByVariable, hasLoop, hasRecursion, collectSideEffectEvidence, formatApplicabilityReport
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type PatternKind is instantiable
    Given the module "core/diagnostics/pattern_guard" is loaded
    Then type PatternKind should be instantiable

  Scenario: func detectSideEffects is callable
    Given the module "core/diagnostics/pattern_guard" is loaded
    Then func detectSideEffects should return a valid value

  Scenario: func detectIoCalls is callable
    Given the module "core/diagnostics/pattern_guard" is loaded
    Then func detectIoCalls should return a valid value

  Scenario: func detectExistingInvariant is callable
    Given the module "core/diagnostics/pattern_guard" is loaded
    Then func detectExistingInvariant should return a valid value

  Scenario: func detectExistingMeasure is callable
    Given the module "core/diagnostics/pattern_guard" is loaded
    Then func detectExistingMeasure should return a valid value

  Scenario: func countCallDepth is callable
    Given the module "core/diagnostics/pattern_guard" is loaded
    Then func countCallDepth should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
