@generated @critical
Feature: nodes
  # generated | src/core/parsers/tree_sitter/nodes.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/parsers/tree_sitter/nodes" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/parsers/tree_sitter/nodes" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs getChildByType, getChildrenByType, isExported
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func getChildByType is callable
    Given the module "core/parsers/tree_sitter/nodes" is loaded
    Then func getChildByType should return a valid value

  Scenario: func getChildrenByType is callable
    Given the module "core/parsers/tree_sitter/nodes" is loaded
    Then func getChildrenByType should return a valid value

  Scenario: func isExported is callable
    Given the module "core/parsers/tree_sitter/nodes" is loaded
    Then func isExported should return a valid value
