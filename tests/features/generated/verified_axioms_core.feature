@generated @critical
Feature: verified_axioms_core
  # generated | src/core/verified_axioms/verified_axioms_core.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/verified_axioms/verified_axioms_core" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types AxiomCategory, AxiomMapping, axiomId, nimSymbol, leanTheorem, leanType, nimSignature, leanSignature, axiomVersion, proofObligation, verified, sourceHash, leanTheoremSource, category, VerifiedAxiom, name, tokens, approved, asiWeight
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/verified_axioms/verified_axioms_core" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs computeAxiomHash, computeAxiomHash, normalizeVerifiedAxiomProp, isNaturalDomainVariableName, compactAxiomComparison, naturalDomainAxiomName, boolCasesAxiomName
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type AxiomCategory is instantiable
    Given the module "core/verified_axioms/verified_axioms_core" is loaded
    Then type AxiomCategory should be instantiable

  Scenario: type AxiomMapping is instantiable
    Given the module "core/verified_axioms/verified_axioms_core" is loaded
    Then type AxiomMapping should be instantiable

  Scenario: type axiomId is instantiable
    Given the module "core/verified_axioms/verified_axioms_core" is loaded
    Then type axiomId should be instantiable

  Scenario: type nimSymbol is instantiable
    Given the module "core/verified_axioms/verified_axioms_core" is loaded
    Then type nimSymbol should be instantiable

  Scenario: type leanTheorem is instantiable
    Given the module "core/verified_axioms/verified_axioms_core" is loaded
    Then type leanTheorem should be instantiable

  Scenario: type leanType is instantiable
    Given the module "core/verified_axioms/verified_axioms_core" is loaded
    Then type leanType should be instantiable

  # +20 more scenarios (types+funcs) omitted to stay under 50 lines
