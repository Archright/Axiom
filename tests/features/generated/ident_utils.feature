@generated @critical
Feature: ident_utils
  # generated | src/core/utils/ident_utils.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/utils/ident_utils" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/utils/ident_utils" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs isIdentStart, isIdentPart
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func isIdentStart is callable
    Given the module "core/utils/ident_utils" is loaded
    Then func isIdentStart should return a valid value

  Scenario: func isIdentPart is callable
    Given the module "core/utils/ident_utils" is loaded
    Then func isIdentPart should return a valid value
