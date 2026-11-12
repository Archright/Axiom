@generated @high
Feature: architecture_ast_facts
  # generated | src/gate/architecture_ast_facts.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/architecture_ast_facts" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types FuncDeclKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/architecture_ast_facts" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type FuncDeclKind is instantiable
    Given the module "gate/architecture_ast_facts" is loaded
    Then type FuncDeclKind should be instantiable

  Scenario: func axiomEffectOf is callable
    Given the module "gate/architecture_ast_facts" is loaded
    Then func axiomEffectOf should return a valid value
