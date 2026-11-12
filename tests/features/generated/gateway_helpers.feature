@generated @critical
Feature: gateway_helpers
  # generated | src/core/gateway/gateway_helpers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/gateway/gateway_helpers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/gateway/gateway_helpers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs isSmtKeyword, collectSmtIntSymbols, isSmtDeclOrDefLine, scanSmtDeclaredSymbolFromLine, collectSmtDeclaredSymbols, stripSmtDeclarationLines, isSmtControlLine, stripSmtProofControlLines, collectSmtAssertBodies, buildSmtConjunction, isSmtSelfEquality, hasVacuousSmtAssertion, isIntegerToken, isSmtOperatorToken, isMetadataOnlySmtSymbol
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func isSmtKeyword is callable
    Given the module "core/gateway/gateway_helpers" is loaded
    Then func isSmtKeyword should return a valid value

  Scenario: func collectSmtIntSymbols is callable
    Given the module "core/gateway/gateway_helpers" is loaded
    Then func collectSmtIntSymbols should return a valid value

  Scenario: func isSmtDeclOrDefLine is callable
    Given the module "core/gateway/gateway_helpers" is loaded
    Then func isSmtDeclOrDefLine should return a valid value

  Scenario: func scanSmtDeclaredSymbolFromLine is callable
    Given the module "core/gateway/gateway_helpers" is loaded
    Then func scanSmtDeclaredSymbolFromLine should return a valid value

  Scenario: func collectSmtDeclaredSymbols is callable
    Given the module "core/gateway/gateway_helpers" is loaded
    Then func collectSmtDeclaredSymbols should return a valid value

  Scenario: func stripSmtDeclarationLines is callable
    Given the module "core/gateway/gateway_helpers" is loaded
    Then func stripSmtDeclarationLines should return a valid value

  # +9 more scenarios (types+funcs) omitted to stay under 50 lines
