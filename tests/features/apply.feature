Feature: Topology Apply — applies computed topology to the verification pipeline
  As the Axiom topology subsystem,
  I want an apply function that wires topology nodes into the pipeline,
  So that the verification graph is instantiated correctly.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: apply wires nodes and edges into the pipeline
    Given a topology with nodes [A, B] and edge A→B
    When I apply the topology to the pipeline
    Then the pipeline contains node A, node B, and edge A→B

  Scenario: apply rejects a topology with cycles
    Given a topology with cycle A→B→A
    When I apply the topology to the pipeline
    Then a cycle-detected error is returned
