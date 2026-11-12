@generated @critical
Feature: import_graph
  # generated | src/core/topology/import_graph.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/import_graph" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ModuleEdge
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/import_graph" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs extractCoreImports, buildImportGraph, countCoreModules, countCoreModulesFromGraph, findCycles, computeTopologicalLayers, buildReverseGraph
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ModuleEdge is instantiable
    Given the module "core/topology/import_graph" is loaded
    Then type ModuleEdge should be instantiable

  Scenario: func extractCoreImports is callable
    Given the module "core/topology/import_graph" is loaded
    Then func extractCoreImports should return a valid value

  Scenario: func buildImportGraph is callable
    Given the module "core/topology/import_graph" is loaded
    Then func buildImportGraph should return a valid value

  Scenario: func countCoreModules is callable
    Given the module "core/topology/import_graph" is loaded
    Then func countCoreModules should return a valid value

  Scenario: func countCoreModulesFromGraph is callable
    Given the module "core/topology/import_graph" is loaded
    Then func countCoreModulesFromGraph should return a valid value

  Scenario: func findCycles is callable
    Given the module "core/topology/import_graph" is loaded
    Then func findCycles should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
