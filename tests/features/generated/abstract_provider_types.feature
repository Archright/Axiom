@generated @high
Feature: abstract_provider_types
  # generated | src/verification/abstract_provider_types.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/abstract_provider_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Interval, lo, hi
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/abstract_provider_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type Interval is instantiable
    Given the module "verification/abstract_provider_types" is loaded
    Then type Interval should be instantiable

  Scenario: type lo is instantiable
    Given the module "verification/abstract_provider_types" is loaded
    Then type lo should be instantiable

  Scenario: type hi is instantiable
    Given the module "verification/abstract_provider_types" is loaded
    Then type hi should be instantiable
