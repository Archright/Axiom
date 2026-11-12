Feature: Import Encapsulation Gate — module import boundary enforcement
  As the Gate Infrastructure,
  I want to enforce import encapsulation rules between modules,
  So that layer boundaries are not violated by transitive imports.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: valid imports pass
    Given staged files with proper import encapsulation
    When I run the import encapsulation gate
    Then the gate passes
