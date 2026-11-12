Feature: Structural Safety Checker
  Source-level scan that validates structural invariants including
  ref object proc fields, func var parameters, and import boundaries.

  Background:
    Given the structural_safety_checker module is used by gate runners

  Scenario: ref object pattern detection in source code
    Given a source file containing "ref object" with proc fields
    When the structural safety checker scans the source
    Then the violation should be reported with file and line number

  Scenario: import boundary violation detection
    Given a core module importing from gate/runner path
    When the structural safety checker scans the source
    Then the import boundary violation should be reported

  Scenario: clean source passes structural safety check
    Given a source file with no structural violations
    When the structural safety checker scans the source
    Then no violations should be reported
