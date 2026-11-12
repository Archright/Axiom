Feature: Project Root — deterministic root resolution via getAppDir
  As the Axiom runtime,
  I want a single source of truth for the project root directory,
  So that all modules resolve paths deterministically without hardcoded values.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: getProjectRoot returns a non-empty string
    When I call getProjectRoot()
    Then the result is a non-empty string
    And the result is an absolute path

  Scenario: getProjectRoot returns the same value on repeated calls
    Given I call getProjectRoot() and store the result as "first"
    When I call getProjectRoot() and store the result as "second"
    Then "first" equals "second"
