@generated @high
Feature: lean_lsp_protocol
  # generated | src/verification/lean_lsp_protocol.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/lean_lsp_protocol" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/lean_lsp_protocol" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: func toFileUri is callable
    Given the module "verification/lean_lsp_protocol" is loaded
    Then func toFileUri should return a valid value

  Scenario: func tryResolveLeanExe is callable
    Given the module "verification/lean_lsp_protocol" is loaded
    Then func tryResolveLeanExe should return a valid value

  Scenario: func resolveLeanExe is callable
    Given the module "verification/lean_lsp_protocol" is loaded
    Then func resolveLeanExe should return a valid value

  Scenario: func readerThreadFunc is callable
    Given the module "verification/lean_lsp_protocol" is loaded
    Then func readerThreadFunc should return a valid value

  Scenario: func pollMessages is callable
    Given the module "verification/lean_lsp_protocol" is loaded
    Then func pollMessages should return a valid value

  Scenario: func sendNotification is callable
    Given the module "verification/lean_lsp_protocol" is loaded
    Then func sendNotification should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
