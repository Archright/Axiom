@generated @critical
Feature: pbt_gate
  # generated | src/core/test_support/pbt_gate.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/test_support/pbt_gate" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types HoareProperty, name, precondition, command, postcondition
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/test_support/pbt_gate" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs verifyHoare, verifyHoareSeq
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type HoareProperty is instantiable
    Given the module "core/test_support/pbt_gate" is loaded
    Then type HoareProperty should be instantiable

  Scenario: type name is instantiable
    Given the module "core/test_support/pbt_gate" is loaded
    Then type name should be instantiable

  Scenario: type precondition is instantiable
    Given the module "core/test_support/pbt_gate" is loaded
    Then type precondition should be instantiable

  Scenario: type command is instantiable
    Given the module "core/test_support/pbt_gate" is loaded
    Then type command should be instantiable

  Scenario: type postcondition is instantiable
    Given the module "core/test_support/pbt_gate" is loaded
    Then type postcondition should be instantiable

  Scenario: func verifyHoare is callable
    Given the module "core/test_support/pbt_gate" is loaded
    Then func verifyHoare should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
