@generated @high
Feature: proof_linkage
  # generated | src/verification/proof_linkage.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/proof_linkage" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/proof_linkage" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func computeLeanHash is callable
    Given the module "verification/proof_linkage" is loaded
    Then func computeLeanHash should return a valid value

  Scenario: func verifyProofLinkage is callable
    Given the module "verification/proof_linkage" is loaded
    Then func verifyProofLinkage should return a valid value

  Scenario: func verifyAxiomLinkage is callable
    Given the module "verification/proof_linkage" is loaded
    Then func verifyAxiomLinkage should return a valid value
