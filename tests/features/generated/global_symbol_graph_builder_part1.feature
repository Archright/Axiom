@generated @critical
Feature: global_symbol_graph_builder_part1
  # generated | src/core/symbol_graph/global_symbol_graph_builder_part1.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/symbol_graph/global_symbol_graph_builder_part1" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/symbol_graph/global_symbol_graph_builder_part1" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs extractSymbolsFromSourceFallback, loadIncrementalGraphCache, globalSymbolGraphIncrementalCachePath
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func extractSymbolsFromSourceFallback is callable
    Given the module "core/symbol_graph/global_symbol_graph_builder_part1" is loaded
    Then func extractSymbolsFromSourceFallback should return a valid value

  Scenario: func loadIncrementalGraphCache is callable
    Given the module "core/symbol_graph/global_symbol_graph_builder_part1" is loaded
    Then func loadIncrementalGraphCache should return a valid value

  Scenario: func globalSymbolGraphIncrementalCachePath is callable
    Given the module "core/symbol_graph/global_symbol_graph_builder_part1" is loaded
    Then func globalSymbolGraphIncrementalCachePath should return a valid value
