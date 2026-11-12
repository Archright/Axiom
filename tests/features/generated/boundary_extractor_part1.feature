@generated @critical
Feature: boundary_extractor_part1
  # generated | src/core/boundary/boundary_extractor_part1.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/boundary/boundary_extractor_part1" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/boundary/boundary_extractor_part1" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs extractBoundaries
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func extractBoundaries is callable
    Given the module "core/boundary/boundary_extractor_part1" is loaded
    Then func extractBoundaries should return a valid value
