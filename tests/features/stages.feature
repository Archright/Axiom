Feature: Batch UAP Stages
  As the Gate System,
  I want to execute batch UAP proof stages with cache metrics,
  So that each proof stage tracks summary cache performance.

  Background:
    Given the batch UAP stages module is initialized

  Scenario: Stage records cache hit on existing summary
    Given a proof obligation with a cached summary
    When the stage processes the obligation
    Then a cache hit is recorded
    And the cached summary is reused

  Scenario: Stage records cache miss on new summary
    Given a proof obligation without a cached summary
    When the stage processes the obligation
    Then a cache miss is recorded
    And a new summary is computed and stored
