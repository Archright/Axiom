@generated @critical
Feature: spec_generator_types
  # generated | src/core/spec/spec_generator_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/spec/spec_generator_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types NimSourceUnit, modulePath, source
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/spec/spec_generator_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type NimSourceUnit is instantiable
    Given the module "core/spec/spec_generator_types" is loaded
    Then type NimSourceUnit should be instantiable

  Scenario: type modulePath is instantiable
    Given the module "core/spec/spec_generator_types" is loaded
    Then type modulePath should be instantiable

  Scenario: type source is instantiable
    Given the module "core/spec/spec_generator_types" is loaded
    Then type source should be instantiable
