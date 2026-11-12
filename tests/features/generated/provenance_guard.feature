@generated @critical
Feature: provenance_guard
  # generated | src/core/trusted/provenance_guard.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/trusted/provenance_guard" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/trusted/provenance_guard" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs evidenceFileName, isCorruptedEvidence, preFlightLeanCheck, isHighQualityEvidence, detectProvenanceFromContent, isProvenanceProtected, enforceProvenanceBeforeWrite, recordProvenanceOverwriteAttempt
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func evidenceFileName is callable
    Given the module "core/trusted/provenance_guard" is loaded
    Then func evidenceFileName should return a valid value

  Scenario: func isCorruptedEvidence is callable
    Given the module "core/trusted/provenance_guard" is loaded
    Then func isCorruptedEvidence should return a valid value

  Scenario: func preFlightLeanCheck is callable
    Given the module "core/trusted/provenance_guard" is loaded
    Then func preFlightLeanCheck should return a valid value

  Scenario: func isHighQualityEvidence is callable
    Given the module "core/trusted/provenance_guard" is loaded
    Then func isHighQualityEvidence should return a valid value

  Scenario: func detectProvenanceFromContent is callable
    Given the module "core/trusted/provenance_guard" is loaded
    Then func detectProvenanceFromContent should return a valid value

  Scenario: func isProvenanceProtected is callable
    Given the module "core/trusted/provenance_guard" is loaded
    Then func isProvenanceProtected should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
