@generated @critical
Feature: the_judge_query_part2
  # generated | src/core/judge/the_judge_query_part2.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/judge/the_judge_query_part2" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/judge/the_judge_query_part2" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs normalizeLeanProjectionsForKnownTypes, buildLeanVariableDeclarations, buildLeanQuery, buildLeanTheoremSkeleton, buildNegativeTestLeanQuery, checkSmtSat, checkLean4Consistency
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func normalizeLeanProjectionsForKnownTypes is callable
    Given the module "core/judge/the_judge_query_part2" is loaded
    Then func normalizeLeanProjectionsForKnownTypes should return a valid value

  Scenario: func buildLeanVariableDeclarations is callable
    Given the module "core/judge/the_judge_query_part2" is loaded
    Then func buildLeanVariableDeclarations should return a valid value

  Scenario: func buildLeanQuery is callable
    Given the module "core/judge/the_judge_query_part2" is loaded
    Then func buildLeanQuery should return a valid value

  Scenario: func buildLeanTheoremSkeleton is callable
    Given the module "core/judge/the_judge_query_part2" is loaded
    Then func buildLeanTheoremSkeleton should return a valid value

  Scenario: func buildNegativeTestLeanQuery is callable
    Given the module "core/judge/the_judge_query_part2" is loaded
    Then func buildNegativeTestLeanQuery should return a valid value

  Scenario: func checkSmtSat is callable
    Given the module "core/judge/the_judge_query_part2" is loaded
    Then func checkSmtSat should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
