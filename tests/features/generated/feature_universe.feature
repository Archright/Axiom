@generated @high
Feature: feature_universe
  # generated | src/gate/nimtry/feature_universe.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/feature_universe" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types FeatureViolation, rule, detail, severity
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/feature_universe" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type FeatureViolation is instantiable
    Given the module "gate/nimtry/feature_universe" is loaded
    Then type FeatureViolation should be instantiable

  Scenario: type rule is instantiable
    Given the module "gate/nimtry/feature_universe" is loaded
    Then type rule should be instantiable

  Scenario: type detail is instantiable
    Given the module "gate/nimtry/feature_universe" is loaded
    Then type detail should be instantiable

  Scenario: type severity is instantiable
    Given the module "gate/nimtry/feature_universe" is loaded
    Then type severity should be instantiable

  Scenario: func registerFeatureQueries is callable
    Given the module "gate/nimtry/feature_universe" is loaded
    Then func registerFeatureQueries should return a valid value
