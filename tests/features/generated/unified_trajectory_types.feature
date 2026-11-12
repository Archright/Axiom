@generated @high
Feature: unified_trajectory_types
  # generated | src/verification/unified_trajectory_types.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/unified_trajectory_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types StageKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/unified_trajectory_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type StageKind is instantiable
    Given the module "verification/unified_trajectory_types" is loaded
    Then type StageKind should be instantiable
