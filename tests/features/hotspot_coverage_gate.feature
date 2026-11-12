Feature: Hotspot Coverage Gate
  High-churn module test enforcement via git churn analysis.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: gate passes when all hotspots have tests
    Given a repository where all top-10% hotspot files have corresponding tests
    When I run the hotspot coverage gate
    Then the exit code should be 0

  Scenario: gate fails when hotspots lack tests
    Given a repository where some top-10% hotspot files have no test coverage
    When I run the hotspot coverage gate
    Then the exit code should be 1
    And the output should list uncovered hotspot files

  Scenario: gate passes with no source files
    Given a repository with no tracked source files
    When I run the hotspot coverage gate
    Then the exit code should be 0

  Scenario: self-test passes
    When I run the hotspot coverage gate in self-test mode
    Then the exit code should be 0

  Scenario: config files are excluded from churn analysis
    Given a file named config.nims with high modification count
    When I run the hotspot coverage gate
    Then config.nims should not appear as a hotspot
