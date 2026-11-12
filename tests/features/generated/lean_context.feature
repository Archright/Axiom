@generated @critical
Feature: lean_context
  # generated | src/core/application/lean_context.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/application/lean_context" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types LeanContext, callLeanstral, runLeanReplay, runLeanProofRefinementLoop, inferLeanSpec
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/application/lean_context" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs validate
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type LeanContext is instantiable
    Given the module "core/application/lean_context" is loaded
    Then type LeanContext should be instantiable

  Scenario: type callLeanstral is instantiable
    Given the module "core/application/lean_context" is loaded
    Then type callLeanstral should be instantiable

  Scenario: type runLeanReplay is instantiable
    Given the module "core/application/lean_context" is loaded
    Then type runLeanReplay should be instantiable

  Scenario: type runLeanProofRefinementLoop is instantiable
    Given the module "core/application/lean_context" is loaded
    Then type runLeanProofRefinementLoop should be instantiable

  Scenario: type inferLeanSpec is instantiable
    Given the module "core/application/lean_context" is loaded
    Then type inferLeanSpec should be instantiable

  Scenario: func validate is callable
    Given the module "core/application/lean_context" is loaded
    Then func validate should return a valid value
