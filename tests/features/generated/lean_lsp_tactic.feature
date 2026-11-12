@generated @high
Feature: lean_lsp_tactic
  # generated | src/verification/lean_lsp_tactic.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/lean_lsp_tactic" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/lean_lsp_tactic" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func theoremSource is callable
    Given the module "verification/lean_lsp_tactic" is loaded
    Then func theoremSource should return a valid value

  Scenario: func appendGeneratedCoreSpec is callable
    Given the module "verification/lean_lsp_tactic" is loaded
    Then func appendGeneratedCoreSpec should return a valid value

  Scenario: func writeGeneratedSpecArtifact is callable
    Given the module "verification/lean_lsp_tactic" is loaded
    Then func writeGeneratedSpecArtifact should return a valid value

  Scenario: func loadWarmStartTactics is callable
    Given the module "verification/lean_lsp_tactic" is loaded
    Then func loadWarmStartTactics should return a valid value

  Scenario: func lineOfTactic is callable
    Given the module "verification/lean_lsp_tactic" is loaded
    Then func lineOfTactic should return a valid value
