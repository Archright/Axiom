@generated @critical
Feature: expr_serialize
  # generated | src/core/solver/expr_serialize.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/solver/expr_serialize" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/solver/expr_serialize" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs toSmt, namedAssert
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func toSmt is callable
    Given the module "core/solver/expr_serialize" is loaded
    Then func toSmt should return a valid value

  Scenario: func namedAssert is callable
    Given the module "core/solver/expr_serialize" is loaded
    Then func namedAssert should return a valid value
