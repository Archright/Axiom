@generated @high
Feature: fixedpoint_types
  # generated | src/verification/solver/fixedpoint_types.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/solver/fixedpoint_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types HornClause, name, body, head
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/solver/fixedpoint_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type HornClause is instantiable
    Given the module "verification/solver/fixedpoint_types" is loaded
    Then type HornClause should be instantiable

  Scenario: type name is instantiable
    Given the module "verification/solver/fixedpoint_types" is loaded
    Then type name should be instantiable

  Scenario: type body is instantiable
    Given the module "verification/solver/fixedpoint_types" is loaded
    Then type body should be instantiable

  Scenario: type head is instantiable
    Given the module "verification/solver/fixedpoint_types" is loaded
    Then type head should be instantiable
