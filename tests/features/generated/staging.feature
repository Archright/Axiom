@generated @critical
Feature: staging
  # generated | src/core/topology/staging.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/staging" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types StagingManifest, createdAt, stagingRoot, moves, rewrites
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/staging" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs buildStagingManifest, stagingManifestJson
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type StagingManifest is instantiable
    Given the module "core/topology/staging" is loaded
    Then type StagingManifest should be instantiable

  Scenario: type createdAt is instantiable
    Given the module "core/topology/staging" is loaded
    Then type createdAt should be instantiable

  Scenario: type stagingRoot is instantiable
    Given the module "core/topology/staging" is loaded
    Then type stagingRoot should be instantiable

  Scenario: type moves is instantiable
    Given the module "core/topology/staging" is loaded
    Then type moves should be instantiable

  Scenario: type rewrites is instantiable
    Given the module "core/topology/staging" is loaded
    Then type rewrites should be instantiable

  Scenario: func buildStagingManifest is callable
    Given the module "core/topology/staging" is loaded
    Then func buildStagingManifest should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
