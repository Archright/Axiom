@generated @critical
Feature: ast_to_lean_bridge
  # generated | src/core/translator/ast_to_lean_bridge.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/translator/ast_to_lean_bridge" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types NimParamInfo, name, nimType, isVar
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/translator/ast_to_lean_bridge" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs translateNimTypeToLean, translateNimExprToLean, translateNimBodyLinesToLean, extractNimFunction, buildLeanParams, buildLeanFunctionDef, buildLeanPropertyProposition, buildLeanTheoremSkeleton, buildLeanBridge, buildLeanBridgeFromSource
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type NimParamInfo is instantiable
    Given the module "core/translator/ast_to_lean_bridge" is loaded
    Then type NimParamInfo should be instantiable

  Scenario: type name is instantiable
    Given the module "core/translator/ast_to_lean_bridge" is loaded
    Then type name should be instantiable

  Scenario: type nimType is instantiable
    Given the module "core/translator/ast_to_lean_bridge" is loaded
    Then type nimType should be instantiable

  Scenario: type isVar is instantiable
    Given the module "core/translator/ast_to_lean_bridge" is loaded
    Then type isVar should be instantiable

  Scenario: func translateNimTypeToLean is callable
    Given the module "core/translator/ast_to_lean_bridge" is loaded
    Then func translateNimTypeToLean should return a valid value

  Scenario: func translateNimExprToLean is callable
    Given the module "core/translator/ast_to_lean_bridge" is loaded
    Then func translateNimExprToLean should return a valid value

  # +8 more scenarios (types+funcs) omitted to stay under 50 lines
