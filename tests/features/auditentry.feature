Feature: AuditEntry
  Audit record for gate execution

  Scenario: AuditEntry is properly defined
    Given the AuditEntry type exists
    Then it should be accessible from the audit subsystem
