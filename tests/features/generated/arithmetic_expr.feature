@generated @critical
Feature: arithmetic_expr
  # generated | src/core/encoding/smt_to_lean/private/arithmetic_expr.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/encoding/smt_to_lean/private/arithmetic_expr" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Param, name, typ
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/encoding/smt_to_lean/private/arithmetic_expr" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs parseArithmeticFunction, parseArithmeticBodyExpressions, generateSmtLib2, generateAndWriteSmtQuery, isArithmeticFunction
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type Param is instantiable
    Given the module "core/encoding/smt_to_lean/private/arithmetic_expr" is loaded
    Then type Param should be instantiable

  Scenario: type name is instantiable
    Given the module "core/encoding/smt_to_lean/private/arithmetic_expr" is loaded
    Then type name should be instantiable

  Scenario: type typ is instantiable
    Given the module "core/encoding/smt_to_lean/private/arithmetic_expr" is loaded
    Then type typ should be instantiable

  Scenario: func parseArithmeticFunction is callable
    Given the module "core/encoding/smt_to_lean/private/arithmetic_expr" is loaded
    Then func parseArithmeticFunction should return a valid value

  Scenario: func parseArithmeticBodyExpressions is callable
    Given the module "core/encoding/smt_to_lean/private/arithmetic_expr" is loaded
    Then func parseArithmeticBodyExpressions should return a valid value

  Scenario: func generateSmtLib2 is callable
    Given the module "core/encoding/smt_to_lean/private/arithmetic_expr" is loaded
    Then func generateSmtLib2 should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
