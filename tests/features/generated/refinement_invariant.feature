@generated @critical
Feature: refinement_invariant
  # generated | src/core/logic/refinement_invariant.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/logic/refinement_invariant" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/logic/refinement_invariant" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs makeStackDisciplineInvariant, makeTopValidityInvariant, makeBoundedGrowthInvariant, relaxedInvariantFor, initTrackedInvariant, findInvariantIndex, findInvariant, hasSuspiciousInvariants, targetTag, invariantMaxSize, underflowWitnessSize, nextPowerOfTwo, boundWitnessSize
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func makeStackDisciplineInvariant is callable
    Given the module "core/logic/refinement_invariant" is loaded
    Then func makeStackDisciplineInvariant should return a valid value

  Scenario: func makeTopValidityInvariant is callable
    Given the module "core/logic/refinement_invariant" is loaded
    Then func makeTopValidityInvariant should return a valid value

  Scenario: func makeBoundedGrowthInvariant is callable
    Given the module "core/logic/refinement_invariant" is loaded
    Then func makeBoundedGrowthInvariant should return a valid value

  Scenario: func relaxedInvariantFor is callable
    Given the module "core/logic/refinement_invariant" is loaded
    Then func relaxedInvariantFor should return a valid value

  Scenario: func initTrackedInvariant is callable
    Given the module "core/logic/refinement_invariant" is loaded
    Then func initTrackedInvariant should return a valid value

  Scenario: func findInvariantIndex is callable
    Given the module "core/logic/refinement_invariant" is loaded
    Then func findInvariantIndex should return a valid value

  # +7 more scenarios (types+funcs) omitted to stay under 50 lines
