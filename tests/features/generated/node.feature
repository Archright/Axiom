@generated @critical
Feature: node
  # generated | src/core/parsers/tree_sitter/node.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/parsers/tree_sitter/node" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/parsers/tree_sitter/node" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs ts_tree_delete, ts_tree_root_node, ts_node_type, ts_node_child, ts_node_child_count, ts_node_is_named, ts_node_named_child, ts_node_named_child_count, ts_node_start_byte, ts_node_end_byte, ts_node_string
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func ts_tree_delete is callable
    Given the module "core/parsers/tree_sitter/node" is loaded
    Then func ts_tree_delete should return a valid value

  Scenario: func ts_tree_root_node is callable
    Given the module "core/parsers/tree_sitter/node" is loaded
    Then func ts_tree_root_node should return a valid value

  Scenario: func ts_node_type is callable
    Given the module "core/parsers/tree_sitter/node" is loaded
    Then func ts_node_type should return a valid value

  Scenario: func ts_node_child is callable
    Given the module "core/parsers/tree_sitter/node" is loaded
    Then func ts_node_child should return a valid value

  Scenario: func ts_node_child_count is callable
    Given the module "core/parsers/tree_sitter/node" is loaded
    Then func ts_node_child_count should return a valid value

  Scenario: func ts_node_is_named is callable
    Given the module "core/parsers/tree_sitter/node" is loaded
    Then func ts_node_is_named should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
