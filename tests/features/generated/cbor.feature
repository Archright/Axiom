@generated @critical
Feature: cbor
  # generated | src/core/trusted/cbor.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/trusted/cbor" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types CborProofEnvelope, path, certificateHash, timestamp
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/trusted/cbor" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs envelopeHash, encodeCbor, decodeCbor
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type CborProofEnvelope is instantiable
    Given the module "core/trusted/cbor" is loaded
    Then type CborProofEnvelope should be instantiable

  Scenario: type path is instantiable
    Given the module "core/trusted/cbor" is loaded
    Then type path should be instantiable

  Scenario: type certificateHash is instantiable
    Given the module "core/trusted/cbor" is loaded
    Then type certificateHash should be instantiable

  Scenario: type timestamp is instantiable
    Given the module "core/trusted/cbor" is loaded
    Then type timestamp should be instantiable

  Scenario: func envelopeHash is callable
    Given the module "core/trusted/cbor" is loaded
    Then func envelopeHash should return a valid value

  Scenario: func encodeCbor is callable
    Given the module "core/trusted/cbor" is loaded
    Then func encodeCbor should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
