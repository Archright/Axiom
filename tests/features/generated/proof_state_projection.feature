@generated @high
Feature: proof_state_projection
  # generated | src/verification/proof_state_projection.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/proof_state_projection" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types CertificateProjection, path, label, modulePath, functionName, status, node
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/proof_state_projection" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type CertificateProjection is instantiable
    Given the module "verification/proof_state_projection" is loaded
    Then type CertificateProjection should be instantiable

  Scenario: type path is instantiable
    Given the module "verification/proof_state_projection" is loaded
    Then type path should be instantiable

  Scenario: type label is instantiable
    Given the module "verification/proof_state_projection" is loaded
    Then type label should be instantiable

  Scenario: type modulePath is instantiable
    Given the module "verification/proof_state_projection" is loaded
    Then type modulePath should be instantiable

  Scenario: type functionName is instantiable
    Given the module "verification/proof_state_projection" is loaded
    Then type functionName should be instantiable

  Scenario: type status is instantiable
    Given the module "verification/proof_state_projection" is loaded
    Then type status should be instantiable

  # +8 more scenarios (types+funcs) omitted to stay under 50 lines
