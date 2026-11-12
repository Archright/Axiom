@legacy
Feature: Global Symbol Graph Tree-Sitter Fallback

  @deprecated
  Scenario: ax prove succeeds when tree-sitter is unavailable
    Given tree-sitter CLI is not installed on the host
    And the repository contains Nim source files with proc declarations
    When I run "ax prove src --no-graph-cache"
    Then the command should exit with code 0
    And "proof_universe.lock" should be generated
    And the lock file should contain "asiFixed4" equal to "1.0000"
    And the global symbol graph should contain at least 200 symbols

  Scenario: fallback extracts basic proc declarations
    Given a Nim module with 5 declarations (proc, func, method, iterator, converter)
    When the module is parsed without tree-sitter
    Then all 5 qualified names should appear in the symbol graph
    And each symbol should have kind skProc or skFunc
