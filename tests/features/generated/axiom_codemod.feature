@generated @high
Feature: axiom_codemod
  # generated | src/gate/runners/axiom_codemod.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/runners/axiom_codemod" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/runners/axiom_codemod" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func contentHashHex is callable
    Given the module "gate/runners/axiom_codemod" is loaded
    Then func contentHashHex should return a valid value
