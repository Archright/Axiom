@generated @high
Feature: semantic_alias_mapper
  # generated | src/gate/semantic_alias_mapper.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/semantic_alias_mapper" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types SemanticGateAlias
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/semantic_alias_mapper" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type SemanticGateAlias is instantiable
    Given the module "gate/semantic_alias_mapper" is loaded
    Then type SemanticGateAlias should be instantiable

  Scenario: func toSemanticAlias is callable
    Given the module "gate/semantic_alias_mapper" is loaded
    Then func toSemanticAlias should return a valid value

  Scenario: func toDisplayName is callable
    Given the module "gate/semantic_alias_mapper" is loaded
    Then func toDisplayName should return a valid value

  Scenario: func toInternalName is callable
    Given the module "gate/semantic_alias_mapper" is loaded
    Then func toInternalName should return a valid value
