@generated @critical
Feature: lean_util
  # generated | src/core/trusted/lean_util.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/trusted/lean_util" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/trusted/lean_util" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs verificationEngineString, sanitizeLeanIdentifier, buildLeanStringLiteral, buildLeanStringList, minimizeProofPath, minimizeProofTactic
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func verificationEngineString is callable
    Given the module "core/trusted/lean_util" is loaded
    Then func verificationEngineString should return a valid value

  Scenario: func sanitizeLeanIdentifier is callable
    Given the module "core/trusted/lean_util" is loaded
    Then func sanitizeLeanIdentifier should return a valid value

  Scenario: func buildLeanStringLiteral is callable
    Given the module "core/trusted/lean_util" is loaded
    Then func buildLeanStringLiteral should return a valid value

  Scenario: func buildLeanStringList is callable
    Given the module "core/trusted/lean_util" is loaded
    Then func buildLeanStringList should return a valid value

  Scenario: func minimizeProofPath is callable
    Given the module "core/trusted/lean_util" is loaded
    Then func minimizeProofPath should return a valid value

  Scenario: func minimizeProofTactic is callable
    Given the module "core/trusted/lean_util" is loaded
    Then func minimizeProofTactic should return a valid value
