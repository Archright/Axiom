@generated @critical
Feature: hotspot_render
  # generated | src/core/audit/hotspot_render.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/audit/hotspot_render" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ReportFormat
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/audit/hotspot_render" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs tierEmoji, tierLabel, renderMarkdown, renderJson, renderTTY
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ReportFormat is instantiable
    Given the module "core/audit/hotspot_render" is loaded
    Then type ReportFormat should be instantiable

  Scenario: func tierEmoji is callable
    Given the module "core/audit/hotspot_render" is loaded
    Then func tierEmoji should return a valid value

  Scenario: func tierLabel is callable
    Given the module "core/audit/hotspot_render" is loaded
    Then func tierLabel should return a valid value

  Scenario: func renderMarkdown is callable
    Given the module "core/audit/hotspot_render" is loaded
    Then func renderMarkdown should return a valid value

  Scenario: func renderJson is callable
    Given the module "core/audit/hotspot_render" is loaded
    Then func renderJson should return a valid value

  Scenario: func renderTTY is callable
    Given the module "core/audit/hotspot_render" is loaded
    Then func renderTTY should return a valid value
