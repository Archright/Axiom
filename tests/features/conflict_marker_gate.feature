Feature: Conflict Marker Gate
  As the Gate System,
  I want to detect leftover conflict markers and CONFLICT_UNRESOLVED annotations in staged files,
  So that incomplete merges/rebases are blocked before commit.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: Detects conflict markers in staged .nim files
    Given a staged file containing "<<<<<<< HEAD" markers
    When the conflict-marker-gate scans the file
    Then the gate reports blocking findings with severity "error"
    And the gate exits with code 1

  Scenario: Passes when no conflict markers found
    Given a staged file with clean content
    When the conflict-marker-gate scans the file
    Then the gate reports zero findings
    And the gate exits with code 0

  Scenario: Receives repoRoot and mode from dispatcher
    Given the gate manifest defines argsTemplate with $repoRoot, $mode, $maxJobs
    When the gate hook dispatches the gate
    Then the binary receives positional arguments from argsTemplate
