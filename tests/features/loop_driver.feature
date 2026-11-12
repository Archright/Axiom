Feature: Batch UAP Loop Driver
  As the Gate System,
  I want to drive the batch UAP proof loop with cache metrics,
  So that proof attempts are optimized with hit rate tracking.

  Background:
    Given the batch UAP loop driver is initialized

  Scenario: Loop driver records cache hits and misses
    Given a batch of proof obligations
    When the loop driver processes each obligation
    Then cache hits and misses are recorded in CacheMetrics
    And the hit rate is computed as hits / (hits + misses)

  Scenario: Loop driver completes batch within timeout
    Given a batch of proof obligations under the concurrency limit
    When the loop driver runs
    Then all obligations are processed
    And the cache metrics are reported
