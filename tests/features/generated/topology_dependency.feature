@generated @critical
Feature: topology_dependency
  # generated | src/core/topology/topology_dependency.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/topology_dependency" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/topology_dependency" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs computeDependents, verifyEngineQuiescence, sortMetricIndices, sortByCoupling, sortByRepairPriority
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func computeDependents is callable
    Given the module "core/topology/topology_dependency" is loaded
    Then func computeDependents should return a valid value

  Scenario: func verifyEngineQuiescence is callable
    Given the module "core/topology/topology_dependency" is loaded
    Then func verifyEngineQuiescence should return a valid value

  Scenario: func sortMetricIndices is callable
    Given the module "core/topology/topology_dependency" is loaded
    Then func sortMetricIndices should return a valid value

  Scenario: func sortByCoupling is callable
    Given the module "core/topology/topology_dependency" is loaded
    Then func sortByCoupling should return a valid value

  Scenario: func sortByRepairPriority is callable
    Given the module "core/topology/topology_dependency" is loaded
    Then func sortByRepairPriority should return a valid value
