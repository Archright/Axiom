@generated @critical
Feature: the_judge_lean
  # generated | src/core/judge/the_judge_lean.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/judge/the_judge_lean" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types LeanVariableUsage, name, fields, elementFields
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/judge/the_judge_lean" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs buildSmt2Query, isLeanIdentStart, readLeanIdent, previousNonSpace, hasLeanKeywordPrefix, sanitizeLeanIdentifierName, extractVariableUsages
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type LeanVariableUsage is instantiable
    Given the module "core/judge/the_judge_lean" is loaded
    Then type LeanVariableUsage should be instantiable

  Scenario: type name is instantiable
    Given the module "core/judge/the_judge_lean" is loaded
    Then type name should be instantiable

  Scenario: type fields is instantiable
    Given the module "core/judge/the_judge_lean" is loaded
    Then type fields should be instantiable

  Scenario: type elementFields is instantiable
    Given the module "core/judge/the_judge_lean" is loaded
    Then type elementFields should be instantiable

  Scenario: func buildSmt2Query is callable
    Given the module "core/judge/the_judge_lean" is loaded
    Then func buildSmt2Query should return a valid value

  Scenario: func isLeanIdentStart is callable
    Given the module "core/judge/the_judge_lean" is loaded
    Then func isLeanIdentStart should return a valid value

  # +5 more scenarios (types+funcs) omitted to stay under 50 lines
