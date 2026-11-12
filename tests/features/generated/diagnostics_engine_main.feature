@generated @critical
Feature: diagnostics_engine_main
  # generated | src/core/diagnostics/diagnostics_engine_main.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/diagnostics/diagnostics_engine_main" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types UnsatCoreCorrelation, isNonLinear, isRecursive, hasMissingInvariant, correlatedVars, astNodePaths
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/diagnostics/diagnostics_engine_main" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs hasLoopStructure, extractProcName, hasRecursiveShape, generateRefactoringTemplates
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type UnsatCoreCorrelation is instantiable
    Given the module "core/diagnostics/diagnostics_engine_main" is loaded
    Then type UnsatCoreCorrelation should be instantiable

  Scenario: type isNonLinear is instantiable
    Given the module "core/diagnostics/diagnostics_engine_main" is loaded
    Then type isNonLinear should be instantiable

  Scenario: type isRecursive is instantiable
    Given the module "core/diagnostics/diagnostics_engine_main" is loaded
    Then type isRecursive should be instantiable

  Scenario: type hasMissingInvariant is instantiable
    Given the module "core/diagnostics/diagnostics_engine_main" is loaded
    Then type hasMissingInvariant should be instantiable

  Scenario: type correlatedVars is instantiable
    Given the module "core/diagnostics/diagnostics_engine_main" is loaded
    Then type correlatedVars should be instantiable

  Scenario: type astNodePaths is instantiable
    Given the module "core/diagnostics/diagnostics_engine_main" is loaded
    Then type astNodePaths should be instantiable

  # +4 more scenarios (types+funcs) omitted to stay under 50 lines
