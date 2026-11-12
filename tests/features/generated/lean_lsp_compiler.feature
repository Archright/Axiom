@generated @high
Feature: lean_lsp_compiler
  # generated | src/verification/lean_lsp_compiler.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/lean_lsp_compiler" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/lean_lsp_compiler" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func buildNegativeTestSource is callable
    Given the module "verification/lean_lsp_compiler" is loaded
    Then func buildNegativeTestSource should return a valid value

  Scenario: func applyLeanCompilerFeedback*[T] is callable
    Given the module "verification/lean_lsp_compiler" is loaded
    Then func applyLeanCompilerFeedback*[T] should return a valid value
