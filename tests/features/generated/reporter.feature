@generated @high
Feature: reporter
  # generated | src/verification/reporter.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/reporter" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/reporter" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func parseDeclarationIdent is callable
    Given the module "verification/reporter" is loaded
    Then func parseDeclarationIdent should return a valid value

  Scenario: func parseProcBindingName is callable
    Given the module "verification/reporter" is loaded
    Then func parseProcBindingName should return a valid value
