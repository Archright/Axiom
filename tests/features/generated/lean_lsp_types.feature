@generated @critical
Feature: lean_lsp_types
  # generated | src/core/types/lean_lsp_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/lean_lsp_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types GoalDelta, unchangedGoals, resolvedGoals, newGoals, typeErrors
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/lean_lsp_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type GoalDelta is instantiable
    Given the module "core/types/lean_lsp_types" is loaded
    Then type GoalDelta should be instantiable

  Scenario: type unchangedGoals is instantiable
    Given the module "core/types/lean_lsp_types" is loaded
    Then type unchangedGoals should be instantiable

  Scenario: type resolvedGoals is instantiable
    Given the module "core/types/lean_lsp_types" is loaded
    Then type resolvedGoals should be instantiable

  Scenario: type newGoals is instantiable
    Given the module "core/types/lean_lsp_types" is loaded
    Then type newGoals should be instantiable

  Scenario: type typeErrors is instantiable
    Given the module "core/types/lean_lsp_types" is loaded
    Then type typeErrors should be instantiable
