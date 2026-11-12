Feature: File Utilities — safe file operations for the Axiom core
  As the Axiom core engine,
  I want utility functions for safe file reading, writing, and existence checks,
  So that file I/O is centralized behind tested wrappers.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: fileExists returns true for an existing file
    Given a file "test.txt" in the test directory
    When I call fileExists on "test.txt"
    Then the result is true

  Scenario: fileExists returns false for a missing file
    Given no file "missing.txt" in the test directory
    When I call fileExists on "missing.txt"
    Then the result is false
