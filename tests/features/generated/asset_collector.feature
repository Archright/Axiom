@generated @critical
Feature: asset_collector
  # generated | src/core/trusted/asset_collector.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/trusted/asset_collector" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/trusted/asset_collector" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs normalizeIdentForFilename, normalizeModulePath, sanitizeLeanIdent, collectFunctions, buildTheoremName
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func normalizeIdentForFilename is callable
    Given the module "core/trusted/asset_collector" is loaded
    Then func normalizeIdentForFilename should return a valid value

  Scenario: func normalizeModulePath is callable
    Given the module "core/trusted/asset_collector" is loaded
    Then func normalizeModulePath should return a valid value

  Scenario: func sanitizeLeanIdent is callable
    Given the module "core/trusted/asset_collector" is loaded
    Then func sanitizeLeanIdent should return a valid value

  Scenario: func collectFunctions is callable
    Given the module "core/trusted/asset_collector" is loaded
    Then func collectFunctions should return a valid value

  Scenario: func buildTheoremName is callable
    Given the module "core/trusted/asset_collector" is loaded
    Then func buildTheoremName should return a valid value
