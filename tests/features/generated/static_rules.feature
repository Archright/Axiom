@generated @high
Feature: static_rules
  # generated | src/verification/static_rules.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/static_rules" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types StaticRuleMatch, rule, matchKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/static_rules" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type StaticRuleMatch is instantiable
    Given the module "verification/static_rules" is loaded
    Then type StaticRuleMatch should be instantiable

  Scenario: type rule is instantiable
    Given the module "verification/static_rules" is loaded
    Then type rule should be instantiable

  Scenario: type matchKind is instantiable
    Given the module "verification/static_rules" is loaded
    Then type matchKind should be instantiable

  Scenario: func staticRuleToJson is callable
    Given the module "verification/static_rules" is loaded
    Then func staticRuleToJson should return a valid value

  Scenario: func jsonToStaticRule is callable
    Given the module "verification/static_rules" is loaded
    Then func jsonToStaticRule should return a valid value

  Scenario: func loadStaticRules is callable
    Given the module "verification/static_rules" is loaded
    Then func loadStaticRules should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
