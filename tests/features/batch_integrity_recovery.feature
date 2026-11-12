@legacy
Feature: Batch integrity recovery
  As an Axiom operator
  I want unit, proof, vault, and heal gates to share deterministic integrity state
  So that repaired technical debt cannot hide behind partial test execution or stale ASI reports

  Background:
    Given the repository is at the Axiom project root
    And the CLI binaries are built from the current source tree

  Scenario: Unit orchestrator covers every unit test file
    When the unit test orchestrator scans tests/unit/*.nim
    Then every discovered unit test is compiled
    And every compiled unit test binary is executed
    And RED_ZONE is empty

  Scenario: Vault sync ignores stale proof-state nodes outside the current source universe
    Given logs/ax_proof_state.json contains verified historical entries
    When vault-sync reads the current source symbol graph
    Then proof-state entries not present in the current source graph are skipped
    And existing non-stale certificates are not overwritten
    And stale certificates are regenerated from proof-state evidence

  @deprecated
  Scenario: ASI reporting uses an absolute source root for default certificates
    Given the default certificate directory is addressed as a relative path
    When ax report --calculate-asi builds the source graph
    Then the source root is normalized to an absolute path before graph indexing
    And certificate garbage collection does not delete live default-layout certificates
    And ax prove --heal reports the same ASI value as verify-certificates

  Scenario: Lean proof gate accepts operator and path-qualified proof labels
    Given a Nim source file declares backtick-delimited operator symbols
    When ax prove builds proof targets from the topology graph
    Then operator declarations are included as proof nodes
    And SMT and Lean identifiers are sanitized through the canonical Axiom token sanitizer
    And verified proof-state entries do not retain timed out final status
