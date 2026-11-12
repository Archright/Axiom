@generated @critical
Feature: sorter_core_index_base
  # generated | src/core/sorter/sorter_core_index_base.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/sorter/sorter_core_index_base" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types AxiomFormula
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/sorter/sorter_core_index_base" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sorterNodeId, sorterNodeIdString, nodeIdEquals, `==`, `$`, axiomFormula, axiomFormulaString, makeVaultEntry, deduplicateStrings, containsNodeId, deduplicateNodeIds, findNodeIndex, findVaultEntryIndex
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type AxiomFormula is instantiable
    Given the module "core/sorter/sorter_core_index_base" is loaded
    Then type AxiomFormula should be instantiable

  Scenario: func sorterNodeId is callable
    Given the module "core/sorter/sorter_core_index_base" is loaded
    Then func sorterNodeId should return a valid value

  Scenario: func sorterNodeIdString is callable
    Given the module "core/sorter/sorter_core_index_base" is loaded
    Then func sorterNodeIdString should return a valid value

  Scenario: func nodeIdEquals is callable
    Given the module "core/sorter/sorter_core_index_base" is loaded
    Then func nodeIdEquals should return a valid value

  Scenario: func `==` is callable
    Given the module "core/sorter/sorter_core_index_base" is loaded
    Then func `==` should return a valid value

  Scenario: func `$` is callable
    Given the module "core/sorter/sorter_core_index_base" is loaded
    Then func `$` should return a valid value

  # +8 more scenarios (types+funcs) omitted to stay under 50 lines
