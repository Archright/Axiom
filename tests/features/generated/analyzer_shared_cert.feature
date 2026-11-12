@generated @high
Feature: analyzer_shared_cert
  # generated | src/verification/analyzer/analyzer_shared_cert.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/analyzer/analyzer_shared_cert" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/analyzer/analyzer_shared_cert" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func resolveSourcePath is callable
    Given the module "verification/analyzer/analyzer_shared_cert" is loaded
    Then func resolveSourcePath should return a valid value

  Scenario: func buildLastNDaysUtc is callable
    Given the module "verification/analyzer/analyzer_shared_cert" is loaded
    Then func buildLastNDaysUtc should return a valid value

  Scenario: func parseDayFromTimestamp is callable
    Given the module "verification/analyzer/analyzer_shared_cert" is loaded
    Then func parseDayFromTimestamp should return a valid value

  Scenario: func parseJsonSafe is callable
    Given the module "verification/analyzer/analyzer_shared_cert" is loaded
    Then func parseJsonSafe should return a valid value

  Scenario: func computeCumulativeDefectsHealed is callable
    Given the module "verification/analyzer/analyzer_shared_cert" is loaded
    Then func computeCumulativeDefectsHealed should return a valid value

  Scenario: func computeAverageRetryCount is callable
    Given the module "verification/analyzer/analyzer_shared_cert" is loaded
    Then func computeAverageRetryCount should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
