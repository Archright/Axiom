@generated @critical
Feature: runtime_context
  # generated | src/core/trusted/runtime_context.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/trusted/runtime_context" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types VerificationRuntimeContext, lspPool
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/trusted/runtime_context" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type VerificationRuntimeContext is instantiable
    Given the module "core/trusted/runtime_context" is loaded
    Then type VerificationRuntimeContext should be instantiable

  Scenario: type lspPool is instantiable
    Given the module "core/trusted/runtime_context" is loaded
    Then type lspPool should be instantiable
