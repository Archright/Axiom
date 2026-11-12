Feature: Gate Definitions — Nim DSL for gate declarations
  As the Gate Infrastructure,
  I want a Nim DSL for declaring gate definitions,
  So that gates can be defined with compile-time validation.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: validate gate definitions at compile time
    Given a set of gate definitions in gate_defs.nim
    When the module is compiled
    Then all gate IDs are unique
    And the DAG is acyclic
    And all critical gates are properly marked
