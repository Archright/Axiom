@generated @critical
Feature: axiom_api_session_helpers
  # generated | src/core/api/axiom_api_session_helpers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/api/axiom_api_session_helpers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/api/axiom_api_session_helpers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs proofArtifactToJsonNode, proofEnvelopeJson, parseProofArtifactNode, parseStoredProofResponse, jsonFromNimLeanBridge
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func proofArtifactToJsonNode is callable
    Given the module "core/api/axiom_api_session_helpers" is loaded
    Then func proofArtifactToJsonNode should return a valid value

  Scenario: func proofEnvelopeJson is callable
    Given the module "core/api/axiom_api_session_helpers" is loaded
    Then func proofEnvelopeJson should return a valid value

  Scenario: func parseProofArtifactNode is callable
    Given the module "core/api/axiom_api_session_helpers" is loaded
    Then func parseProofArtifactNode should return a valid value

  Scenario: func parseStoredProofResponse is callable
    Given the module "core/api/axiom_api_session_helpers" is loaded
    Then func parseStoredProofResponse should return a valid value

  Scenario: func jsonFromNimLeanBridge is callable
    Given the module "core/api/axiom_api_session_helpers" is loaded
    Then func jsonFromNimLeanBridge should return a valid value
