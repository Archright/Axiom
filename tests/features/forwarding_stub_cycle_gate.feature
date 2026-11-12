Feature: Forwarding Stub Cycle Gate with Ratchet Auto-Tightening
  As an Axiom architect enforcing Import Encapsulation
  I want the forwarding stub cycle gate to auto-tighten the facade ratchet
  So that facade count decreases are permanently enforced

  Background:
    Given the forwarding stub cycle gate is available

  @core
  Scenario: Facade ratchet ceiling is checked
    Given a facade_ratchet_ceiling.json with current_count and max_allowed
    When the forwarding stub count is at or below the ceiling
    Then the gate must pass

  @core
  Scenario: Facade ratchet auto-tightens on count decrease
    Given the current forwarding stub count decreased from previous
    When the gate runs
    Then facade_ratchet_ceiling.json max_allowed must be updated to the new count
    And the decrease_only flag must remain true

  @gate
  Scenario: Facade count increase above ceiling fails
    Given the forwarding stub count exceeds max_allowed
    When the gate runs
    Then the gate must fail with a ratchet violation message

  @gate
  Scenario: Decrease-only enforcement
    Given facade_ratchet_ceiling.json with decrease_only set to true
    When an attempt is made to increase max_allowed
    Then the attempt must be rejected
