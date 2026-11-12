@generated @critical
Feature: coverage_bridge
  # generated | src/core/coverage/coverage_bridge.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/coverage/coverage_bridge" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ModuleMetrics, hotspotDepth, astNodeCount, inDegree
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/coverage/coverage_bridge" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs cubeRoot, calculatePriority, computeDensity, isHotspot
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ModuleMetrics is instantiable
    Given the module "core/coverage/coverage_bridge" is loaded
    Then type ModuleMetrics should be instantiable

  Scenario: type hotspotDepth is instantiable
    Given the module "core/coverage/coverage_bridge" is loaded
    Then type hotspotDepth should be instantiable

  Scenario: type astNodeCount is instantiable
    Given the module "core/coverage/coverage_bridge" is loaded
    Then type astNodeCount should be instantiable

  Scenario: type inDegree is instantiable
    Given the module "core/coverage/coverage_bridge" is loaded
    Then type inDegree should be instantiable

  Scenario: func cubeRoot is callable
    Given the module "core/coverage/coverage_bridge" is loaded
    Then func cubeRoot should return a valid value

  Scenario: func calculatePriority is callable
    Given the module "core/coverage/coverage_bridge" is loaded
    Then func calculatePriority should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
