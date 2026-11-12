Feature: Compile-Time Manifest — frozen build metadata at compile time
  As the Axiom build system,
  I want a compile-time manifest that embeds version and gate state,
  So that every binary carries immutable build provenance.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: manifest embeds expected constants
    Given a compile-time manifest generated from current sources
    When I read the manifest constants
    Then the manifest contains non-empty build hash and version fields

  Scenario: manifest is deterministic for identical inputs
    Given two compile-time manifests generated from the same sources
    When I compare the two manifests
    Then the manifests are byte-identical
