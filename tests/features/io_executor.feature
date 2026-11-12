Feature: I/O Executor — interface for deterministic I/O operations
  As the Axiom core engine,
  I want an I/O executor interface that abstracts filesystem operations,
  So that side-effecting I/O is isolated from pure logic modules.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: executor reads an existing file successfully
    Given a file "test.txt" with content "hello"
    When I call the executor's readFile on "test.txt"
    Then the returned content is "hello"

  Scenario: executor returns an error for a missing file
    Given no file at path "missing.txt"
    When I call the executor's readFile on "missing.txt"
    Then an I/O error is returned
