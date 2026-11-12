@generated @critical
Feature: json_utils_scan
  # generated | src/core/json/json_utils_scan.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/json/json_utils_scan" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/json/json_utils_scan" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs skipJsonWhitespace, decodeJsonString, skipJsonValue, skipJsonLiteral
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func skipJsonWhitespace is callable
    Given the module "core/json/json_utils_scan" is loaded
    Then func skipJsonWhitespace should return a valid value

  Scenario: func decodeJsonString is callable
    Given the module "core/json/json_utils_scan" is loaded
    Then func decodeJsonString should return a valid value

  Scenario: func skipJsonValue is callable
    Given the module "core/json/json_utils_scan" is loaded
    Then func skipJsonValue should return a valid value

  Scenario: func skipJsonLiteral is callable
    Given the module "core/json/json_utils_scan" is loaded
    Then func skipJsonLiteral should return a valid value
