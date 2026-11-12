@generated @high
Feature: gate_rules_module_classifier
  # generated | src/gate/gate_rules_module_classifier.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/gate_rules_module_classifier" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/gate_rules_module_classifier" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func classifyModuleByPath is callable
    Given the module "gate/gate_rules_module_classifier" is loaded
    Then func classifyModuleByPath should return a valid value

  Scenario: func buildModulePathMap is callable
    Given the module "gate/gate_rules_module_classifier" is loaded
    Then func buildModulePathMap should return a valid value

  Scenario: func isConcreteModule is callable
    Given the module "gate/gate_rules_module_classifier" is loaded
    Then func isConcreteModule should return a valid value

  Scenario: func isAbstractModule is callable
    Given the module "gate/gate_rules_module_classifier" is loaded
    Then func isAbstractModule should return a valid value

  Scenario: func extractModuleStemFromDependency is callable
    Given the module "gate/gate_rules_module_classifier" is loaded
    Then func extractModuleStemFromDependency should return a valid value

  Scenario: func isLikelyConcreteName is callable
    Given the module "gate/gate_rules_module_classifier" is loaded
    Then func isLikelyConcreteName should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
