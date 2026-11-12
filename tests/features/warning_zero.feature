@legacy
Feature: Warning Zero — Compiler Hygiene Completion
  Ensures the codebase reaches zero compiler hints and deterministic
  dependency locking after the Great Refinement.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And nimble configuration exists at "axiom.nimble"

  Scenario: nim check produces zero unused-declaration hints
    When nim check is executed on `src/cli/main.nim` with threading enabled
    Then no XDeclaredButNotUsed hints remain
    And no loop-invariant warnings remain

  Scenario: Dependency versions are pinned in lock file
    Given "axiom.nimble" requires "checksums >= 0.2.0"
    When `nimble lock` is executed
    Then "nimble.lock" is generated successfully
    And "checksums" appears in the lock file

  Scenario: CONTEXT.md has no duplicate table headers
    When CONTEXT.md is parsed
    Then the Open Challenges table has exactly one header row
