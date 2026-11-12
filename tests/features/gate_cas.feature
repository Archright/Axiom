Feature: Gate CAS — content-addressable storage for gate binaries
  As the Gate Infrastructure,
  I want gate binaries stored by content hash in .axiom/cas/,
  So that identical source produces identical binaries without duplication.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: store and retrieve a binary by content hash
    Given a compiled gate binary with hash "sha256abc"
    When I call casStore with the binary
    And I call casLookup for hash "sha256abc"
    Then the lookup returns the binary path

  Scenario: resolveCasBinaryPath returns absolute path
    Given a gate "test-gate" with known source hash
    When I call resolveCasBinaryPath for "test-gate"
    Then the result is an absolute path under .axiom/cas/

  Scenario: duplicate store is idempotent
    Given a binary already stored with hash "sha256abc"
    When I call casStore again with the same binary
    Then no duplicate entry is created
