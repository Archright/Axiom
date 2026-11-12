@generated @critical
Feature: verification_context
  # generated | src/core/application/verification_context.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/application/verification_context" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types VerificationContext, runLayer1Bmc, runSwatStage, runKInductionStage, z3CheckViaProcess, runCegarLoop, proveWithFixedpoint, encodeProvedInvariantsSmtlib2, analyzeVariableIntervalsAtLoopHeader, detectInductionVariables, deriveInvariantCandidates, extractLoopConditionFromHeader
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/application/verification_context" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs validate
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type VerificationContext is instantiable
    Given the module "core/application/verification_context" is loaded
    Then type VerificationContext should be instantiable

  Scenario: type runLayer1Bmc is instantiable
    Given the module "core/application/verification_context" is loaded
    Then type runLayer1Bmc should be instantiable

  Scenario: type runSwatStage is instantiable
    Given the module "core/application/verification_context" is loaded
    Then type runSwatStage should be instantiable

  Scenario: type runKInductionStage is instantiable
    Given the module "core/application/verification_context" is loaded
    Then type runKInductionStage should be instantiable

  Scenario: type z3CheckViaProcess is instantiable
    Given the module "core/application/verification_context" is loaded
    Then type z3CheckViaProcess should be instantiable

  Scenario: type runCegarLoop is instantiable
    Given the module "core/application/verification_context" is loaded
    Then type runCegarLoop should be instantiable

  # +7 more scenarios (types+funcs) omitted to stay under 50 lines
