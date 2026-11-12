Feature: path-free hash computation via MerkleVFS
  As the Hermetic Build Engine
  I want content-addressed hashing that is independent of file paths
  So that identical content always produces the same hash regardless of location

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: computeHash returns SHA-256 of content only
    Given a file with known ASCII content "hello world"
    When computeHash is called on the file
    Then the returned hash is the SHA-256 digest of "hello world"
    And the hash is a 64-character hexadecimal string

  Scenario: same content produces same hash regardless of path
    Given two files in different directories with identical content
    When computeHash is called on each file
    Then both hashes are equal
    And the hashes differ from a file with different content

  Scenario: empty content has known hash
    Given an empty file with zero bytes
    When computeHash is called on the file
    Then the returned hash equals the SHA-256 of the empty string
    And the hash matches the known reference value e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

Feature: 4-stage VFS pipeline with binary cache and parallel hashing
  As the Hermetic Build Engine
  I want an incremental VFS pipeline that skips unchanged files and hashes in parallel
  So that gate evaluation is fast and scales to large repositories

  Scenario: discoverFiles walks directory recursively
    Given a directory with files in nested subdirectories
    When discoverFiles is called on the root path
    Then all non-excluded files are returned sorted by path
    And excluded directories like .git and nimcache are skipped

  Scenario: VfsCache binary round-trip preserves entries
    Given a VfsCache with multiple file entries and hashes
    When the cache is flushed to disk as binary
    And loaded back from disk
    Then all entries match the original with correct mtime size and hash

  Scenario: diffAgainstCache separates unchanged from work queue
    Given a VfsCache containing entries for known files
    And a file list where some files have changed mtime or size
    When diffAgainstCache is called
    Then unchanged files are returned in the unchanged list
    And changed or new files are returned in the work queue

  Scenario: parallelHash computes SHA-256 for multiple files
    Given a work queue of files to hash
    When parallelHash is called with the work queue
    Then each file gets a valid SHA-256 hex digest
    And the results are stored in a table keyed by relative path

  Scenario: buildVfsFromCache reconstructs VFS without disk I/O
    Given a fully populated VfsCache with correct hashes
    When buildVfsFromCache is called
    Then a valid MerkleVfs is returned with matching root hash
    And no filesystem reads are performed
