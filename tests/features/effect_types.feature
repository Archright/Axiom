Feature: Effect System Types
  As an Axiom operator
  I want JSON parsing to be tagged with UnsafeJsonEffect
  So that unverified JSON parsing is visible to the effect system

  Scenario: OpaqueJsonString prevents direct parseJson
    Given a raw JSON string
    When it is wrapped in OpaqueJsonString
    Then direct parseJson is blocked at compile time
    And only pureParseJson can consume it

  Scenario: UnsafeJsonEffect marks I/O boundary
    Given a function that parses external JSON
    When the effect system inspects it
    Then UnsafeJsonEffect is in the effect set
