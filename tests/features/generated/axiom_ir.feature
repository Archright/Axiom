@generated @critical
Feature: axiom_ir
  # generated | src/core/types/axiom_ir.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/axiom_ir" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types IrNodeKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/axiom_ir" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs toSExpr, toLeanContract, parseNimToIR, extractTypeContract, extractEffectConstraints
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type IrNodeKind is instantiable
    Given the module "core/types/axiom_ir" is loaded
    Then type IrNodeKind should be instantiable

  Scenario: func toSExpr is callable
    Given the module "core/types/axiom_ir" is loaded
    Then func toSExpr should return a valid value

  Scenario: func toLeanContract is callable
    Given the module "core/types/axiom_ir" is loaded
    Then func toLeanContract should return a valid value

  Scenario: func parseNimToIR is callable
    Given the module "core/types/axiom_ir" is loaded
    Then func parseNimToIR should return a valid value

  Scenario: func extractTypeContract is callable
    Given the module "core/types/axiom_ir" is loaded
    Then func extractTypeContract should return a valid value

  Scenario: func extractEffectConstraints is callable
    Given the module "core/types/axiom_ir" is loaded
    Then func extractEffectConstraints should return a valid value
