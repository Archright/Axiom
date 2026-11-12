@generated @critical
Feature: axiom_api_session_ops
  # generated | src/core/api/axiom_api_session_ops.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/api/axiom_api_session_ops" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/api/axiom_api_session_ops" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs inspectTrace, exportProof, collectSessionFromObservedMessages, exportSessionAsImportBlock, applyRedactionPolicyToSession, redactSensitiveText, validateMarkdownCodeBlocksHaveLang
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func inspectTrace is callable
    Given the module "core/api/axiom_api_session_ops" is loaded
    Then func inspectTrace should return a valid value

  Scenario: func exportProof is callable
    Given the module "core/api/axiom_api_session_ops" is loaded
    Then func exportProof should return a valid value

  Scenario: func collectSessionFromObservedMessages is callable
    Given the module "core/api/axiom_api_session_ops" is loaded
    Then func collectSessionFromObservedMessages should return a valid value

  Scenario: func exportSessionAsImportBlock is callable
    Given the module "core/api/axiom_api_session_ops" is loaded
    Then func exportSessionAsImportBlock should return a valid value

  Scenario: func applyRedactionPolicyToSession is callable
    Given the module "core/api/axiom_api_session_ops" is loaded
    Then func applyRedactionPolicyToSession should return a valid value

  Scenario: func redactSensitiveText is callable
    Given the module "core/api/axiom_api_session_ops" is loaded
    Then func redactSensitiveText should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
