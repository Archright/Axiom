@generated @critical
Feature: integrity_refinement_loop
  # generated | src/core/integrity/integrity_refinement_loop.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/integrity/integrity_refinement_loop" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/integrity/integrity_refinement_loop" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs upsertInvariant, minimizeRegistryByUnsatCore, runDeterministicZ3
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func upsertInvariant is callable
    Given the module "core/integrity/integrity_refinement_loop" is loaded
    Then func upsertInvariant should return a valid value

  Scenario: func minimizeRegistryByUnsatCore is callable
    Given the module "core/integrity/integrity_refinement_loop" is loaded
    Then func minimizeRegistryByUnsatCore should return a valid value

  Scenario: func runDeterministicZ3 is callable
    Given the module "core/integrity/integrity_refinement_loop" is loaded
    Then func runDeterministicZ3 should return a valid value
