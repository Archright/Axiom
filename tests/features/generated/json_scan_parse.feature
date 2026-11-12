@generated @critical
Feature: json_scan_parse
  # generated | src/core/json/json_scan_parse.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/json/json_scan_parse" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/json/json_scan_parse" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs findObjectField, getJsonValueAtPath, parseJsonStringField, parseJsonStringAtPath, parseJsonStringAtPathOrDefault, parseJsonBoolAtPathOrDefault, parseJsonStringArrayAtPath
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func findObjectField is callable
    Given the module "core/json/json_scan_parse" is loaded
    Then func findObjectField should return a valid value

  Scenario: func getJsonValueAtPath is callable
    Given the module "core/json/json_scan_parse" is loaded
    Then func getJsonValueAtPath should return a valid value

  Scenario: func parseJsonStringField is callable
    Given the module "core/json/json_scan_parse" is loaded
    Then func parseJsonStringField should return a valid value

  Scenario: func parseJsonStringAtPath is callable
    Given the module "core/json/json_scan_parse" is loaded
    Then func parseJsonStringAtPath should return a valid value

  Scenario: func parseJsonStringAtPathOrDefault is callable
    Given the module "core/json/json_scan_parse" is loaded
    Then func parseJsonStringAtPathOrDefault should return a valid value

  Scenario: func parseJsonBoolAtPathOrDefault is callable
    Given the module "core/json/json_scan_parse" is loaded
    Then func parseJsonBoolAtPathOrDefault should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
