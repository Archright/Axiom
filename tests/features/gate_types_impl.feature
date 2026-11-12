Feature: Gate Types Implementation — Utility Functions for Gate Types
  As the gate infrastructure,
  the gate_types_impl module must provide utility functions
  (string conversion, error construction, outcome factories)
  that operate on types defined in gate_contract.nim.

  Background:
    Given the gate_types_impl module depends on gate_contract

  # ── String conversion ────────────────────────────────────────────

  Scenario: GateResult has a string representation
    Given a GateResult value
    When converted to string via the $ operator
    Then the result contains the gate ID, status, and duration

  # ── Error construction ───────────────────────────────────────────

  Scenario: gateErr constructs a GateError
    Given an error code and message
    When gateErr is called
    Then a GateError is returned with the code, message, and optional gateId

  # ── Outcome factories ────────────────────────────────────────────

  Scenario: gateOk constructs a successful GateOutcome
    Given a GateResult
    When gateOk is called
    Then a successful GateOutcome wrapping the result is returned

  Scenario: gateFail constructs a failed GateOutcome
    Given an error code and message
    When gateFail is called
    Then a failed GateOutcome containing a GateError is returned

  # ── Effect safety ────────────────────────────────────────────────

  Scenario: All utility functions are side-effect free
    Given any function in gate_types_impl
    When analyzed by the Nim effect system
    Then no side effects are declared
