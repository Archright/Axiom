@generated @critical
Feature: heal_types
  # generated | src/core/types/heal_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/heal_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types HealNodeInput, node, nodeId, inputIndex, fileContext, docContext, unsatCore, attemptCount, forceFormal, cwdOverride, tomlHint, modulePathCache
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/heal_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type HealNodeInput is instantiable
    Given the module "core/types/heal_types" is loaded
    Then type HealNodeInput should be instantiable

  Scenario: type node is instantiable
    Given the module "core/types/heal_types" is loaded
    Then type node should be instantiable

  Scenario: type nodeId is instantiable
    Given the module "core/types/heal_types" is loaded
    Then type nodeId should be instantiable

  Scenario: type inputIndex is instantiable
    Given the module "core/types/heal_types" is loaded
    Then type inputIndex should be instantiable

  Scenario: type fileContext is instantiable
    Given the module "core/types/heal_types" is loaded
    Then type fileContext should be instantiable

  Scenario: type docContext is instantiable
    Given the module "core/types/heal_types" is loaded
    Then type docContext should be instantiable

  # +6 more scenarios (types+funcs) omitted to stay under 50 lines
