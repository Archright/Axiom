@generated @critical
Feature: topology_symbol_scanner
  # generated | src/core/topology/topology_symbol_scanner.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/topology_symbol_scanner" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/topology_symbol_scanner" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs scanTopologySource, buildSymbolIndexTable
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func scanTopologySource is callable
    Given the module "core/topology/topology_symbol_scanner" is loaded
    Then func scanTopologySource should return a valid value

  Scenario: func buildSymbolIndexTable is callable
    Given the module "core/topology/topology_symbol_scanner" is loaded
    Then func buildSymbolIndexTable should return a valid value
