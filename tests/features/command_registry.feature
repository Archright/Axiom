Feature: Command Registry — central registry of CLI subcommands
  As the Axiom CLI framework,
  I want a registry that maps command names to handlers,
  So that subcommands can be discovered and dispatched deterministically.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: register and dispatch a command
    Given a registered command "prove" with a handler
    When I dispatch the command "prove"
    Then the handler for "prove" is invoked

  Scenario: dispatching an unknown command returns an error
    Given no command registered as "unknown-cmd"
    When I dispatch the command "unknown-cmd"
    Then an unknown-command error is returned
