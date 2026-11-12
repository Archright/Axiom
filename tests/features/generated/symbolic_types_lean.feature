@generated @critical
Feature: symbolic_types_lean
  # generated | src/core/types/symbolic_types_lean.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/symbolic_types_lean" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/symbolic_types_lean" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sExprToLean
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func sExprToLean is callable
    Given the module "core/types/symbolic_types_lean" is loaded
    Then func sExprToLean should return a valid value
