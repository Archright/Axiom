@legacy
Feature: Symbolic Path Condition Extraction
  As an Axiom verification pipeline
  I want boundary extraction to analyze control-flow AST nodes
  So that functions with branches and loops receive non-trivial semantic hints

  Background:
    Given the Axiom boundary extractor is loaded
    And tree-sitter AST parsing is available

  Scenario: Extract while-loop condition with dot expression
    Given a function containing "while i < text.len"
    When `extractPathConditions` is called on its AST
    Then the result should contain `(> (str.len text) 0)` or `(< i (str.len text))`
    And the Lean proposition should contain `text.length`

  Scenario: Extract if-condition with strict comparison
    Given a function containing "if s.len > 0"
    When `extractPathConditions` is called on its AST
    Then the result should contain `(> (str.len s) 0)`
    And `isTrivialConstraint` should return false for this condition

  Scenario: Extract nested boolean conditions
    Given a function containing "if a > 0 and b < 10"
    When `extractPathConditions` is called on its AST
    Then the result should contain a single SMT `(and ...)` expression
    And the expression should include both `a > 0` and `b < 10`

  Scenario: Deduplicate repeated conditions across branches
    Given a function with multiple "elif current.len > 0" branches
    When `extractPathConditions` is called on its AST
    Then `current.length > 0` should appear exactly once in the output

  Scenario: BoundaryExtractor no longer returns none for control-flow functions
    Given `tokenizeLowered` which contains while/if/elif/else
    When `extractBoundaries` is called
    Then the result should not be `bcTrivialDiscard`
    And the generated hint should include `i < text.length`
