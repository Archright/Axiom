@generated @critical
Feature: hotspot_gate
  # generated | src/core/audit/hotspot_gate.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/audit/hotspot_gate" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types HotspotGateResult
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/audit/hotspot_gate" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs formatHotspotContext
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type HotspotGateResult is instantiable
    Given the module "core/audit/hotspot_gate" is loaded
    Then type HotspotGateResult should be instantiable

  Scenario: func formatHotspotContext is callable
    Given the module "core/audit/hotspot_gate" is loaded
    Then func formatHotspotContext should return a valid value
