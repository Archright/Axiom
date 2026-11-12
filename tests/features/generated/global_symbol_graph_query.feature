@generated @critical
Feature: global_symbol_graph_query
  # generated | src/core/symbol_graph/global_symbol_graph_query.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/symbol_graph/global_symbol_graph_query" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/symbol_graph/global_symbol_graph_query" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs findDependents, graphHash, countSourceFunctions
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func findDependents is callable
    Given the module "core/symbol_graph/global_symbol_graph_query" is loaded
    Then func findDependents should return a valid value

  Scenario: func graphHash is callable
    Given the module "core/symbol_graph/global_symbol_graph_query" is loaded
    Then func graphHash should return a valid value

  Scenario: func countSourceFunctions is callable
    Given the module "core/symbol_graph/global_symbol_graph_query" is loaded
    Then func countSourceFunctions should return a valid value
