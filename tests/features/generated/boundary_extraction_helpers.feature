@generated @critical
Feature: boundary_extraction_helpers
  # generated | src/core/boundary/boundary_extraction_helpers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/boundary/boundary_extraction_helpers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/boundary/boundary_extraction_helpers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs typeToBoundaryConstraints, extractObjectFieldBoundaries, loadSourceFromNodeId, extractParamsFromSourceRegex, convertExpressionToSmtLean, convertExpressionToSmtLean, findNodesMultiTag, determineBoundaryTier
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func typeToBoundaryConstraints is callable
    Given the module "core/boundary/boundary_extraction_helpers" is loaded
    Then func typeToBoundaryConstraints should return a valid value

  Scenario: func extractObjectFieldBoundaries is callable
    Given the module "core/boundary/boundary_extraction_helpers" is loaded
    Then func extractObjectFieldBoundaries should return a valid value

  Scenario: func loadSourceFromNodeId is callable
    Given the module "core/boundary/boundary_extraction_helpers" is loaded
    Then func loadSourceFromNodeId should return a valid value

  Scenario: func extractParamsFromSourceRegex is callable
    Given the module "core/boundary/boundary_extraction_helpers" is loaded
    Then func extractParamsFromSourceRegex should return a valid value

  Scenario: func convertExpressionToSmtLean is callable
    Given the module "core/boundary/boundary_extraction_helpers" is loaded
    Then func convertExpressionToSmtLean should return a valid value

  Scenario: func convertExpressionToSmtLean is callable
    Given the module "core/boundary/boundary_extraction_helpers" is loaded
    Then func convertExpressionToSmtLean should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
