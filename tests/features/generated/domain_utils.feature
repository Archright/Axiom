@generated @critical
Feature: domain_utils
  # generated | src/core/types/domain_utils.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/domain_utils" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/domain_utils" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs axiomErrorMessage, parseCertStatus, isCertificateVerified, isFormalProofStatus, isVerifiedAxiomStatus, isPseudoVerifiedStatus, isYellowStatus, qualifiedName
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func axiomErrorMessage is callable
    Given the module "core/types/domain_utils" is loaded
    Then func axiomErrorMessage should return a valid value

  Scenario: func parseCertStatus is callable
    Given the module "core/types/domain_utils" is loaded
    Then func parseCertStatus should return a valid value

  Scenario: func isCertificateVerified is callable
    Given the module "core/types/domain_utils" is loaded
    Then func isCertificateVerified should return a valid value

  Scenario: func isFormalProofStatus is callable
    Given the module "core/types/domain_utils" is loaded
    Then func isFormalProofStatus should return a valid value

  Scenario: func isVerifiedAxiomStatus is callable
    Given the module "core/types/domain_utils" is loaded
    Then func isVerifiedAxiomStatus should return a valid value

  Scenario: func isPseudoVerifiedStatus is callable
    Given the module "core/types/domain_utils" is loaded
    Then func isPseudoVerifiedStatus should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
