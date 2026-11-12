Feature: Feature Manifest Guard — ensures all features are tracked in the manifest
  As the Axiom gate layer,
  I want a guard that validates feature manifest completeness,
  So that no feature ships without an explicit manifest entry.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: guard passes when all features are in the manifest
    Given a feature manifest covering all registered features
    When I run the feature manifest guard
    Then the guard passes

  Scenario: guard fails when a feature is missing from the manifest
    Given a feature "new_module" not listed in the manifest
    When I run the feature manifest guard
    Then the guard fails with a missing-feature error
