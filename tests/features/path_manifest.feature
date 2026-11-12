Feature: PATH Binary Manifest
  As the hermetic build engine
  I need a manifest of all binaries discoverable on PATH with their SHA-256 hashes
  So that hermetic builds can verify no unexpected binaries are used during compilation

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: computePathManifest finds binaries in PATH
    Given a PATH containing at least one known binary
    When I compute the path manifest
    Then the manifest includes an entry for each binary on PATH
    And each entry records the absolute path to the binary
    And each entry records the SHA-256 hash of the binary content

  Scenario: manifestHash is deterministic for identical PATH
    Given a PATH containing known binaries
    When I compute the path manifest twice with the same PATH
    Then the manifest hashes from both runs are identical

  Scenario: missing PATH returns an empty manifest
    Given PATH is set to an empty value
    When I compute the path manifest
    Then the manifest contains zero entries
    And the manifest hash represents an empty manifest
