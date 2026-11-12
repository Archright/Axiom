Feature: Axiom Runner — top-level execution entry point for Axiom commands
  As the Axiom CLI,
  I want a runner that orchestrates command parsing and execution,
  So that CLI invocations are dispatched through a single entry point.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: runner executes a valid command successfully
    Given a valid CLI invocation "ax prove src/main.nim"
    When I invoke the axiom runner
    Then the command completes with exit code 0

  Scenario: runner returns non-zero for an invalid invocation
    Given an invalid CLI invocation with missing arguments
    When I invoke the axiom runner
    Then the command returns a non-zero exit code
