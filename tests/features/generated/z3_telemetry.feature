@generated @critical
Feature: z3_telemetry
  # generated | src/core/solver/z3_telemetry.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/solver/z3_telemetry" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Z3TelemetryRecord, ts, queryType, rlimit, result, timeMs, memoryMb, cegarIters
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/solver/z3_telemetry" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs appendZ3Telemetry
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type Z3TelemetryRecord is instantiable
    Given the module "core/solver/z3_telemetry" is loaded
    Then type Z3TelemetryRecord should be instantiable

  Scenario: type ts is instantiable
    Given the module "core/solver/z3_telemetry" is loaded
    Then type ts should be instantiable

  Scenario: type queryType is instantiable
    Given the module "core/solver/z3_telemetry" is loaded
    Then type queryType should be instantiable

  Scenario: type rlimit is instantiable
    Given the module "core/solver/z3_telemetry" is loaded
    Then type rlimit should be instantiable

  Scenario: type result is instantiable
    Given the module "core/solver/z3_telemetry" is loaded
    Then type result should be instantiable

  Scenario: type timeMs is instantiable
    Given the module "core/solver/z3_telemetry" is loaded
    Then type timeMs should be instantiable

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
