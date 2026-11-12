@generated @critical
Feature: spec_generator_main
  # generated | src/core/spec/spec_generator_main.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/spec/spec_generator_main" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/spec/spec_generator_main" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs mapNimTypeToSmtSort, renderTypeMappingProofObligation
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func mapNimTypeToSmtSort is callable
    Given the module "core/spec/spec_generator_main" is loaded
    Then func mapNimTypeToSmtSort should return a valid value

  Scenario: func renderTypeMappingProofObligation is callable
    Given the module "core/spec/spec_generator_main" is loaded
    Then func renderTypeMappingProofObligation should return a valid value
