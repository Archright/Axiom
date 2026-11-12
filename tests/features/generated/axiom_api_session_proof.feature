@generated @critical
Feature: axiom_api_session_proof
  # generated | src/core/api/axiom_api_session_proof.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/api/axiom_api_session_proof" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/api/axiom_api_session_proof" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs parseAxiomSessionJson, captureSession, generateProofFromSessionId, generateProofFromSession
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func parseAxiomSessionJson is callable
    Given the module "core/api/axiom_api_session_proof" is loaded
    Then func parseAxiomSessionJson should return a valid value

  Scenario: func captureSession is callable
    Given the module "core/api/axiom_api_session_proof" is loaded
    Then func captureSession should return a valid value

  Scenario: func generateProofFromSessionId is callable
    Given the module "core/api/axiom_api_session_proof" is loaded
    Then func generateProofFromSessionId should return a valid value

  Scenario: func generateProofFromSession is callable
    Given the module "core/api/axiom_api_session_proof" is loaded
    Then func generateProofFromSession should return a valid value
