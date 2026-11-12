@generated @critical
Feature: ast_types
  # generated | src/core/types/ast_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/ast_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types AstNode
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/ast_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs toAstNode, toXmlNode, isNil, kind, tag, `$`
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type AstNode is instantiable
    Given the module "core/types/ast_types" is loaded
    Then type AstNode should be instantiable

  Scenario: func toAstNode is callable
    Given the module "core/types/ast_types" is loaded
    Then func toAstNode should return a valid value

  Scenario: func toXmlNode is callable
    Given the module "core/types/ast_types" is loaded
    Then func toXmlNode should return a valid value

  Scenario: func isNil is callable
    Given the module "core/types/ast_types" is loaded
    Then func isNil should return a valid value

  Scenario: func kind is callable
    Given the module "core/types/ast_types" is loaded
    Then func kind should return a valid value

  Scenario: func tag is callable
    Given the module "core/types/ast_types" is loaded
    Then func tag should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
