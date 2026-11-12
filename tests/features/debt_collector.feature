Feature: Debt Collector — compile-time axiomCollect macro for debt scanning
  As the Axiom quality gate system,
  I want a compile-time macro that scans for hardcoded paths and debt markers,
  So that technical debt is detected at compile time rather than runtime.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: axiomCollect passes clean code without errors
    Given a module with no hardcoded paths or debt markers
    When I compile with -d:axiomScan
    Then compilation succeeds without errors

  Scenario: axiomCollect detects hardcoded absolute paths
    Given a module containing the string "/home/user/project"
    When I compile with -d:axiomScan
    Then the compiler emits an error containing "HARDCODED ABSOLUTE PATH"

  Scenario: axiomCollect without -d:axiomScan is a no-op
    Given a module containing a hardcoded path
    When I compile without -d:axiomScan
    Then compilation succeeds without debt hints

  Scenario: axiomCollect detects axiomDebt pragma hints
    Given a module with a proc annotated {.axiomDebt: "DEBT-001".}
    When I compile with -d:axiomScan
    Then the compiler emits a hint containing "AXIOM_DEBT:DEBT-001"
