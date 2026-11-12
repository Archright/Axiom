@generated @critical
Feature: spec_generator_helpers
  # generated | src/core/spec/spec_generator_helpers.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/spec/spec_generator_helpers" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/spec/spec_generator_helpers" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs normalizeIdent, splitTopLevel, normalizeNimNumericLiteral, isNonNegativeIntegerLiteral, parseRangeBounds, mapRangeToLeanSubtype, mapBuiltinRefinementType, parenthesizeLeanTypeArg, mapNimTypeToLean, parseAliases, parseStructures, parseEnums, parseGlobalVars, detectIoSideEffects, detectGlobalRefs, parseFunctions, renderStructure, leanDefaultForType
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func normalizeIdent is callable
    Given the module "core/spec/spec_generator_helpers" is loaded
    Then func normalizeIdent should return a valid value

  Scenario: func splitTopLevel is callable
    Given the module "core/spec/spec_generator_helpers" is loaded
    Then func splitTopLevel should return a valid value

  Scenario: func normalizeNimNumericLiteral is callable
    Given the module "core/spec/spec_generator_helpers" is loaded
    Then func normalizeNimNumericLiteral should return a valid value

  Scenario: func isNonNegativeIntegerLiteral is callable
    Given the module "core/spec/spec_generator_helpers" is loaded
    Then func isNonNegativeIntegerLiteral should return a valid value

  Scenario: func parseRangeBounds is callable
    Given the module "core/spec/spec_generator_helpers" is loaded
    Then func parseRangeBounds should return a valid value

  Scenario: func mapRangeToLeanSubtype is callable
    Given the module "core/spec/spec_generator_helpers" is loaded
    Then func mapRangeToLeanSubtype should return a valid value

  # +12 more scenarios (types+funcs) omitted to stay under 50 lines
