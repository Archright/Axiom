@generated @critical
Feature: axiom_identity
  # generated | src/core/identity/axiom_identity.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/identity/axiom_identity" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/identity/axiom_identity" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs normalizePayloadForFingerprint, hashNormalizedPayload, computeAxiomFingerprint, computeAxiomFingerprintCandidates
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func normalizePayloadForFingerprint is callable
    Given the module "core/identity/axiom_identity" is loaded
    Then func normalizePayloadForFingerprint should return a valid value

  Scenario: func hashNormalizedPayload is callable
    Given the module "core/identity/axiom_identity" is loaded
    Then func hashNormalizedPayload should return a valid value

  Scenario: func computeAxiomFingerprint is callable
    Given the module "core/identity/axiom_identity" is loaded
    Then func computeAxiomFingerprint should return a valid value

  Scenario: func computeAxiomFingerprintCandidates is callable
    Given the module "core/identity/axiom_identity" is loaded
    Then func computeAxiomFingerprintCandidates should return a valid value
