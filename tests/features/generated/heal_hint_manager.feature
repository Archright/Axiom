@generated @critical
Feature: heal_hint_manager
  # generated | src/core/contract/heal_hint_manager.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/contract/heal_hint_manager" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/contract/heal_hint_manager" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs acceptVerifiedAxiom
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func acceptVerifiedAxiom is callable
    Given the module "core/contract/heal_hint_manager" is loaded
    Then func acceptVerifiedAxiom should return a valid value
