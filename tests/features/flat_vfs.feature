Feature: Flat VFS — Cache-Local Sorted Seq Virtual File System
  As the gate hook architecture
  I want a sorted-seq VFS with migration-ready interface
  So that gate runners can perform fast path lookups without disk I/O

  Background:
    Given the FlatVfs module is available
    And a temporary test directory exists

  Scenario: hashPath produces deterministic FNV-1a hash
    Given a path string "src/core/gate/gate_memo.nim"
    When hashPath is called on the path
    Then the returned hash is a non-zero uint64
    And calling hashPath again with the same path returns the same hash

  Scenario: findEntry returns opaque VfsHandle for existing path
    Given a FlatVfs built from a VfsCache with known files
    When findEntry is called with a path that exists
    Then the returned VfsHandle is not nil
    And pathOf on the handle returns the original path string
    And contentHashOf returns a 64-character hex SHA-256

  Scenario: findEntry returns nil handle for missing path
    Given a FlatVfs built from a VfsCache with known files
    When findEntry is called with a path that does not exist
    Then the returned VfsHandle equals VfsHandle(nil)

  Scenario: collectChangedFiles detects content differences
    Given two FlatVfs snapshots with different content hashes for one file
    When collectChangedFiles is called comparing the two
    Then the changed file path is in the result list
    And unchanged files are not in the result list

  Scenario: getMerkleRoot is deterministic across sorted file sets
    Given a FlatVfs with three files having known SHA-256 hashes
    When getMerkleRoot is called
    Then the returned root is a valid SHA-256 hex string
    And calling getMerkleRoot again returns the identical root
