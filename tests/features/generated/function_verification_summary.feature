@generated @critical
Feature: function_verification_summary
  # generated | src/core/types/function_verification_summary.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/function_verification_summary" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types FunctionComplexityClass
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/function_verification_summary" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs makeCacheKey, lookupSummary, storeSummary
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type FunctionComplexityClass is instantiable
    Given the module "core/types/function_verification_summary" is loaded
    Then type FunctionComplexityClass should be instantiable

  Scenario: func makeCacheKey is callable
    Given the module "core/types/function_verification_summary" is loaded
    Then func makeCacheKey should return a valid value

  Scenario: func lookupSummary is callable
    Given the module "core/types/function_verification_summary" is loaded
    Then func lookupSummary should return a valid value

  Scenario: func storeSummary is callable
    Given the module "core/types/function_verification_summary" is loaded
    Then func storeSummary should return a valid value
