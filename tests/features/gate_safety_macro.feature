Feature: Gate Safety Macro — Compile-Time In-Process Gate Validation
  As an Axiom developer
  I want compile-time assertions for in-process gate safety
  So that only verified-safe gates can run in-process

  Background:
    Given the gate safety macro module is available

  Scenario: assertValueType rejects ref types
    When a ref object type is passed to assertValueType
    Then the compilation should fail with "ref type — value type required"

  Scenario: assertValueType accepts value types
    When a plain object type is passed to assertValueType
    Then compilation should succeed

  Scenario: assertGateSignature checks for ref parameters
    When a proc with a ref parameter is passed to assertGateSignature
    Then the compilation should fail with "ref type — value types only"

  Scenario: InProcessGateContext is a pure value type
    Then InProcessGateContext should not be a ref type
    And InProcessGateContext should not be a ptr type

  Scenario: LightGateAllowlist starts empty
    Then the allowlist should have zero entries
    And isLightGateAllowed for any gateId should return false
