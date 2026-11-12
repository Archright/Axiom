Feature: Axiom Local Docs Lookup — offline documentation search from CLI
  As the Axiom CLI user,
  I want to look up local documentation by keyword,
  So that I can find relevant specs without leaving the terminal.

  Background:
    Given the Axiom gate infrastructure is initialized
    And the local docs directory is available

  Scenario: lookup returns matching documents for a known keyword
    Given a local docs index containing "gate_manifest"
    When I invoke axiom_local_docs_lookup with query "gate manifest"
    Then the result contains the path to the gate manifest documentation

  Scenario: lookup returns empty for an unknown keyword
    Given no local docs match "nonexistent_xyzzy"
    When I invoke axiom_local_docs_lookup with query "nonexistent_xyzzy"
    Then the result is an empty list
