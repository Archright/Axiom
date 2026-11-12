@manual @critical
Feature: spec_presence_gate
  # manual | src/gate/runners/spec_presence_gate.nim | gate | critical
  BDD Contract Gate (Tier 0): ensures every staged .nim has spec evidence.

  Background:
    Given the spec-presence-gate binary is compiled
    And the working tree is clean

  Scenario: Module with feature file passes spec check
    Given a staged module "spec_presence_gate" exists in src/gate/runners/
    And a feature file "spec_presence_gate.feature" exists in tests/features/
    When the spec-presence-gate runs
    Then the exit code is 0

  Scenario: Module without any spec evidence fails
    Given a staged module "orphan_module" exists in src/core/
    And no feature file or test file exists for "orphan_module"
    When the spec-presence-gate runs
    Then the exit code is 1
    And stderr contains "missing feature specification"

  Scenario: Feature files in generated/ subdirectory are discovered
    Given a feature file exists at "tests/features/generated/nimtry_cli.feature"
    When the gate scans for feature files recursively
    Then "nimtry_cli" is found in the feature set

  Scenario: Stale orphan features do not cause false positives
    Given a module "deleted_module" was removed from src/
    And the orphan feature "deleted_module.feature" was cleaned up
    When a new module "deleted_module" is created without spec evidence
    Then the gate correctly reports "deleted_module" as missing spec evidence
