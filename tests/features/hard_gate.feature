@legacy
@executable
Feature: Hard Gate — Anti-Tautology Topology Filter
  As an Axiom architect
  I want trivial nodes (e.g. string-length >= 0) to be physically excluded from verificationQueue
  So that no solver time is wasted on tautological proofs

  Background:
    Given the Axiom engine is initialized

  Scenario: Trivial string-length function is marked TrivialDiscard
    When a function with body "s.len" is scanned
    Then its boundaryKind should be topologyBoundaryTrivialDiscard

  Scenario: Meaningful branching function is NOT marked TrivialDiscard
    When a function with branches and non-trivial conditions is scanned
    Then its boundaryKind should NOT be topologyBoundaryTrivialDiscard

  Scenario: VerificationQueue excludes TrivialDiscard nodes
    Given a module contains both trivial and meaningful functions
    When topology analysis builds the verificationQueue
    Then trivial functions should not appear in verificationQueue
    And meaningful functions should appear in verificationQueue

  Scenario: Trivial rejection is recorded in trivial_vault.jsonl
    When a trivial function is processed by boundary_extractor
    Then logs/trivial_vault.jsonl should contain its nodeId
    And the rejection reason should explain why it is trivial
