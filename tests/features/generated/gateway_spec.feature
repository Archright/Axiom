@generated @critical
Feature: gateway_spec
  # generated | src/core/boundary/gateway/gateway_spec.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/boundary/gateway/gateway_spec" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types GatewayEndpoint, typeName, predicate, errValue, requires
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/boundary/gateway/gateway_spec" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type GatewayEndpoint is instantiable
    Given the module "core/boundary/gateway/gateway_spec" is loaded
    Then type GatewayEndpoint should be instantiable

  Scenario: type typeName is instantiable
    Given the module "core/boundary/gateway/gateway_spec" is loaded
    Then type typeName should be instantiable

  Scenario: type predicate is instantiable
    Given the module "core/boundary/gateway/gateway_spec" is loaded
    Then type predicate should be instantiable

  Scenario: type errValue is instantiable
    Given the module "core/boundary/gateway/gateway_spec" is loaded
    Then type errValue should be instantiable

  Scenario: type requires is instantiable
    Given the module "core/boundary/gateway/gateway_spec" is loaded
    Then type requires should be instantiable
