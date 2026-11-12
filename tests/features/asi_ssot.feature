@legacy
Feature: ASI SSOT — Calculated-Property Architecture
  Eliminates ASI discrepancy between TUI and CLI by enforcing single
  source of truth (SSOT) via src/core/metrics.nim.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And metrics module exists at "src/core/metrics.nim"

  @deprecated
  Scenario: TUI and CLI produce identical ASI values
    Given certificate vault is unchanged between runs
    When "ax report" is executed (TUI)
    And "ax report --calculate-asi" is executed (CLI)
    Then both report the same asiFixed4 value

  Scenario: Coverage calculation uses SSOT denominator
    Given AsiUniverse is populated with totalFunctions = 100
    When computeCoverage(50, universe) is called
    Then the result is exactly 0.5

  Scenario: ASI cannot exceed 1.0
    Given verifiedFunctions = 200 and totalFunctions = 100
    When computeInformationGainWeightedAsi is called
    Then the result is exactly 1.0

  Scenario: Zero-functions universe returns ASI 0.0
    Given AsiUniverse totalFunctions = 0
    When computeInformationGainWeightedAsi(any, universe, any) is called
    Then the result is 0.0

  Scenario: No ad-hoc ASI math remains in CLI layer
    Given asi_cli.nim imports metrics
    When ASI is computed in asi_cli.nim
    Then it delegates to metrics.computeCoverage and metrics.computeRetryPenalty
    And no inline division by totalTrustedFunctions exists
