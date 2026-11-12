Feature: SAD Gate
  Calculates Semantic Assertion Density and enforces minimum thresholds.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: sadScore returns 0.0 for empty file
    Given an empty test file
    When I calculate the SAD score
    Then the score should be 0.0

  Scenario: sadScore counts assertions correctly
    Given a test file with 3 check statements and 10 non-empty lines
    When I calculate the SAD score
    Then the score should be 0.3

  Scenario: sadScore ignores comment lines
    Given a test file with 2 check statements, 5 comment lines, and 10 total lines
    When I calculate the SAD score
    Then the score should be 0.4

  Scenario: isExempt returns true for annotated file
    Given a file with "@no-sad-required" in the first 10 lines
    When I check if the file is exempt
    Then the result should be true

  Scenario: isExempt returns false for unannotated file
    Given a file without "@no-sad-required" annotation
    When I check if the file is exempt
    Then the result should be false

  Scenario: auditFile returns arStub for zero-sad file
    Given a test file with SAD 0.0 and no exempt annotation
    When I audit the file
    Then the result should be arStub

  Scenario: Temporal tiering radius is deterministic
    Given the same date
    When I calculate the enforcement radius twice
    Then both results should be equal

  Scenario: formatHardeningNotice includes tier information
    Given an enforcement radius of 50
    When I format the hardening notice
    Then the notice should contain "Tier 50/100"
