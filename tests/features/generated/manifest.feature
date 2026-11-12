@generated @critical
Feature: manifest
  # generated | src/core/topology/manifest.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/manifest" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/manifest" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs ensureSubdomain, inferFromPath, determineMapping
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func ensureSubdomain is callable
    Given the module "core/topology/manifest" is loaded
    Then func ensureSubdomain should return a valid value

  Scenario: func inferFromPath is callable
    Given the module "core/topology/manifest" is loaded
    Then func inferFromPath should return a valid value

  Scenario: func determineMapping is callable
    Given the module "core/topology/manifest" is loaded
    Then func determineMapping should return a valid value
