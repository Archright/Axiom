@generated @high
Feature: git
  # generated | src/gate/git.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/git" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/git" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func gitDiffCachedPatch is callable
    Given the module "gate/git" is loaded
    Then func gitDiffCachedPatch should return a valid value

  Scenario: func gitStage is callable
    Given the module "gate/git" is loaded
    Then func gitStage should return a valid value
