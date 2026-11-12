@legacy
Feature: Nim AST → Axiom Core IR Conversion
  Converts Nim function definitions into Axiom Core IR for the formal
  verification pipeline. Handles int/bool types, arithmetic ops,
  let/if/case control flow, and recursive calls. Well-founded metric
  boundary assertion for while-loop termination via loopVariant.

  Background:
    Given the Axiom system is initialized

  Scenario: AST to IR conversion produces valid IRFuncDef
    When ast_to_ir converts a Nim function definition
    Then the result is a valid IRFuncDef

  Scenario: While-loop produces loopVariant metric
    Given a while-loop with numeric condition
    When ast_to_ir converts the AST
    Then the IR contains loopVariant field

  Scenario: Recursive call detection
    Given a recursive function definition
    When ast_to_ir converts the AST
    Then the IR marks the call as irRecCall
