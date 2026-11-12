@generated @critical
Feature: refinement_predicate
  # generated | src/core/logic/refinement_predicate.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/logic/refinement_predicate" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/logic/refinement_predicate" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs hasNegativeTopToken, hasBoundGuardToken, subjectExpr, predicateExpr, hasTopValidityProtection, isSpecialBitPattern
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func hasNegativeTopToken is callable
    Given the module "core/logic/refinement_predicate" is loaded
    Then func hasNegativeTopToken should return a valid value

  Scenario: func hasBoundGuardToken is callable
    Given the module "core/logic/refinement_predicate" is loaded
    Then func hasBoundGuardToken should return a valid value

  Scenario: func subjectExpr is callable
    Given the module "core/logic/refinement_predicate" is loaded
    Then func subjectExpr should return a valid value

  Scenario: func predicateExpr is callable
    Given the module "core/logic/refinement_predicate" is loaded
    Then func predicateExpr should return a valid value

  Scenario: func hasTopValidityProtection is callable
    Given the module "core/logic/refinement_predicate" is loaded
    Then func hasTopValidityProtection should return a valid value

  Scenario: func isSpecialBitPattern is callable
    Given the module "core/logic/refinement_predicate" is loaded
    Then func isSpecialBitPattern should return a valid value
