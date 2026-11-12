@generated @critical
Feature: smt_types
  # generated | src/core/encoding/smt_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/encoding/smt_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types SExprNode, atom, children, isList
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/encoding/smt_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs consumeSExpr, parseSExpr
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type SExprNode is instantiable
    Given the module "core/encoding/smt_types" is loaded
    Then type SExprNode should be instantiable

  Scenario: type atom is instantiable
    Given the module "core/encoding/smt_types" is loaded
    Then type atom should be instantiable

  Scenario: type children is instantiable
    Given the module "core/encoding/smt_types" is loaded
    Then type children should be instantiable

  Scenario: type isList is instantiable
    Given the module "core/encoding/smt_types" is loaded
    Then type isList should be instantiable

  Scenario: func consumeSExpr is callable
    Given the module "core/encoding/smt_types" is loaded
    Then func consumeSExpr should return a valid value

  Scenario: func parseSExpr is callable
    Given the module "core/encoding/smt_types" is loaded
    Then func parseSExpr should return a valid value
