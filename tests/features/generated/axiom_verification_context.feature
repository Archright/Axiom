@generated @critical
Feature: axiom_verification_context
  # generated | src/core/logic/axiom_verification_context.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/logic/axiom_verification_context" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/logic/axiom_verification_context" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs conjoinConstraints, emitAssertionLines, emitHornScript
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func conjoinConstraints is callable
    Given the module "core/logic/axiom_verification_context" is loaded
    Then func conjoinConstraints should return a valid value

  Scenario: func emitAssertionLines is callable
    Given the module "core/logic/axiom_verification_context" is loaded
    Then func emitAssertionLines should return a valid value

  Scenario: func emitHornScript is callable
    Given the module "core/logic/axiom_verification_context" is loaded
    Then func emitHornScript should return a valid value
