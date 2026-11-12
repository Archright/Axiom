@generated @high
Feature: call_graph
  # generated | src/gate/nimtry/call_graph.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/call_graph" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types CallGraph, edges, callerModule, calleeModule
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/call_graph" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type CallGraph is instantiable
    Given the module "gate/nimtry/call_graph" is loaded
    Then type CallGraph should be instantiable

  Scenario: type edges is instantiable
    Given the module "gate/nimtry/call_graph" is loaded
    Then type edges should be instantiable

  Scenario: type callerModule is instantiable
    Given the module "gate/nimtry/call_graph" is loaded
    Then type callerModule should be instantiable

  Scenario: type calleeModule is instantiable
    Given the module "gate/nimtry/call_graph" is loaded
    Then type calleeModule should be instantiable

  Scenario: func buildCallGraph is callable
    Given the module "gate/nimtry/call_graph" is loaded
    Then func buildCallGraph should return a valid value

  Scenario: func resolveCalleeModules is callable
    Given the module "gate/nimtry/call_graph" is loaded
    Then func resolveCalleeModules should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
