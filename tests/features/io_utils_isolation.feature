Feature: IO utilities isolation
  As a developer
  I want isolated file operations with error containment
  So that IO failures don't propagate unexpectedly

  Scenario: Move file with valid paths
    Given a source file and a destination path
    When isolatedMoveFile is called
    Then the file is moved to the destination

  Scenario: Move file with non-existent source
    Given a non-existent source path
    When isolatedMoveFile is called
    Then the operation fails gracefully without crashing

  Scenario: Write file with valid content
    Given a path and content string
    When isolatedWriteFile is called
    Then the content is written to the file
