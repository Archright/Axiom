@generated @critical
Feature: lean_diagnostic
  # generated | src/core/logic/lean_diagnostic.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/logic/lean_diagnostic" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/logic/lean_diagnostic" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs hasErrors, hasWarnings, isNearLine, diagnosticKind, diagnosticKind, diagnosticHint, firstGoalSummary, computeProofAttemptTimeoutMs, analyzeSpecComplexity, buildInitialTacticStrategy, inferMissingHypotheses
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func hasErrors is callable
    Given the module "core/logic/lean_diagnostic" is loaded
    Then func hasErrors should return a valid value

  Scenario: func hasWarnings is callable
    Given the module "core/logic/lean_diagnostic" is loaded
    Then func hasWarnings should return a valid value

  Scenario: func isNearLine is callable
    Given the module "core/logic/lean_diagnostic" is loaded
    Then func isNearLine should return a valid value

  Scenario: func diagnosticKind is callable
    Given the module "core/logic/lean_diagnostic" is loaded
    Then func diagnosticKind should return a valid value

  Scenario: func diagnosticKind is callable
    Given the module "core/logic/lean_diagnostic" is loaded
    Then func diagnosticKind should return a valid value

  Scenario: func diagnosticHint is callable
    Given the module "core/logic/lean_diagnostic" is loaded
    Then func diagnosticHint should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
