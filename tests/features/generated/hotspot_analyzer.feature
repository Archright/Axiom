@generated @critical
Feature: hotspot_analyzer
  # generated | src/core/audit/hotspot_analyzer.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/audit/hotspot_analyzer" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ChurnPeriod
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/audit/hotspot_analyzer" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs periodDays, runGitLog, parseChurnScores, computeChurnScores, moduleNameFromPath, sortedChurnByScore
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ChurnPeriod is instantiable
    Given the module "core/audit/hotspot_analyzer" is loaded
    Then type ChurnPeriod should be instantiable

  Scenario: func periodDays is callable
    Given the module "core/audit/hotspot_analyzer" is loaded
    Then func periodDays should return a valid value

  Scenario: func runGitLog is callable
    Given the module "core/audit/hotspot_analyzer" is loaded
    Then func runGitLog should return a valid value

  Scenario: func parseChurnScores is callable
    Given the module "core/audit/hotspot_analyzer" is loaded
    Then func parseChurnScores should return a valid value

  Scenario: func computeChurnScores is callable
    Given the module "core/audit/hotspot_analyzer" is loaded
    Then func computeChurnScores should return a valid value

  Scenario: func moduleNameFromPath is callable
    Given the module "core/audit/hotspot_analyzer" is loaded
    Then func moduleNameFromPath should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
