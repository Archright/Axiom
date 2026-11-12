@generated @high
Feature: lean_lsp_proof_search
  # generated | src/verification/lean_lsp_proof_search.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/lean_lsp_proof_search" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/lean_lsp_proof_search" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
