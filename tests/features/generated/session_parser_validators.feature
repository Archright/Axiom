@generated @critical
Feature: session_parser_validators
  # generated | src/core/session/session_parser_validators.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/session/session_parser_validators" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Client
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/session/session_parser_validators" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs isValidUuid, isValidUuidV4, isValidIso8601, isValidIsoDate, isNonEmpty, isAnyString, isValidSchemaVersion, isValidMimeType, isValidBase64, isValidJsonBlob, isNonEmpty, isAnyString, isValidUuid, isValidUuidV4, isValidIsoDate, isValidSchemaVersion, isValidMimeType, isValidBase64, isValidJsonBlob, isValidIso8601
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type Client is instantiable
    Given the module "core/session/session_parser_validators" is loaded
    Then type Client should be instantiable

  Scenario: func isValidUuid is callable
    Given the module "core/session/session_parser_validators" is loaded
    Then func isValidUuid should return a valid value

  Scenario: func isValidUuidV4 is callable
    Given the module "core/session/session_parser_validators" is loaded
    Then func isValidUuidV4 should return a valid value

  Scenario: func isValidIso8601 is callable
    Given the module "core/session/session_parser_validators" is loaded
    Then func isValidIso8601 should return a valid value

  Scenario: func isValidIsoDate is callable
    Given the module "core/session/session_parser_validators" is loaded
    Then func isValidIsoDate should return a valid value

  Scenario: func isNonEmpty is callable
    Given the module "core/session/session_parser_validators" is loaded
    Then func isNonEmpty should return a valid value

  # +15 more scenarios (types+funcs) omitted to stay under 50 lines
