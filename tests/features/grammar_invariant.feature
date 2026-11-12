@legacy
Feature: Grammar Invariant
  As an Axiom engineer
  I want Leanstral-generated Lean 4 source to be sanitized before compilation
  So that syntax errors are prevented and retry loops are avoided

  Background:
    Given the Axiom engine is initialized

  Scenario: Trailing semicolons are removed
    When Leanstral generates "simp;"
    And sanitizeLeanSource is applied
    Then the output should not contain "simp;"

  Scenario: Lean 3 tactic sequencing is replaced
    When Leanstral generates "by simp ; trivial"
    And sanitizeLeanSource is applied
    Then the output should not contain " ; "

  Scenario: Syntax errors are recorded in blacklist
    When Lean compiler rejects with "unexpected token ';'"
    Then leanstral_blacklist.json should contain "unexpected token ';'"
