Feature: Sorter Node ID — unique deterministic identifiers for pipeline sorter nodes
  As the Axiom verification pipeline,
  I want each sorter node to have a stable unique ID,
  So that pipeline topology is reproducible across runs.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: two nodes with different content have different IDs
    Given sorter node A with content "foo" and node B with content "bar"
    When I generate IDs for both nodes
    Then the IDs are distinct

  Scenario: same content always produces the same node ID
    Given two sorter nodes with identical content "baz"
    When I generate IDs for both nodes
    Then the IDs are equal
