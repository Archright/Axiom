@generated @critical
Feature: symbolic_types_expr
  # generated | src/core/types/symbolic_types_expr.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/symbolic_types_expr" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types SymSymSExprKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/symbolic_types_expr" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sVar, sConst, sAdd, sSub, sMul, sEq, sLt, sLe, sGe, sGt, sAnd, sNot, sSome, sIsSome, sVal, sOk, sErr, sIsOk, sErrMsg, sUninterpretedApp, sAxiomRef, sCons, sHead, sTail, sLength, sExprToString
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type SymSymSExprKind is instantiable
    Given the module "core/types/symbolic_types_expr" is loaded
    Then type SymSymSExprKind should be instantiable

  Scenario: func sVar is callable
    Given the module "core/types/symbolic_types_expr" is loaded
    Then func sVar should return a valid value

  Scenario: func sConst is callable
    Given the module "core/types/symbolic_types_expr" is loaded
    Then func sConst should return a valid value

  Scenario: func sAdd is callable
    Given the module "core/types/symbolic_types_expr" is loaded
    Then func sAdd should return a valid value

  Scenario: func sSub is callable
    Given the module "core/types/symbolic_types_expr" is loaded
    Then func sSub should return a valid value

  Scenario: func sMul is callable
    Given the module "core/types/symbolic_types_expr" is loaded
    Then func sMul should return a valid value

  # +21 more scenarios (types+funcs) omitted to stay under 50 lines
