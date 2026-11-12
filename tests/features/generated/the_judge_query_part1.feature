@generated @critical
Feature: the_judge_query_part1
  # generated | src/core/judge/the_judge_query_part1.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/judge/the_judge_query_part1" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types LeanTokenKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/judge/the_judge_query_part1" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs extractVariables, tokenizeLeanProp, normalizeLeanTokens, tokensToString, sanitizeLean4AppSyntax, sanitizeLeanIdentifiers, sanitizeLean4Forall, generateUniqueSignature, negateLeanProposition, nimTypeToLeanType, usageHasField
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type LeanTokenKind is instantiable
    Given the module "core/judge/the_judge_query_part1" is loaded
    Then type LeanTokenKind should be instantiable

  Scenario: func extractVariables is callable
    Given the module "core/judge/the_judge_query_part1" is loaded
    Then func extractVariables should return a valid value

  Scenario: func tokenizeLeanProp is callable
    Given the module "core/judge/the_judge_query_part1" is loaded
    Then func tokenizeLeanProp should return a valid value

  Scenario: func normalizeLeanTokens is callable
    Given the module "core/judge/the_judge_query_part1" is loaded
    Then func normalizeLeanTokens should return a valid value

  Scenario: func tokensToString is callable
    Given the module "core/judge/the_judge_query_part1" is loaded
    Then func tokensToString should return a valid value

  Scenario: func sanitizeLean4AppSyntax is callable
    Given the module "core/judge/the_judge_query_part1" is loaded
    Then func sanitizeLean4AppSyntax should return a valid value

  # +6 more scenarios (types+funcs) omitted to stay under 50 lines
