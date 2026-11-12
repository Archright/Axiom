@generated @critical
Feature: rewrite
  # generated | src/core/topology/rewrite.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/rewrite" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ImportRewriteRule, oldPath, newPath
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/rewrite" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs makeImportRewriteRule, buildImportRewriteRules
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type ImportRewriteRule is instantiable
    Given the module "core/topology/rewrite" is loaded
    Then type ImportRewriteRule should be instantiable

  Scenario: type oldPath is instantiable
    Given the module "core/topology/rewrite" is loaded
    Then type oldPath should be instantiable

  Scenario: type newPath is instantiable
    Given the module "core/topology/rewrite" is loaded
    Then type newPath should be instantiable

  Scenario: func makeImportRewriteRule is callable
    Given the module "core/topology/rewrite" is loaded
    Then func makeImportRewriteRule should return a valid value

  Scenario: func buildImportRewriteRules is callable
    Given the module "core/topology/rewrite" is loaded
    Then func buildImportRewriteRules should return a valid value
