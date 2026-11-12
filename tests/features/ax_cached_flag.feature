@manual
Feature: --cached CLI flag replaces AXIOM_FREEZE_GRAPH_CACHE env var
  As an Axiom developer
  I want to use --cached instead of AXIOM_FREEZE_GRAPH_CACHE=1
  So that cache lock state is deterministically controlled via CLI SSOT

  Background:
    Given the project builds successfully

  Scenario: stripGlobalFlags isolates --cached from positional args
    When I call stripGlobalFlags with ["prove", "--limit", "50", "--cached"]
    Then processed args are ["prove", "--limit", "50"]
    And the flag set contains "cached"

  Scenario: --cached flag triggers cached=true in buildGlobalSymbolGraph
    Given AXIOM_FREEZE_GRAPH_CACHE is unset
    When I run "ax report --calculate-asi --cached"
    Then the timing log contains "cached=true"
