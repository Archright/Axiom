Feature: Audit Domain Types
  SSOT type definitions for audit persistence.

  Scenario: AuditEntry contains required fields
    Given the AuditEntry type exists
    Then it should have a gateId field of type string
    And it should have a passed field of type bool
    And it should have a durationMs field of type int
    And it should have a timestamp field of type string
    And it should have a metadata field of type string

  Scenario: HealthLevel enum covers all tiers
    Given the HealthLevel enum exists
    Then it should contain hlHealthy
    And it should contain hlWarning
    And it should contain hlDegraded
    And it should contain hlCritical

  Scenario: HealthLevel is ordered from healthy to critical
    Given the HealthLevel enum exists
    Then ord(hlHealthy) should be less than ord(hlWarning)
    And ord(hlWarning) should be less than ord(hlDegraded)
    And ord(hlDegraded) should be less than ord(hlCritical)
