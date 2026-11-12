@generated @high
Feature: checks
  # generated | src/gate/runners/debt_blocker/private/checks.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/runners/debt_blocker/private/checks" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/runners/debt_blocker/private/checks" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func isStdlibModule is callable
    Given the module "gate/runners/debt_blocker/private/checks" is loaded
    Then func isStdlibModule should return a valid value

  Scenario: func isExternalPackage is callable
    Given the module "gate/runners/debt_blocker/private/checks" is loaded
    Then func isExternalPackage should return a valid value

  Scenario: func isCompilerModule is callable
    Given the module "gate/runners/debt_blocker/private/checks" is loaded
    Then func isCompilerModule should return a valid value

  Scenario: func isProjectModule is callable
    Given the module "gate/runners/debt_blocker/private/checks" is loaded
    Then func isProjectModule should return a valid value

  Scenario: func resolveModulePath is callable
    Given the module "gate/runners/debt_blocker/private/checks" is loaded
    Then func resolveModulePath should return a valid value

  Scenario: func extractImportTargets is callable
    Given the module "gate/runners/debt_blocker/private/checks" is loaded
    Then func extractImportTargets should return a valid value
