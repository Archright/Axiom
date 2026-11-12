@legacy
Feature: Task Duration Scheduler
  Records Leanstral call durations and prioritizes nodes by complexity × staleness.

  Scenario: Fast node has lower priority score
    Given avgDurationMs = 5000 and isComplex = false, isStale = false
    When computePriority is called
    Then priority is higher (lower number) than a slow node

  Scenario: Stale node gets highest priority
    Given isStale = true
    When computePriority is called
    Then priority score is < 0