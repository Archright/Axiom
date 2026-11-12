Feature: Script Registry — registry of build and utility scripts
  As the Axiom runtime,
  I want a registry mapping script names to their file paths,
  So that scripts can be invoked by symbolic name rather than path.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: registered script is resolved by name
    Given a script "lint" registered at "tools/lint.nim"
    When I resolve the script name "lint"
    Then the resolved path is "tools/lint.nim"

  Scenario: unregistered script name returns an error
    Given no script registered as "nonexistent"
    When I resolve the script name "nonexistent"
    Then a script-not-found error is returned
