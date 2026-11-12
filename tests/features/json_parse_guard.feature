Feature: JSON Parse Guard
  As an Axiom operator
  I want a guard that validates JSON before parsing
  So that malformed JSON is rejected deterministically

  Scenario: Valid JSON passes pureParseJson
    Given a valid JSON string '{"key": "value"}'
    When pureParseJson is called with OpaqueJsonString
    Then a JsonNode is returned without error

  Scenario: Empty string is rejected
    Given an empty string
    When pureParseJson is called with OpaqueJsonString
    Then an error is raised
