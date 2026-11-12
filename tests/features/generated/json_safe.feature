@generated @critical
Feature: json_safe
  # generated | src/core/json/json_safe.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/json/json_safe" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/json/json_safe" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs safeParseJson, safeParseJsonFile
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func safeParseJson is callable
    Given the module "core/json/json_safe" is loaded
    Then func safeParseJson should return a valid value

  Scenario: func safeParseJsonFile is callable
    Given the module "core/json/json_safe" is loaded
    Then func safeParseJsonFile should return a valid value
