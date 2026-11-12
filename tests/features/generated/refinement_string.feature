@generated @critical
Feature: refinement_string
  # generated | src/core/logic/refinement_string.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/logic/refinement_string" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/logic/refinement_string" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs loopVerdictString, replayActionString, refinementOperatorKindString, computeSourceFingerprint, opcodeSlug, trimCaseLabel, invariantId, encodeBool
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func loopVerdictString is callable
    Given the module "core/logic/refinement_string" is loaded
    Then func loopVerdictString should return a valid value

  Scenario: func replayActionString is callable
    Given the module "core/logic/refinement_string" is loaded
    Then func replayActionString should return a valid value

  Scenario: func refinementOperatorKindString is callable
    Given the module "core/logic/refinement_string" is loaded
    Then func refinementOperatorKindString should return a valid value

  Scenario: func computeSourceFingerprint is callable
    Given the module "core/logic/refinement_string" is loaded
    Then func computeSourceFingerprint should return a valid value

  Scenario: func opcodeSlug is callable
    Given the module "core/logic/refinement_string" is loaded
    Then func opcodeSlug should return a valid value

  Scenario: func trimCaseLabel is callable
    Given the module "core/logic/refinement_string" is loaded
    Then func trimCaseLabel should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
