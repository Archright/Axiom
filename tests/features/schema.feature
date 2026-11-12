Feature: Schema — core data schema definitions for Axiom types
  As the Axiom core engine,
  I want a schema module defining canonical data types,
  So that all modules share a single source of truth for structures.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: schema defines the GateResult type
    Given the core schema is loaded
    When I inspect the GateResult type
    Then GateResult has fields for status, message, and evidence

  Scenario: schema version is accessible at compile time
    Given the core schema is loaded
    When I read the schema version constant
    Then the version is a non-empty string
