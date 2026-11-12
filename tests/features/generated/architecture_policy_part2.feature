@generated @critical
Feature: architecture_policy_part2
  # generated | src/core/policy/architecture_policy_part2.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/policy/architecture_policy_part2" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/policy/architecture_policy_part2" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs validateMandatorySections, parseArchitecturePolicy, loadArchitecturePolicy, pathMatchesGlob, layerForPath, allowedLayersFor, hasModuleRole, isAssignmentOwner, forbiddenAssignmentsFor, forbiddenCallsFor, isGeneratedModuleWhitelisted
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func validateMandatorySections is callable
    Given the module "core/policy/architecture_policy_part2" is loaded
    Then func validateMandatorySections should return a valid value

  Scenario: func parseArchitecturePolicy is callable
    Given the module "core/policy/architecture_policy_part2" is loaded
    Then func parseArchitecturePolicy should return a valid value

  Scenario: func loadArchitecturePolicy is callable
    Given the module "core/policy/architecture_policy_part2" is loaded
    Then func loadArchitecturePolicy should return a valid value

  Scenario: func pathMatchesGlob is callable
    Given the module "core/policy/architecture_policy_part2" is loaded
    Then func pathMatchesGlob should return a valid value

  Scenario: func layerForPath is callable
    Given the module "core/policy/architecture_policy_part2" is loaded
    Then func layerForPath should return a valid value

  Scenario: func allowedLayersFor is callable
    Given the module "core/policy/architecture_policy_part2" is loaded
    Then func allowedLayersFor should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
