Feature: Immunity Gate — raises-annotation coverage + ratchet
  As the Static First Enforcement policy,
  I want a gate that verifies every proc/func in src/core carries a raises annotation,
  So that the Effect-Free Core discipline cannot silently regress.

  Background:
    Given the immunity gate scans all modules under src/core/
    And a coverage baseline exists in data/immunity_baseline.json

  Scenario: inline raises annotation counts as covered
    Given a module with procs annotated {.raises: [].}
    When scanRaisesCoverage scans the module
    Then those procs are counted as annotated

  Scenario: file-scoped push raises is honored
    Given a module that opens with {.push raises: [].}
    And closes with {.pop raises.}
    When scanRaisesCoverage scans the module
    Then every proc inside the push scope is counted as annotated

  Scenario: coverage below baseline fails the ratchet
    Given the computed coverage is below the frozen baseline threshold
    When the immunity gate evaluates the result
    Then the gate fails
    And the report lists the uncovered declaration count

  Scenario: coverage meeting baseline passes
    Given the computed coverage meets or exceeds the baseline threshold
    When the immunity gate evaluates the result
    Then the gate passes
