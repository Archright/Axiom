@legacy
Feature: Axiom-IR Constraint Inference
  BoundaryExtractor extracts additional constraints from tree-sitter IR
  for bcPartialHavoc cases (if-conditions, for-loop ranges).

  Background:
    Given boundary_extractor.nim has inferConstraintsFromIrNode
    And tree_sitter_bridge is available

  Scenario: If-condition produces numeric bound
    Given source "proc foo(x: int) = if x > 0: discard"
    When extractBoundaries is called
    And result.completeness is bcPartialHavoc
    Then smtParts contains "(>= x 0)"
    And leanParts contains "x >= 0"

  Scenario: For-loop range produces bounds
    Given source "proc foo() = for i in 0..10: discard"
    When inferConstraintsFromIrNode is called
    Then result contains "(>= i 0)"
    And result contains "(<= i 10)"

  Scenario: Simple function without conditions produces no IR constraints
    Given source "proc foo(x: int) = discard"
    When inferConstraintsFromIrNode is called
    Then result is empty sequence
