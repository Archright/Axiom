Feature: Architecture Guard LFS Pointer Validation
  As an Axiom maintainer
  I want the architecture guard to validate LFS pointers without deadlocking
  So that pre-push checks complete reliably even for large repositories

  Background:
    Given the repository has git-lfs installed
    And the docs/spec directory contains LFS-tracked PDF files

  Scenario: LFS-tracked files are identified via git lfs ls-files
    When the architecture guard scans the repository
    Then it should discover all LFS-tracked files
    And each discovered file should be a valid LFS pointer in the index

  Scenario: Architecture guard completes within the gate timeout
    When the architecture guard runs as part of pre-push gates
    Then it should finish in less than 150 seconds
    And the exit code should be 0

  Scenario: Binary blobs in the index are reported as violations
    Given an LFS-tracked file is stored as a binary blob in the index
    When the architecture guard validates LFS pointers
    Then it should report an LFS pointer violation for that file
