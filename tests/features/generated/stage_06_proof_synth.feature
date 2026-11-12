@generated @high
Feature: stage_06_proof_synth
  # generated | src/verification/analyzer/stage_06_proof_synth.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/analyzer/stage_06_proof_synth" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/analyzer/stage_06_proof_synth" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
