@generated @critical
Feature: remediation_types
  # generated | src/core/types/remediation_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/remediation_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types MathematicalDiscontinuity, filePath, lineNumber, smtUnsatCoreVars, discontinuityKind, description
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/remediation_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type MathematicalDiscontinuity is instantiable
    Given the module "core/types/remediation_types" is loaded
    Then type MathematicalDiscontinuity should be instantiable

  Scenario: type filePath is instantiable
    Given the module "core/types/remediation_types" is loaded
    Then type filePath should be instantiable

  Scenario: type lineNumber is instantiable
    Given the module "core/types/remediation_types" is loaded
    Then type lineNumber should be instantiable

  Scenario: type smtUnsatCoreVars is instantiable
    Given the module "core/types/remediation_types" is loaded
    Then type smtUnsatCoreVars should be instantiable

  Scenario: type discontinuityKind is instantiable
    Given the module "core/types/remediation_types" is loaded
    Then type discontinuityKind should be instantiable

  Scenario: type description is instantiable
    Given the module "core/types/remediation_types" is loaded
    Then type description should be instantiable
