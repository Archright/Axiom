Feature: Layer Guard — enforces L1→L0 gate layer boundary
  As the Axiom gate architecture,
  I want a guard preventing L1 modules from calling L0 internals,
  So that layer boundaries are not violated.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: allowed L0→L1 dependency passes the guard
    Given an L0 module importing an L1 public API
    When I run the layer guard check
    Then the check passes

  Scenario: forbidden L1→L0 dependency fails the guard
    Given an L1 module importing an L0 internal symbol
    When I run the layer guard check
    Then the check fails with a layer-boundary violation
