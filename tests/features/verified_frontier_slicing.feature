@verification
Feature: Verified Bitset Masking Frontier Slicing
  As an Axiom engineer
  I want the verification frontier to contain only ready, unverified nodes
  So that each prove batch maximizes verifiable work without dependency padding

  Background:
    Given the topology analysis has four dependent nodes A, B, C, D
    And the dependency graph is A <- B <- D and A <- C

  Scenario: Unlimited frontier selects only ready leaf nodes
    When no nodes are verified
    And the frontier is computed with limit 0
    Then the frontier should contain node A
    And the frontier should not contain nodes B, C, or D
    And every selected node's dependencies should be satisfied

  Scenario: Verified nodes are masked out of the frontier
    Given node A is already verified
    When the frontier is computed with limit 0
    Then the frontier should not contain node A
    And nodes B and C should be selected
    And every selected node's dependencies should be satisfied

  Scenario: Dependent nodes become selectable only after prerequisites are verified
    Given nodes A and B are already verified
    When the frontier is computed with limit 0
    Then node D should be selected
    And every selected node's dependencies should be satisfied

  Scenario: Frontier respects the requested batch size
    Given node A is already verified
    When the frontier is computed with limit 1
    Then the frontier should contain exactly 1 node
    And every selected node's dependencies should be satisfied
