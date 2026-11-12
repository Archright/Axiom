@legacy
Feature: Proof Preservation and Tautology Fast-Track
  As an Axiom developer
  I want existing certGreen nodes preserved and tautology proofs fast-tracked
  So that ASI stops declining and tautology throughput accelerates

  Scenario: Existing certGreen node is skipped during heal
    Given a node with an existing certGreen certificate
    When executeHealNode is called
    Then isAlreadyCertGreen returns true
    And the node is skipped without re-evaluation

  Scenario: Tautology proof writes certGreen directly
    Given a SemanticHint with strategy isTautologyProof
    When saveHint is called
    Then sentinel and vacuity checks are bypassed
    And a certGreen certificate is written immediately
    And the certificate records winningStrategy "isTautologyProof"

  Scenario: Same function names in different modules are preserved
    Given a certGreen certificate exists for src/a.nim::shared
    When saveHint writes a pseudo-verified certificate for src/b.nim::shared
    Then the src/a.nim::shared certificate remains in the vault
    And the src/b.nim::shared certificate is written separately

  Scenario: Tail-only proof state module paths resolve to source-relative paths
    Given src/core/results.nim exists
    When saveHint receives nodeId results.nim::ok
    Then the certificate modulePath is core/results.nim
    And no orphan results_nim__ok certificate is created
