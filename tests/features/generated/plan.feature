@generated @critical
Feature: plan
  # generated | src/core/topology/plan.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/plan" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types MoveOp, file, fromPath, toPath, FilterSuggestion, filter, moveCount, rewriteCount, affectedConsumerDomains
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/plan" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs moduleImportPath, fileExistsRelative, scanSourceFiles, importsModule, computeDrift, findConsumers, computeRewrites, computePlan, parseFilterExpr, filterPlan, suggestFilters, formatSuggestions, formatPlan
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type MoveOp is instantiable
    Given the module "core/topology/plan" is loaded
    Then type MoveOp should be instantiable

  Scenario: type file is instantiable
    Given the module "core/topology/plan" is loaded
    Then type file should be instantiable

  Scenario: type fromPath is instantiable
    Given the module "core/topology/plan" is loaded
    Then type fromPath should be instantiable

  Scenario: type toPath is instantiable
    Given the module "core/topology/plan" is loaded
    Then type toPath should be instantiable

  Scenario: type FilterSuggestion is instantiable
    Given the module "core/topology/plan" is loaded
    Then type FilterSuggestion should be instantiable

  Scenario: type filter is instantiable
    Given the module "core/topology/plan" is loaded
    Then type filter should be instantiable

  # +16 more scenarios (types+funcs) omitted to stay under 50 lines
