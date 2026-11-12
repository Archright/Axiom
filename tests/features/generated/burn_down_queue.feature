@generated @critical
Feature: burn_down_queue
  # generated | src/core/audit/burn_down_queue.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/audit/burn_down_queue" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types HotspotTier
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/audit/burn_down_queue" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs findTestFile, computeSadScore, computeRiskMultiplier, computeTier, isHotspot, findHotspotEntry
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type HotspotTier is instantiable
    Given the module "core/audit/burn_down_queue" is loaded
    Then type HotspotTier should be instantiable

  Scenario: func findTestFile is callable
    Given the module "core/audit/burn_down_queue" is loaded
    Then func findTestFile should return a valid value

  Scenario: func computeSadScore is callable
    Given the module "core/audit/burn_down_queue" is loaded
    Then func computeSadScore should return a valid value

  Scenario: func computeRiskMultiplier is callable
    Given the module "core/audit/burn_down_queue" is loaded
    Then func computeRiskMultiplier should return a valid value

  Scenario: func computeTier is callable
    Given the module "core/audit/burn_down_queue" is loaded
    Then func computeTier should return a valid value

  Scenario: func isHotspot is callable
    Given the module "core/audit/burn_down_queue" is loaded
    Then func isHotspot should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
