Feature: wf_semantic — Workflow Semantic Translation
  As a contributor working with the Axiom workflow engine,
  the wf_semantic module must provide semantic translation
  of workflow definitions into the internal representation.

  Background:
    Given the wf_semantic module is compiled
    And the working directory is the Axiom project root

  # ── Semantic translation ─────────────────────────────────────────

  Scenario: Workflow definition parsed into semantic model
    Given a valid workflow definition file
    When the semantic translation processes the definition
    Then it should produce a valid semantic model
    And the model should contain all declared steps

  Scenario: Empty workflow produces minimal model
    Given an empty workflow definition
    When the semantic translation processes the definition
    Then it should produce a valid semantic model
    And the model should have zero steps
