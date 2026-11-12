@generated @high
Feature: certificate_applier
  # generated | src/verification/certificate_applier.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/certificate_applier" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/certificate_applier" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func findByName is callable
    Given the module "verification/certificate_applier" is loaded
    Then func findByName should return a valid value

  Scenario: func applyDirectives is callable
    Given the module "verification/certificate_applier" is loaded
    Then func applyDirectives should return a valid value
