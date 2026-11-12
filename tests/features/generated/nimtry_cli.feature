@generated @high
Feature: nimtry_cli
  # generated | src/gate/nimtry/nimtry_cli.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/nimtry_cli" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Baseline, totalViolations, errorCount, ViolationBaseline, version, created, totalViolations, bySeverity, fingerprints
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/nimtry_cli" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type Baseline is instantiable
    Given the module "gate/nimtry/nimtry_cli" is loaded
    Then type Baseline should be instantiable

  Scenario: type totalViolations is instantiable
    Given the module "gate/nimtry/nimtry_cli" is loaded
    Then type totalViolations should be instantiable

  Scenario: type errorCount is instantiable
    Given the module "gate/nimtry/nimtry_cli" is loaded
    Then type errorCount should be instantiable

  Scenario: type ViolationBaseline is instantiable
    Given the module "gate/nimtry/nimtry_cli" is loaded
    Then type ViolationBaseline should be instantiable

  Scenario: type version is instantiable
    Given the module "gate/nimtry/nimtry_cli" is loaded
    Then type version should be instantiable

  Scenario: type created is instantiable
    Given the module "gate/nimtry/nimtry_cli" is loaded
    Then type created should be instantiable

  # +4 more scenarios (types+funcs) omitted to stay under 50 lines
