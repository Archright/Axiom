@generated @critical
Feature: json_scan_skip
  # generated | src/core/json/json_scan_skip.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/json/json_scan_skip" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/json/json_scan_skip" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs isJsonWhitespace, skipJsonWhitespace, hexDigitValue, appendCodePoint, decodeJsonString, skipJsonStringValue, skipJsonLiteral, skipJsonNumber, skipJsonValue, skipJsonArray, skipJsonObject, skipJsonValue
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func isJsonWhitespace is callable
    Given the module "core/json/json_scan_skip" is loaded
    Then func isJsonWhitespace should return a valid value

  Scenario: func skipJsonWhitespace is callable
    Given the module "core/json/json_scan_skip" is loaded
    Then func skipJsonWhitespace should return a valid value

  Scenario: func hexDigitValue is callable
    Given the module "core/json/json_scan_skip" is loaded
    Then func hexDigitValue should return a valid value

  Scenario: func appendCodePoint is callable
    Given the module "core/json/json_scan_skip" is loaded
    Then func appendCodePoint should return a valid value

  Scenario: func decodeJsonString is callable
    Given the module "core/json/json_scan_skip" is loaded
    Then func decodeJsonString should return a valid value

  Scenario: func skipJsonStringValue is callable
    Given the module "core/json/json_scan_skip" is loaded
    Then func skipJsonStringValue should return a valid value

  # +6 more scenarios (types+funcs) omitted to stay under 50 lines
