Feature: Gate Admin — CLI for managing gate policies and runtime state
  As the Axiom operator,
  I want a CLI to list, enable, and disable gates,
  So that I can manage gate policies without editing config files.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: list all gate IDs
    When I run gate_admin list
    Then the output contains all registered gate IDs
