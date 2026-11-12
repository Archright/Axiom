Feature: AST Hash
  Deterministic AST-based source hashing that ignores whitespace and comments.

  Background:
    Given the Axiom infrastructure is initialized

  Scenario: computeAstHash returns deterministic result
    Given a valid Nim source string
    When I compute the AST hash twice
    Then both hashes should be equal

  Scenario: computeAstHash ignores whitespace differences
    Given two source strings differing only in whitespace
    When I compute the AST hash for each
    Then both hashes should be equal

  Scenario: computeAstHash ignores comments
    Given two source strings differing only in comments
    When I compute the AST hash for each
    Then both hashes should be equal

  Scenario: computeAstHash detects structural changes
    Given two source strings with different AST structure
    When I compute the AST hash for each
    Then the hashes should differ

  Scenario: computeAstHash falls back to content hash on parse failure
    Given an invalid source string that cannot be parsed
    When I compute the AST hash
    Then a non-zero hash should be returned
