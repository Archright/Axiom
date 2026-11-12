@generated @critical
Feature: sad_gate
  # generated | src/core/audit/sad_gate.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/audit/sad_gate" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types AuditMode
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/audit/sad_gate" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs formatHardeningNotice, sadScore, isExempt, auditFile, auditChangedFiles, writeBackRegistry
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type AuditMode is instantiable
    Given the module "core/audit/sad_gate" is loaded
    Then type AuditMode should be instantiable

  Scenario: func formatHardeningNotice is callable
    Given the module "core/audit/sad_gate" is loaded
    Then func formatHardeningNotice should return a valid value

  Scenario: func sadScore is callable
    Given the module "core/audit/sad_gate" is loaded
    Then func sadScore should return a valid value

  Scenario: func isExempt is callable
    Given the module "core/audit/sad_gate" is loaded
    Then func isExempt should return a valid value

  Scenario: func auditFile is callable
    Given the module "core/audit/sad_gate" is loaded
    Then func auditFile should return a valid value

  Scenario: func auditChangedFiles is callable
    Given the module "core/audit/sad_gate" is loaded
    Then func auditChangedFiles should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
