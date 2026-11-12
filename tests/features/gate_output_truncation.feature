Feature: Gate Output Truncation
  As a developer
  I want gate output to be truncated when it exceeds buffer limits
  So that git hooks don't crash with EAGAIN IOError

  Scenario: Large gate output is truncated gracefully
    Given a gate produces more than 4096 bytes of output
    When the orchestrator writes the output to stderr
    Then the output is truncated to 4096 bytes
    And a truncation message is appended
    And no IOError is thrown

  @spec-density
  Scenario: Baseline items are suppressed when all are baseline
    Given a hotspot gate scans 669 files with all items at baseline
    When the gate reports results
    Then only a summary count is printed per category
    And no individual baseline items are enumerated
    And output is under 50 lines
