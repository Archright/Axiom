@generated @critical
Feature: sorter_core_algo
  # generated | src/core/sorter/sorter_core_algo.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/sorter/sorter_core_algo" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/sorter/sorter_core_algo" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs buildSorterPlan, verifyWorkflowLabelFromNode, verifyWorkflowLabelFromNodeId
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func buildSorterPlan is callable
    Given the module "core/sorter/sorter_core_algo" is loaded
    Then func buildSorterPlan should return a valid value

  Scenario: func verifyWorkflowLabelFromNode is callable
    Given the module "core/sorter/sorter_core_algo" is loaded
    Then func verifyWorkflowLabelFromNode should return a valid value

  Scenario: func verifyWorkflowLabelFromNodeId is callable
    Given the module "core/sorter/sorter_core_algo" is loaded
    Then func verifyWorkflowLabelFromNodeId should return a valid value
