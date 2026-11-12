@generated @critical
Feature: gateway_generator
  # generated | src/core/boundary/gateway/gateway_generator.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/boundary/gateway/gateway_generator" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/boundary/gateway/gateway_generator" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs lowerFirstAscii, `stringProcName`, `toProcName`
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func lowerFirstAscii is callable
    Given the module "core/boundary/gateway/gateway_generator" is loaded
    Then func lowerFirstAscii should return a valid value

  Scenario: func `stringProcName` is callable
    Given the module "core/boundary/gateway/gateway_generator" is loaded
    Then func `stringProcName` should return a valid value

  Scenario: func `toProcName` is callable
    Given the module "core/boundary/gateway/gateway_generator" is loaded
    Then func `toProcName` should return a valid value
