Feature: make fail-closed — verification exit status must propagate
  As the Axiom integrity engine
  I want verification commands to propagate their exit status so that
  a failing verification causes CI to fail (fail-closed)

  Background:
    Given a throwaway Makefile is available for testing
    And the Anti-Theater Gate module is available

  Scenario: A failing verification command without swallow propagates non-zero exit
    Given a Makefile with a recipe containing "test 1 -eq 2" (which fails)
    When make runs the verification recipe
    Then make exits with a non-zero exit code

  Scenario: Appending "|| rm -rf" to a failing verification swallows the failure
    Given a Makefile with a recipe containing "test 1 -eq 2 || rm -rf /tmp/junk"
    When make runs the recipe
    Then make exits with exit code 0
    And this swallow pattern is a known-dangerous tripwire flagged by Rule C

  Scenario: A verification command without swallow that succeeds propagates zero exit
    Given a Makefile with a recipe containing "true" (which succeeds)
    When make runs the recipe
    Then make exits with exit code 0
