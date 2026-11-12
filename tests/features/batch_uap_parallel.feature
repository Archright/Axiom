Feature: Parallel Batch UAP Verification
  As an Axiom engineer
  I want batch UAP processing to run in parallel via malebolgia
  So that verification throughput scales with available CPU cores

  Background:
    Given the Axiom engine is initialized
    And the proof vault directory is isolated via AXIOM_PROVE_VAULT_DIR

  Scenario: Parallel batch UAP produces deterministic results
    Given a set of proof obligations for 20 modules
    When batch UAP is executed with 1 worker
    And batch UAP is executed with 2 workers on a separate vault
    Then both executions should produce identical certificate hashes

  Scenario: AXIOM_PROVE_VAULT_DIR isolates proof artifacts
    Given a custom vault directory is set via environment variable
    When ax prove is executed
    Then proof artifacts should be written to the custom vault
    And the default logs/proof_vault should remain untouched

  Scenario: Depth-parallel processing respects topology ordering
    Given a dependency topology with multiple depth levels
    When parallel batch UAP processes the topology
    Then modules at the same depth level should execute concurrently
    And modules at different depth levels should respect dependency order
