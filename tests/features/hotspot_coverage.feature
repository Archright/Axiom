Feature: Hotspot Coverage Gate
  As the Gate System,
  I want to enforce test coverage on high-churn (hotspot) source modules,
  So that frequently-modified code is always backed by tests.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: All hotspots have tests — gate passes
    Given a repository with source modules and matching test files
    When the hotspot-coverage-gate computes churn
    Then the gate identifies top-10% files as hotspots
    And every hotspot has a corresponding test file
    And the gate exits with code 0

  Scenario: Missing test for hotspot — gate fails with details
    Given a repository with a high-churn module lacking a test file
    When the hotspot-coverage-gate computes churn
    Then the gate identifies the module as a hotspot
    And the gate reports uncovered hotspots on stderr
    And the gate exits with code 1

  Scenario: New module with low churn — not a hotspot
    Given a repository with a new module that has low modification count
    When the hotspot-coverage-gate computes churn
    Then the new module is not classified as a hotspot
    And the gate exits with code 0

  Scenario: Empty repository — no source files
    Given a repository with no tracked .nim source files
    When the hotspot-coverage-gate computes churn
    Then the gate reports zero hotspots
    And the gate exits with code 0

  Scenario: Self-test validates core functions
    When the hotspot-coverage-gate runs in self-test mode
    Then the self-test exits with code 0

  # ── Tiered coverage enforcement ──────────────────────────────────

  Scenario: Tier 1 hotspot modules require 100% test coverage
    Given the hotspot coverage gate is loaded
    When tier 1 has 14 of 15 modules with tests
    Then the gate should FAIL with tier 1 coverage gap

  Scenario: Tier 1 hotspot modules all covered — gate passes
    Given the hotspot coverage gate is loaded
    When tier 1 has 15 of 15 modules with tests
    Then the gate should PASS for tier 1

  Scenario: Tier 2 hotspot modules require 80% test coverage
    Given the hotspot coverage gate is loaded
    When tier 2 has 28 of 35 modules with tests
    Then the gate should PASS for tier 2

  Scenario: Tier 2 hotspot modules below threshold — gate fails
    Given the hotspot coverage gate is loaded
    When tier 2 has 25 of 35 modules with tests
    Then the gate should FAIL with tier 2 coverage gap

  Scenario: Tier 3 hotspot modules require 50% test coverage
    Given the hotspot coverage gate is loaded
    When tier 3 has 50 of 90 modules with tests
    Then the gate should PASS

  Scenario: Tier 3 hotspot modules below threshold — gate fails
    Given the hotspot coverage gate is loaded
    When tier 3 has 40 of 90 modules with tests
    Then the gate should FAIL with tier 3 coverage gap

  Scenario: All tiers pass — overall gate passes
    Given the hotspot coverage gate is loaded
    When tier 1 has 15 of 15 modules with tests
    And tier 2 has 30 of 35 modules with tests
    And tier 3 has 60 of 90 modules with tests
    Then the gate should PASS

  Scenario: One tier fails — overall gate fails with gap details
    Given the hotspot coverage gate is loaded
    When tier 1 has 15 of 15 modules with tests
    And tier 2 has 25 of 35 modules with tests
    And tier 3 has 60 of 90 modules with tests
    Then the gate should FAIL with tier 2 coverage gap
