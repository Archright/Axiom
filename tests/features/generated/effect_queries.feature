@generated @high
Feature: effect_queries
  # generated | src/gate/nimtry/effect_queries.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/effect_queries" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types NimtryEffectKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/effect_queries" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type NimtryEffectKind is instantiable
    Given the module "gate/nimtry/effect_queries" is loaded
    Then type NimtryEffectKind should be instantiable
