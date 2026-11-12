@generated @critical
Feature: cfg_builder
  # generated | src/core/orchestrator/cfg_builder.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/orchestrator/cfg_builder" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/orchestrator/cfg_builder" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs buildCfgFromAst, findLoopHeaders, findBackEdges, buildControlFlowGraph, findPrimaryLoopHeader
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func buildCfgFromAst is callable
    Given the module "core/orchestrator/cfg_builder" is loaded
    Then func buildCfgFromAst should return a valid value

  Scenario: func findLoopHeaders is callable
    Given the module "core/orchestrator/cfg_builder" is loaded
    Then func findLoopHeaders should return a valid value

  Scenario: func findBackEdges is callable
    Given the module "core/orchestrator/cfg_builder" is loaded
    Then func findBackEdges should return a valid value

  Scenario: func buildControlFlowGraph is callable
    Given the module "core/orchestrator/cfg_builder" is loaded
    Then func buildControlFlowGraph should return a valid value

  Scenario: func findPrimaryLoopHeader is callable
    Given the module "core/orchestrator/cfg_builder" is loaded
    Then func findPrimaryLoopHeader should return a valid value
