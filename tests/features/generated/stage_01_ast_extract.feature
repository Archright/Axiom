@generated @high
Feature: stage_01_ast_extract
  # generated | src/verification/analyzer/stage_01_ast_extract.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/analyzer/stage_01_ast_extract" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/analyzer/stage_01_ast_extract" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
