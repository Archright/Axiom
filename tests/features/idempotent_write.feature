Feature: Idempotent Write Guard
  As a deterministic build system
  I want to skip file writes when content is unchanged
  So that mtime is preserved and spurious git diffs are prevented

  Background:
    Given a file path and content string

  Scenario: Identical content skips write
    Given the file already exists with the same content
    When writeFileIdempotent is called
    Then the file should not be written
    And the return value should be false

  Scenario: Different content performs write
    Given the file exists with different content
    When writeFileIdempotent is called
    Then the file should be written with new content
    And the return value should be true

  Scenario: New file performs write
    Given the file does not exist
    When writeFileIdempotent is called
    Then the file should be created with the content
    And the return value should be true

  Scenario: IO failure returns false
    Given the file path is unwritable
    When writeFileIdempotent is called
    Then the return value should be false
    And no exception should propagate
