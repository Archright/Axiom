@legacy
Feature: SSA Extractor Enhancement
  As an Axiom developer
  I want the SSA extractor to find more constraints from Nim ASTs
  So that boundary extraction produces richer invariants for Lean theorem generation

  Background:
    Given the boundary_extractor module "src/core/boundary_extractor.nim"

  Scenario: Multi-tag search finds assert in call_expression nodes
    Given a function AST with an assert call in a call_expression node
    When extractPathConditions is called with multi-tag search
    Then the assert condition is extracted as a path condition

  Scenario: Multi-tag search finds assignment in asgn nodes
    Given a function AST with variable assignment using asgn tag
    When extractPathConditions is called with multi-tag search
    Then the assignment constraint is extracted

  Scenario: Multi-tag search finds return in return nodes
    Given a function AST with a return statement using return tag
    When extractPathConditions is called with multi-tag search
    Then the return constraint is extracted

  Scenario: if_expression is converted to SMT ite
    Given an if_expression AST node with condition, consequence, and alternative
    When convertExpressionToSmtLean is called
    Then the SMT output contains "ite"
    And the Lean output contains "if ... then ... else"

  Scenario: let_section extracts initial value constraints
    Given a let_section AST node with variable declaration and initial value
    When convertExpressionToSmtLean is called
    Then the output is an equality constraint linking name to value

  Scenario: Loop invariants are injected from liquid inference
    Given a function AST with a for loop with liquid-inferred bounds
    When extractPathConditions is called
    Then invariants from envToInvariantCandidates are appended to conditions
