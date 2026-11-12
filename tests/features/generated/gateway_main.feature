@generated @critical
Feature: gateway_main
  # generated | src/core/gateway/gateway_main.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/gateway/gateway_main" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types EvidenceWriter, Z3PersistentProverFn, AxiomProofRequest, nodeId, ownSourceCode, stateValue, inputDelta, dependencyAxioms, expectedSmtlib2, injectContradiction, timeoutMs, solverCommand, solverArgs
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/gateway/gateway_main" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs registerEvidenceWriter, registerZ3PersistentProver, isSubstantiveSmtFormula, buildInjectedSmtlib2, proveAxiomNode
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type EvidenceWriter is instantiable
    Given the module "core/gateway/gateway_main" is loaded
    Then type EvidenceWriter should be instantiable

  Scenario: type Z3PersistentProverFn is instantiable
    Given the module "core/gateway/gateway_main" is loaded
    Then type Z3PersistentProverFn should be instantiable

  Scenario: type AxiomProofRequest is instantiable
    Given the module "core/gateway/gateway_main" is loaded
    Then type AxiomProofRequest should be instantiable

  Scenario: type nodeId is instantiable
    Given the module "core/gateway/gateway_main" is loaded
    Then type nodeId should be instantiable

  Scenario: type ownSourceCode is instantiable
    Given the module "core/gateway/gateway_main" is loaded
    Then type ownSourceCode should be instantiable

  Scenario: type stateValue is instantiable
    Given the module "core/gateway/gateway_main" is loaded
    Then type stateValue should be instantiable

  # +12 more scenarios (types+funcs) omitted to stay under 50 lines
