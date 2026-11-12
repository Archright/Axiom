@generated @high
Feature: nimtry_cache
  # generated | src/gate/nimtry/nimtry_cache.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/nimtry_cache" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types CacheEntry, sourceHash, policyHash, binaryHash, nimVersion, facts
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/nimtry_cache" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type CacheEntry is instantiable
    Given the module "gate/nimtry/nimtry_cache" is loaded
    Then type CacheEntry should be instantiable

  Scenario: type sourceHash is instantiable
    Given the module "gate/nimtry/nimtry_cache" is loaded
    Then type sourceHash should be instantiable

  Scenario: type policyHash is instantiable
    Given the module "gate/nimtry/nimtry_cache" is loaded
    Then type policyHash should be instantiable

  Scenario: type binaryHash is instantiable
    Given the module "gate/nimtry/nimtry_cache" is loaded
    Then type binaryHash should be instantiable

  Scenario: type nimVersion is instantiable
    Given the module "gate/nimtry/nimtry_cache" is loaded
    Then type nimVersion should be instantiable

  Scenario: type facts is instantiable
    Given the module "gate/nimtry/nimtry_cache" is loaded
    Then type facts should be instantiable

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
