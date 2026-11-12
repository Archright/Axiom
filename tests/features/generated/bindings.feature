@generated @critical
Feature: bindings
  # generated | src/core/parsers/tree_sitter/bindings.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/parsers/tree_sitter/bindings" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/parsers/tree_sitter/bindings" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs ts_tree_edit, ts_parser_delete, ts_parser_set_language
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func ts_tree_edit is callable
    Given the module "core/parsers/tree_sitter/bindings" is loaded
    Then func ts_tree_edit should return a valid value

  Scenario: func ts_parser_delete is callable
    Given the module "core/parsers/tree_sitter/bindings" is loaded
    Then func ts_parser_delete should return a valid value

  Scenario: func ts_parser_set_language is callable
    Given the module "core/parsers/tree_sitter/bindings" is loaded
    Then func ts_parser_set_language should return a valid value
