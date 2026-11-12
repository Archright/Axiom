@generated @high
Feature: isolated_check
  # generated | src/gate/runners/isolated_check.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/runners/isolated_check" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types IsolatedCheckResult, ok, output, elapsedMs
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/runners/isolated_check" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type IsolatedCheckResult is instantiable
    Given the module "gate/runners/isolated_check" is loaded
    Then type IsolatedCheckResult should be instantiable

  Scenario: type ok is instantiable
    Given the module "gate/runners/isolated_check" is loaded
    Then type ok should be instantiable

  Scenario: type output is instantiable
    Given the module "gate/runners/isolated_check" is loaded
    Then type output should be instantiable

  Scenario: type elapsedMs is instantiable
    Given the module "gate/runners/isolated_check" is loaded
    Then type elapsedMs should be instantiable
