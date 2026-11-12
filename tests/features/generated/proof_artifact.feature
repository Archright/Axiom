@generated @critical
Feature: proof_artifact
  # generated | src/core/proof/proof_artifact.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/proof/proof_artifact" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Discontinuity, filePath, lineNumber, smtUnsatCoreVars, kind, description
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/proof/proof_artifact" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs emptyProofArtifact
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type Discontinuity is instantiable
    Given the module "core/proof/proof_artifact" is loaded
    Then type Discontinuity should be instantiable

  Scenario: type filePath is instantiable
    Given the module "core/proof/proof_artifact" is loaded
    Then type filePath should be instantiable

  Scenario: type lineNumber is instantiable
    Given the module "core/proof/proof_artifact" is loaded
    Then type lineNumber should be instantiable

  Scenario: type smtUnsatCoreVars is instantiable
    Given the module "core/proof/proof_artifact" is loaded
    Then type smtUnsatCoreVars should be instantiable

  Scenario: type kind is instantiable
    Given the module "core/proof/proof_artifact" is loaded
    Then type kind should be instantiable

  Scenario: type description is instantiable
    Given the module "core/proof/proof_artifact" is loaded
    Then type description should be instantiable

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
