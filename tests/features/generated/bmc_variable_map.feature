@generated @critical
Feature: bmc_variable_map
  # generated | src/core/bmc/bmc_variable_map.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/bmc/bmc_variable_map" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types VariableMapping, sourceName, smtName, ssaIndex, bmcStep, sourceLine, sourceFile, scopeContext
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/bmc/bmc_variable_map" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs initScopeContextStack, pushScope, popScope, addMapping, buildVariableMap
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type VariableMapping is instantiable
    Given the module "core/bmc/bmc_variable_map" is loaded
    Then type VariableMapping should be instantiable

  Scenario: type sourceName is instantiable
    Given the module "core/bmc/bmc_variable_map" is loaded
    Then type sourceName should be instantiable

  Scenario: type smtName is instantiable
    Given the module "core/bmc/bmc_variable_map" is loaded
    Then type smtName should be instantiable

  Scenario: type ssaIndex is instantiable
    Given the module "core/bmc/bmc_variable_map" is loaded
    Then type ssaIndex should be instantiable

  Scenario: type bmcStep is instantiable
    Given the module "core/bmc/bmc_variable_map" is loaded
    Then type bmcStep should be instantiable

  Scenario: type sourceLine is instantiable
    Given the module "core/bmc/bmc_variable_map" is loaded
    Then type sourceLine should be instantiable

  # +7 more scenarios (types+funcs) omitted to stay under 50 lines
