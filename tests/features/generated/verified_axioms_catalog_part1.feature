@generated @critical
Feature: verified_axioms_catalog_part1
  # generated | src/core/verified_axioms/verified_axioms_catalog_part1.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/verified_axioms/verified_axioms_catalog_part1" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/verified_axioms/verified_axioms_catalog_part1" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs lookupAxiom, lookupAxiomByNimSymbol, lookupAxiomByLeanTheorem, axiomsByCategory, verifyAxiomHash, verifyAxiomHash, axiomMatchesLeanProposition, verifiedAxiomName, isVerifiedAxiomProperty, getAxiomWeight
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func lookupAxiom is callable
    Given the module "core/verified_axioms/verified_axioms_catalog_part1" is loaded
    Then func lookupAxiom should return a valid value

  Scenario: func lookupAxiomByNimSymbol is callable
    Given the module "core/verified_axioms/verified_axioms_catalog_part1" is loaded
    Then func lookupAxiomByNimSymbol should return a valid value

  Scenario: func lookupAxiomByLeanTheorem is callable
    Given the module "core/verified_axioms/verified_axioms_catalog_part1" is loaded
    Then func lookupAxiomByLeanTheorem should return a valid value

  Scenario: func axiomsByCategory is callable
    Given the module "core/verified_axioms/verified_axioms_catalog_part1" is loaded
    Then func axiomsByCategory should return a valid value

  Scenario: func verifyAxiomHash is callable
    Given the module "core/verified_axioms/verified_axioms_catalog_part1" is loaded
    Then func verifyAxiomHash should return a valid value

  Scenario: func verifyAxiomHash is callable
    Given the module "core/verified_axioms/verified_axioms_catalog_part1" is loaded
    Then func verifyAxiomHash should return a valid value

  # +4 more scenarios (types+funcs) omitted to stay under 50 lines
