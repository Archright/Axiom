Feature: Topology Policy — rules governing valid topology configurations
  As the Axiom topology subsystem,
  I want a policy engine that validates topology constraints,
  So that only structurally sound graphs are accepted.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: policy accepts a DAG with a single root
    Given a topology with one root node and no cycles
    When I validate the topology against the policy
    Then the policy accepts the topology

  Scenario: policy rejects a topology with multiple roots
    Given a topology with two independent root nodes
    When I validate the topology against the policy
    Then the policy rejects the topology with a multiple-roots error
