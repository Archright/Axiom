@generated @critical
Feature: architecture_policy_types
  # generated | src/core/policy/architecture_policy_types.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/policy/architecture_policy_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types DryPolicy, functionCloneMinAstNodes, alphaEquivalence, boilerplateNodeCountThreshold
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/policy/architecture_policy_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type DryPolicy is instantiable
    Given the module "core/policy/architecture_policy_types" is loaded
    Then type DryPolicy should be instantiable

  Scenario: type functionCloneMinAstNodes is instantiable
    Given the module "core/policy/architecture_policy_types" is loaded
    Then type functionCloneMinAstNodes should be instantiable

  Scenario: type alphaEquivalence is instantiable
    Given the module "core/policy/architecture_policy_types" is loaded
    Then type alphaEquivalence should be instantiable

  Scenario: type boilerplateNodeCountThreshold is instantiable
    Given the module "core/policy/architecture_policy_types" is loaded
    Then type boilerplateNodeCountThreshold should be instantiable
