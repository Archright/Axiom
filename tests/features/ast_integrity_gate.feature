Feature: AST Integrity Gate
  As an Axiom operator
  I want cast expressions and raw pointers to be detected at gate time
  So that unsafe memory patterns are blocked before merge

  Scenario: cast expression in source triggers failure
    Given a .nim file containing `cast[ptr Foo](x)`
    When the AST integrity gate scans the file
    Then the gate fails with a cast detection error

  Scenario: ptr type in core layer triggers failure
    Given a .nim file in src/core/ containing `ptr int`
    When the AST integrity gate scans the file
    Then the gate fails with a pointer detection error

  Scenario: Clean source passes the gate
    Given a .nim file with no cast or pointer usage
    When the AST integrity gate scans the file
    Then the gate passes
