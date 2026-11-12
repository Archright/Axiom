Feature: Hotspot Analyzer
  Computes git churn scores for source modules to identify hotspots.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: parseChurnScores filters non-nim files
    Given git log output containing "src/core/audit.nim" and "README.md"
    When I parse the churn scores
    Then the result should contain "src/core/audit.nim"
    And the result should not contain "README.md"

  Scenario: parseChurnScores filters test and vendor paths
    Given git log output containing "tests/unit/foo_test.nim" and "vendor/lib/bar.nim"
    When I parse the churn scores
    Then the result should not contain "tests/unit/foo_test.nim"
    And the result should not contain "vendor/lib/bar.nim"

  Scenario: parseChurnScores counts duplicate entries
    Given git log output with "src/core/hotspot.nim" appearing 3 times
    When I parse the churn scores
    Then the score for "src/core/hotspot.nim" should be 3

  Scenario: moduleNameFromPath extracts basename without extension
    Given a file path "src/core/audit/audit_types.nim"
    When I extract the module name
    Then the result should be "audit_types"

  Scenario: sortedChurnByScore sorts descending by edit count
    Given churn data with paths having counts 5, 20, and 10
    When I sort by churn score
    Then the first entry should have count 20
    And the second entry should have count 10

  Scenario: ChurnPeriod maps to correct day counts
    Given the ChurnPeriod enum
    Then periodDays cp7d should be 7
    And periodDays cp30d should be 30
    And periodDays cp90d should be 90
