@generated @high
Feature: quality_gate
  # generated | src/gate/quality_gate.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/quality_gate" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ModuleInfo, path, imports, funcCount, procCount, totalFunctions, exportedFunctions, importCount
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/quality_gate" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type ModuleInfo is instantiable
    Given the module "gate/quality_gate" is loaded
    Then type ModuleInfo should be instantiable

  Scenario: type path is instantiable
    Given the module "gate/quality_gate" is loaded
    Then type path should be instantiable

  Scenario: type imports is instantiable
    Given the module "gate/quality_gate" is loaded
    Then type imports should be instantiable

  Scenario: type funcCount is instantiable
    Given the module "gate/quality_gate" is loaded
    Then type funcCount should be instantiable

  Scenario: type procCount is instantiable
    Given the module "gate/quality_gate" is loaded
    Then type procCount should be instantiable

  Scenario: type totalFunctions is instantiable
    Given the module "gate/quality_gate" is loaded
    Then type totalFunctions should be instantiable

  # +7 more scenarios (types+funcs) omitted to stay under 50 lines
