@legacy
Feature: ax topology apply
  As an Axiom developer
  I want to reconcile the filesystem with topology.json declaratively
  So that architectural intent is preserved automatically and safely.

  Background:
    Given the project has a valid topology.json declaration

  @executable
  Scenario: Dry-run shows planned moves and rewrites without changes
    Given "src/core/drifted.nim" is mapped to the "core/target" subdomain
    And "src/consumer.nim" imports "core/drifted"
    When I run "ax topology apply --dry-run"
    Then the plan includes moving "src/core/drifted.nim" to "src/core/target/drifted.nim"
    And the plan includes rewriting "src/consumer.nim" to import "core/target/drifted"
    And no files are modified

  @executable
  Scenario: Apply moves a drifted file and rewrites consumers atomically
    Given "src/core/drifted.nim" is mapped to the "core/target" subdomain
    And "src/consumer.nim" imports "core/drifted"
    When I run "ax topology apply --auto-approve --force"
    Then "src/core/target/drifted.nim" exists
    And "src/core/drifted.nim" does not exist
    And "src/consumer.nim" contains "import core/target/drifted"
    And topology.lock revision is incremented

  @executable
  Scenario: Apply rolls back on validation failure
    Given "src/core/drifted.nim" is mapped to the "core/target" subdomain
    And "src/consumer.nim" imports "core/drifted"
    And the consumer file has a deliberate syntax error after rewrite
    When I run "ax topology apply --auto-approve --force"
    Then "src/core/drifted.nim" still exists at its original location
    And "src/consumer.nim" is unchanged
