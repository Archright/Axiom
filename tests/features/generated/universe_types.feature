@generated @critical
Feature: universe_types
  # generated | src/core/types/universe_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/universe_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ProofUniverseLock, merkleRoot, timestamp, fileCount, asiFixed4
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/universe_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ProofUniverseLock is instantiable
    Given the module "core/types/universe_types" is loaded
    Then type ProofUniverseLock should be instantiable

  Scenario: type merkleRoot is instantiable
    Given the module "core/types/universe_types" is loaded
    Then type merkleRoot should be instantiable

  Scenario: type timestamp is instantiable
    Given the module "core/types/universe_types" is loaded
    Then type timestamp should be instantiable

  Scenario: type fileCount is instantiable
    Given the module "core/types/universe_types" is loaded
    Then type fileCount should be instantiable

  Scenario: type asiFixed4 is instantiable
    Given the module "core/types/universe_types" is loaded
    Then type asiFixed4 should be instantiable
