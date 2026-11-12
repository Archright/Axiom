Feature: JSONL Audit Store
  Infrastructure implementation of IAuditStorage backed by JSONL files.

  Background:
    Given a temporary JSONL audit log path exists

  Scenario: append writes an audit entry as JSON line
    Given a JsonlAuditStore targeting the log path
    And an AuditEntry with gateId "architecture_gate" and passed true
    When I call append with the entry
    Then the JSONL file should contain one line
    And the line should be valid JSON with field "gateId" = "architecture_gate"

  Scenario: recentEntries reads the last N entries
    Given a JsonlAuditStore with 5 appended entries
    When I call recentEntries with count 3
    Then the result should contain 3 entries
    And the entries should be the most recent 3

  Scenario: assessHealth returns hlHealthy when no data exists
    Given a JsonlAuditStore with no entries
    When I call assessHealth for gate "unknown_gate"
    Then the result should be hlHealthy

  Scenario: assessHealth returns hlCritical when all entries failed
    Given a JsonlAuditStore with 10 failed entries for gate "sad_gate"
    When I call assessHealth for gate "sad_gate"
    Then the result should be hlCritical

  Scenario: assessHealth returns hlWarning when pass rate is between 50% and 90%
    Given a JsonlAuditStore with 7 passing and 3 failing entries for gate "spec_gate"
    When I call assessHealth for gate "spec_gate"
    Then the result should be hlWarning
