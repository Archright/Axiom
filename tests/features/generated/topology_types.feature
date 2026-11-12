@generated @critical
Feature: topology_types
  # generated | src/core/topology/topology_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/topology_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types TopologyBoundaryKind, TopologyScopeKind, TopologyOperationKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/topology_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs topologyExtractFilename, topologyParentDir
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type TopologyBoundaryKind is instantiable
    Given the module "core/topology/topology_types" is loaded
    Then type TopologyBoundaryKind should be instantiable

  Scenario: type TopologyScopeKind is instantiable
    Given the module "core/topology/topology_types" is loaded
    Then type TopologyScopeKind should be instantiable

  Scenario: type TopologyOperationKind is instantiable
    Given the module "core/topology/topology_types" is loaded
    Then type TopologyOperationKind should be instantiable

  Scenario: func topologyExtractFilename is callable
    Given the module "core/topology/topology_types" is loaded
    Then func topologyExtractFilename should return a valid value

  Scenario: func topologyParentDir is callable
    Given the module "core/topology/topology_types" is loaded
    Then func topologyParentDir should return a valid value
