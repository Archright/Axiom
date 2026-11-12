@generated @critical
Feature: sandbox_guard
  # generated | src/core/test_support/sandbox_guard.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/test_support/sandbox_guard" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types EnvSnapshot
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/test_support/sandbox_guard" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs captureEnv, restoreEnv
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type EnvSnapshot is instantiable
    Given the module "core/test_support/sandbox_guard" is loaded
    Then type EnvSnapshot should be instantiable

  Scenario: func captureEnv is callable
    Given the module "core/test_support/sandbox_guard" is loaded
    Then func captureEnv should return a valid value

  Scenario: func restoreEnv is callable
    Given the module "core/test_support/sandbox_guard" is loaded
    Then func restoreEnv should return a valid value
