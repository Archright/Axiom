Feature: Validate Effect Hints Gate
  As the Axiom integrity pipeline,
  I want to verify that all {.axiomIoBoundary.} and effect pragmas are consistent,
  So that the static-first enforcement policy is maintained.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: proc with I/O calls must have axiomIoBoundary pragma
    Given a Nim source file with a proc that calls writeFile
    When the validate-effect-hints-gate scans the file
    Then the proc must have the {.axiomIoBoundary.} pragma

  Scenario: func must not have axiomIoBoundary pragma
    Given a Nim source file with a func declaration
    When the validate-effect-hints-gate scans the file
    Then the func must not have the {.axiomIoBoundary.} pragma

  Scenario: passFilenames isolation
    When the gate is queried for passFilenames
    Then passFilenames returns true
    And the gate only receives changed files, not the full manifest
