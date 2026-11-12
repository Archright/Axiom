@generated @critical
Feature: section_parsers
  # generated | src/core/policy/section_parsers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/policy/section_parsers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types SectionParseProc
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/policy/section_parsers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs registerSection, getHandler, isRegistered
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type SectionParseProc is instantiable
    Given the module "core/policy/section_parsers" is loaded
    Then type SectionParseProc should be instantiable

  Scenario: func registerSection is callable
    Given the module "core/policy/section_parsers" is loaded
    Then func registerSection should return a valid value

  Scenario: func getHandler is callable
    Given the module "core/policy/section_parsers" is loaded
    Then func getHandler should return a valid value

  Scenario: func isRegistered is callable
    Given the module "core/policy/section_parsers" is loaded
    Then func isRegistered should return a valid value
