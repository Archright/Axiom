@generated @high
Feature: proof_summarizer
  # generated | src/verification/proof_summarizer.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/proof_summarizer" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types StaticRule, ruleId, nodeId, functionName, modulePath, leanTheoremSource, smtConstraint, strategy, sourceReference, createdAt, appliedCount, successCount
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/proof_summarizer" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type StaticRule is instantiable
    Given the module "verification/proof_summarizer" is loaded
    Then type StaticRule should be instantiable

  Scenario: type ruleId is instantiable
    Given the module "verification/proof_summarizer" is loaded
    Then type ruleId should be instantiable

  Scenario: type nodeId is instantiable
    Given the module "verification/proof_summarizer" is loaded
    Then type nodeId should be instantiable

  Scenario: type functionName is instantiable
    Given the module "verification/proof_summarizer" is loaded
    Then type functionName should be instantiable

  Scenario: type modulePath is instantiable
    Given the module "verification/proof_summarizer" is loaded
    Then type modulePath should be instantiable

  Scenario: type leanTheoremSource is instantiable
    Given the module "verification/proof_summarizer" is loaded
    Then type leanTheoremSource should be instantiable

  # +9 more scenarios (types+funcs) omitted to stay under 50 lines
