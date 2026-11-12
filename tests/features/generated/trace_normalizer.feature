@generated @critical
Feature: trace_normalizer
  # generated | src/core/telemetry/trace_normalizer.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/telemetry/trace_normalizer" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types RawTrace, NormalizedTrace
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/telemetry/trace_normalizer" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs normalizeTrace, `$`
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type RawTrace is instantiable
    Given the module "core/telemetry/trace_normalizer" is loaded
    Then type RawTrace should be instantiable

  Scenario: type NormalizedTrace is instantiable
    Given the module "core/telemetry/trace_normalizer" is loaded
    Then type NormalizedTrace should be instantiable

  Scenario: func normalizeTrace is callable
    Given the module "core/telemetry/trace_normalizer" is loaded
    Then func normalizeTrace should return a valid value

  Scenario: func `$` is callable
    Given the module "core/telemetry/trace_normalizer" is loaded
    Then func `$` should return a valid value
