Feature: Nimtry AST Fact Extraction
  As a static analysis gate
  In order to enforce architecture constraints
  The nimtry extractor must safely parse Nim AST nodes
  Without crashing on edge-case node shapes

  @spec-density: 60
  Scenario: targetToString handles single-child bracket expressions safely
    Given a Nim AST node of kind nkBracketExpr with only 1 child
    When targetToString processes the node
    Then it returns the string representation of the single child
    And no IndexDefect is raised

  @spec-density: 60
  Scenario: targetToString handles single-child dot expressions safely
    Given a Nim AST node of kind nkDotExpr with only 1 child
    When targetToString processes the node
    Then it returns the string representation of the single child
    And no IndexDefect is raised

  @spec-density: 60
  Scenario: Assignment extraction walks all nested AST nodes
    Given a source file with assignments inside nested control flow
    When extractAssignmentsV4 processes the AST
    Then all assignment targets are captured
    And source locations are accurate
