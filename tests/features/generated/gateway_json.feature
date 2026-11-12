@generated @critical
Feature: gateway_json
  # generated | src/core/gateway/gateway_json.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/gateway/gateway_json" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/gateway/gateway_json" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs jsonParseSafe, jsonRequireObject, jsonRequireObjectField, jsonGetNonEmptyStringField, jsonGetNonEmptyStringFieldOrDefault, jsonGetBoolFieldOrDefault, jsonTryGetObjectField, jsonTryGetArrayField, jsonTryGetNonEmptyStringField
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func jsonParseSafe is callable
    Given the module "core/gateway/gateway_json" is loaded
    Then func jsonParseSafe should return a valid value

  Scenario: func jsonRequireObject is callable
    Given the module "core/gateway/gateway_json" is loaded
    Then func jsonRequireObject should return a valid value

  Scenario: func jsonRequireObjectField is callable
    Given the module "core/gateway/gateway_json" is loaded
    Then func jsonRequireObjectField should return a valid value

  Scenario: func jsonGetNonEmptyStringField is callable
    Given the module "core/gateway/gateway_json" is loaded
    Then func jsonGetNonEmptyStringField should return a valid value

  Scenario: func jsonGetNonEmptyStringFieldOrDefault is callable
    Given the module "core/gateway/gateway_json" is loaded
    Then func jsonGetNonEmptyStringFieldOrDefault should return a valid value

  Scenario: func jsonGetBoolFieldOrDefault is callable
    Given the module "core/gateway/gateway_json" is loaded
    Then func jsonGetBoolFieldOrDefault should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
