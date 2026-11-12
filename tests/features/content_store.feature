Feature: Content Store (256-shard CAS)
  As the hermetic build engine
  I need a content-addressable store backed by 256-shard directories at .axiom/store/
  So that build artifacts are deduplicated and integrity-verified by SHA-256 hash

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: put and get object round-trip
    Given a content store is initialized in the temporary directory
    When I put an object with known content into the store
    Then the returned hash is a valid SHA-256 digest
    And I can get the same object back by its hash
    And the retrieved content matches the original content

  Scenario: putChecked verifies content hash matches
    Given a content store is initialized in the temporary directory
    When I putChecked an object with a mismatched expected hash
    Then a hash mismatch error is raised
    And the object is not persisted in the store

  Scenario: getOpt returns None for missing object
    Given a content store is initialized in the temporary directory
    When I request an object by a hash that does not exist
    Then getOpt returns None

  Scenario: put is idempotent for identical content
    Given a content store is initialized in the temporary directory
    When I put the same object into the store twice
    Then the returned hashes are identical
    And the shard directory contains exactly one entry for that hash
