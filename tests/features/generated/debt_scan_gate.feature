@generated @high
Feature: debt_scan_gate
  # generated | src/gate/runners/debt_scan_gate.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/runners/debt_scan_gate" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/runners/debt_scan_gate" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func runDebtScan is callable
    Given the module "gate/runners/debt_scan_gate" is loaded
    Then func runDebtScan should return a valid value

  Scenario: func runDebtScanVfs is callable
    Given the module "gate/runners/debt_scan_gate" is loaded
    Then func runDebtScanVfs should return a valid value

  Scenario: func mainWithVfs is callable
    Given the module "gate/runners/debt_scan_gate" is loaded
    Then func mainWithVfs should return a valid value
