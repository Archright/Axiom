Feature: Audit Storage Interface
  Concept interface for gate audit persistence.

  Background:
    Given the Axiom audit subsystem is initialized

  Scenario: IAuditStorage concept is satisfied by a compliant type
    Given a type implementing append, recentEntries, and assessHealth
    Then the type should satisfy the IAuditStorage concept

  Scenario: append accepts an AuditEntry
    Given an AuditEntry with gateId "architecture_gate" and passed true
    When I append the entry to storage
    Then the entry should be persisted

  Scenario: recentEntries returns the last N entries
    Given the audit log contains 10 entries
    When I request recentEntries with count 5
    Then the result should contain 5 entries
    And the entries should be the most recent 5

  Scenario: assessHealth returns a valid HealthLevel
    Given the audit log contains entries for gate "spec_presence_gate"
    When I call assessHealth for gate "spec_presence_gate"
    Then the result should be a valid HealthLevel
