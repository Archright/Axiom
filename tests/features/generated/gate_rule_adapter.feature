@generated @high
Feature: gate_rule_adapter
  # generated | src/verification/gate_rule_adapter.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/gate_rule_adapter" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/gate_rule_adapter" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
