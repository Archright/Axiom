@generated @critical
Feature: sorter_core_index_table
  # generated | src/core/sorter/sorter_core_index_table.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/sorter/sorter_core_index_table" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/sorter/sorter_core_index_table" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs buildNodeIndexTable, findNodeIndex, buildVaultEntryIndexTable, findVaultEntryIndex, hasVaultEntry, hasVaultEntry, addUniqueReleasedNode, findVaultIntegrityBlockIndex, buildVaultIntegrityBlockIndexTable, hasVaultIntegrityBlock, allDependenciesInVault
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func buildNodeIndexTable is callable
    Given the module "core/sorter/sorter_core_index_table" is loaded
    Then func buildNodeIndexTable should return a valid value

  Scenario: func findNodeIndex is callable
    Given the module "core/sorter/sorter_core_index_table" is loaded
    Then func findNodeIndex should return a valid value

  Scenario: func buildVaultEntryIndexTable is callable
    Given the module "core/sorter/sorter_core_index_table" is loaded
    Then func buildVaultEntryIndexTable should return a valid value

  Scenario: func findVaultEntryIndex is callable
    Given the module "core/sorter/sorter_core_index_table" is loaded
    Then func findVaultEntryIndex should return a valid value

  Scenario: func hasVaultEntry is callable
    Given the module "core/sorter/sorter_core_index_table" is loaded
    Then func hasVaultEntry should return a valid value

  Scenario: func hasVaultEntry is callable
    Given the module "core/sorter/sorter_core_index_table" is loaded
    Then func hasVaultEntry should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
