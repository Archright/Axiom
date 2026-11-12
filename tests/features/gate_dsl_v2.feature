Feature: GateDef extended with inputs/outputs fields
  As the Hermetic Build Engine
  I want the gate DSL to support declared inputs and outputs in GateDef
  So that gates can express their resource contracts at definition time

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: gateDef with inputs/outputs parses correctly
    Given a DSL string defining a gate with inputs and outputs fields
    When the DSL is parsed into a GateDef
    Then the resulting GateDef contains the correct input declarations
    And the resulting GateDef contains the correct output declarations

  Scenario: output collision detection in DSL
    Given two DSL gate definitions that declare overlapping output paths
    When both GateDefs are registered
    Then an output collision is detected
    And the detection report names both conflicting gate definitions

  Scenario: backward compatibility with v1 GateDef
    Given a DSL string using the v1 GateDef format without inputs or outputs
    When the DSL is parsed
    Then the parsing succeeds without errors
    And the resulting GateDef has empty inputs and outputs lists
    And the v1-specific fields are preserved unchanged
