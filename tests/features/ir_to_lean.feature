@legacy
Feature: IR → Lean 4 Code Generation
  Converts Axiom Core IR into syntactically valid Lean 4 source code with
  automatic termination handling. Supports structural descent, numeric
  descent with termination_by omega, and fallback partial def.

  Background:
    Given the Axiom system is initialized

  Scenario: IR function def to Lean theorem
    When irToLean converts an IRFuncDef
    Then the result is valid Lean 4 syntax

  Scenario: While-loop generates if h : cond guard
    Given an IR loop with loopVariant
    When irToLean generates Lean code
    Then the output contains "if h : cond"

  Scenario: Termination by metric for numeric loops
    Given a numeric while-loop
    When irToLean generates termination clause
    Then the output contains "termination_by"

  Scenario: Omega decreasing proof
    Given a termination_by clause
    When irToLean generates decreasing proof
    Then the output contains "decreasing_by omega"
