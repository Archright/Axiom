@generated @critical
Feature: global_symbol_graph_types
  # generated | src/core/types/global_symbol_graph_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/global_symbol_graph_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/global_symbol_graph_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}
