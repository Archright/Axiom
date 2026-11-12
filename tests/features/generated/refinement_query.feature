@generated @critical
Feature: refinement_query
  # generated | src/core/logic/refinement_query.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/logic/refinement_query" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/logic/refinement_query" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs buildInvariantAssertions, computeUnsatCore
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func buildInvariantAssertions is callable
    Given the module "core/logic/refinement_query" is loaded
    Then func buildInvariantAssertions should return a valid value

  Scenario: func computeUnsatCore is callable
    Given the module "core/logic/refinement_query" is loaded
    Then func computeUnsatCore should return a valid value
