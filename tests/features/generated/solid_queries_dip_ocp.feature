@generated @high
Feature: solid_queries_dip_ocp
  # generated | src/gate/nimtry/solid_queries_dip_ocp.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/solid_queries_dip_ocp" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ForbiddenCallPattern, callee, callerPattern, allowedCallers
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/solid_queries_dip_ocp" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type ForbiddenCallPattern is instantiable
    Given the module "gate/nimtry/solid_queries_dip_ocp" is loaded
    Then type ForbiddenCallPattern should be instantiable

  Scenario: type callee is instantiable
    Given the module "gate/nimtry/solid_queries_dip_ocp" is loaded
    Then type callee should be instantiable

  Scenario: type callerPattern is instantiable
    Given the module "gate/nimtry/solid_queries_dip_ocp" is loaded
    Then type callerPattern should be instantiable

  Scenario: type allowedCallers is instantiable
    Given the module "gate/nimtry/solid_queries_dip_ocp" is loaded
    Then type allowedCallers should be instantiable

  Scenario: func loadForbiddenCallPatterns is callable
    Given the module "gate/nimtry/solid_queries_dip_ocp" is loaded
    Then func loadForbiddenCallPatterns should return a valid value

  Scenario: func loadForbiddenPragmaPatterns is callable
    Given the module "gate/nimtry/solid_queries_dip_ocp" is loaded
    Then func loadForbiddenPragmaPatterns should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
