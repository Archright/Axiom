@generated @high
Feature: gate_rules_normalization
  # generated | src/gate/gate_rules_normalization.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/gate_rules_normalization" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/gate_rules_normalization" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func normalizedEntries is callable
    Given the module "gate/gate_rules_normalization" is loaded
    Then func normalizedEntries should return a valid value

  Scenario: func normalizedResources is callable
    Given the module "gate/gate_rules_normalization" is loaded
    Then func normalizedResources should return a valid value

  Scenario: func normalizedMutations is callable
    Given the module "gate/gate_rules_normalization" is loaded
    Then func normalizedMutations should return a valid value

  Scenario: func moduleStem is callable
    Given the module "gate/gate_rules_normalization" is loaded
    Then func moduleStem should return a valid value

  Scenario: func isCliCompositionRoot is callable
    Given the module "gate/gate_rules_normalization" is loaded
    Then func isCliCompositionRoot should return a valid value

  Scenario: func isDependencyBudgetBoundary is callable
    Given the module "gate/gate_rules_normalization" is loaded
    Then func isDependencyBudgetBoundary should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
