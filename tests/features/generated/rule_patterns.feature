@generated @high
Feature: rule_patterns
  # generated | src/gate/rule_patterns.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/rule_patterns" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types ArchitectureViolationArtifact, rule, detail, files, severity
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/rule_patterns" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type ArchitectureViolationArtifact is instantiable
    Given the module "gate/rule_patterns" is loaded
    Then type ArchitectureViolationArtifact should be instantiable

  Scenario: type rule is instantiable
    Given the module "gate/rule_patterns" is loaded
    Then type rule should be instantiable

  Scenario: type detail is instantiable
    Given the module "gate/rule_patterns" is loaded
    Then type detail should be instantiable

  Scenario: type files is instantiable
    Given the module "gate/rule_patterns" is loaded
    Then type files should be instantiable

  Scenario: type severity is instantiable
    Given the module "gate/rule_patterns" is loaded
    Then type severity should be instantiable
