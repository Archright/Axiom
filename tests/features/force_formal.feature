@manual
Feature: Force-Formal Shadow Verification
  --force-formal requires Formal Sketching proof even after intrinsic certification.
  Deprecated: --force-formal flag has been removed from ax prove.

  Scenario: --force-formal triggers Formal Sketching for all nodes
    Given ax prove --heal --force-formal is executed
    Then every intrinsic-certified node also attempts Formal Sketching
    And [Parallel-First] appears for all passed nodes

  Scenario: SMT pre-check marks trivial propositions
    Given isTrivialViaZ3 is called with "x >= 0"
    When Z3 returns unsat on negated proposition
    Then the proposition is classified as trivial
