@generated @high
Feature: agent_preflight
  # generated | src/gate/runners/agent_preflight.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/runners/agent_preflight" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types PreflightResult, safe, reason
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/runners/agent_preflight" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type PreflightResult is instantiable
    Given the module "gate/runners/agent_preflight" is loaded
    Then type PreflightResult should be instantiable

  Scenario: type safe is instantiable
    Given the module "gate/runners/agent_preflight" is loaded
    Then type safe should be instantiable

  Scenario: type reason is instantiable
    Given the module "gate/runners/agent_preflight" is loaded
    Then type reason should be instantiable

  Scenario: func checkInfraFileOverlap is callable
    Given the module "gate/runners/agent_preflight" is loaded
    Then func checkInfraFileOverlap should return a valid value
