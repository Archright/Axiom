@generated @critical
Feature: topology_parser
  # generated | src/core/topology/topology_parser.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/topology/topology_parser" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/topology/topology_parser" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs countIndent, normalizeLineSpan, countBraceDelta, stripInlineComment, parseDeclaration, countControlSignals, extractCallTargets
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func countIndent is callable
    Given the module "core/topology/topology_parser" is loaded
    Then func countIndent should return a valid value

  Scenario: func normalizeLineSpan is callable
    Given the module "core/topology/topology_parser" is loaded
    Then func normalizeLineSpan should return a valid value

  Scenario: func countBraceDelta is callable
    Given the module "core/topology/topology_parser" is loaded
    Then func countBraceDelta should return a valid value

  Scenario: func stripInlineComment is callable
    Given the module "core/topology/topology_parser" is loaded
    Then func stripInlineComment should return a valid value

  Scenario: func parseDeclaration is callable
    Given the module "core/topology/topology_parser" is loaded
    Then func parseDeclaration should return a valid value

  Scenario: func countControlSignals is callable
    Given the module "core/topology/topology_parser" is loaded
    Then func countControlSignals should return a valid value

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
