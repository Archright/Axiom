@generated @critical
Feature: nav
  # generated | src/core/parsers/nav.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/parsers/nav" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/parsers/nav" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs findNodes, findFirstNode, nodeText, nodeTextAll, nodeAttr, childElements, nodeField, collectNodeTexts, findFunctionNode, nodeSpan, indexFunctionNodes
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func findNodes is callable
    Given the module "core/parsers/nav" is loaded
    Then func findNodes should return a valid value

  Scenario: func findFirstNode is callable
    Given the module "core/parsers/nav" is loaded
    Then func findFirstNode should return a valid value

  Scenario: func nodeText is callable
    Given the module "core/parsers/nav" is loaded
    Then func nodeText should return a valid value

  Scenario: func nodeTextAll is callable
    Given the module "core/parsers/nav" is loaded
    Then func nodeTextAll should return a valid value

  Scenario: func nodeAttr is callable
    Given the module "core/parsers/nav" is loaded
    Then func nodeAttr should return a valid value

  Scenario: func childElements is callable
    Given the module "core/parsers/nav" is loaded
    Then func childElements should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
