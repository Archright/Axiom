@generated @high
Feature: loop_invariant_synthesis
  # generated | src/verification/loop_invariant_synthesis.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/loop_invariant_synthesis" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/loop_invariant_synthesis" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
