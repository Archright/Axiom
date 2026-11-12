@generated @high
Feature: import_encapsulation_gate
  # generated | src/gate/runners/import_encapsulation_gate.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/runners/import_encapsulation_gate" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/runners/import_encapsulation_gate" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func runImportEncapsulationScan is callable
    Given the module "gate/runners/import_encapsulation_gate" is loaded
    Then func runImportEncapsulationScan should return a valid value

  Scenario: func runImportEncapsulationScanVfs is callable
    Given the module "gate/runners/import_encapsulation_gate" is loaded
    Then func runImportEncapsulationScanVfs should return a valid value

  Scenario: func mainWithVfs is callable
    Given the module "gate/runners/import_encapsulation_gate" is loaded
    Then func mainWithVfs should return a valid value
