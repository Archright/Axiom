@generated @critical
Feature: semantic_theorem_builder
  # generated | src/core/logic/semantic_theorem_builder.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/logic/semantic_theorem_builder" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/logic/semantic_theorem_builder" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs buildSemanticCandidateInvariantHints, isSemanticReplayTacticCompatible, semanticProofTacticLine
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func buildSemanticCandidateInvariantHints is callable
    Given the module "core/logic/semantic_theorem_builder" is loaded
    Then func buildSemanticCandidateInvariantHints should return a valid value

  Scenario: func isSemanticReplayTacticCompatible is callable
    Given the module "core/logic/semantic_theorem_builder" is loaded
    Then func isSemanticReplayTacticCompatible should return a valid value

  Scenario: func semanticProofTacticLine is callable
    Given the module "core/logic/semantic_theorem_builder" is loaded
    Then func semanticProofTacticLine should return a valid value
