Feature: Doc Completeness Gate — documentation completeness enforcement
  As the Gate Infrastructure,
  I want to verify that modified modules have adequate documentation,
  So that code changes are accompanied by documentation updates.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: documented modules pass
    Given staged files that have corresponding documentation
    When I run the doc completeness gate
    Then the gate passes
