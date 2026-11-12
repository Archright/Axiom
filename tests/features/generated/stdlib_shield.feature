@generated @critical
Feature: stdlib_shield
  # generated | src/core/trusted/stdlib_shield.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/trusted/stdlib_shield" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types XmlParseError
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/trusted/stdlib_shield" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs safeParseXml, safeParseXmlFromString, safeMoveFile, safeReadFile, safeWalkDirRec, safeDirExists, safeParseJson, safeParseFile
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type XmlParseError is instantiable
    Given the module "core/trusted/stdlib_shield" is loaded
    Then type XmlParseError should be instantiable

  Scenario: func safeParseXml is callable
    Given the module "core/trusted/stdlib_shield" is loaded
    Then func safeParseXml should return a valid value

  Scenario: func safeParseXmlFromString is callable
    Given the module "core/trusted/stdlib_shield" is loaded
    Then func safeParseXmlFromString should return a valid value

  Scenario: func safeMoveFile is callable
    Given the module "core/trusted/stdlib_shield" is loaded
    Then func safeMoveFile should return a valid value

  Scenario: func safeReadFile is callable
    Given the module "core/trusted/stdlib_shield" is loaded
    Then func safeReadFile should return a valid value

  Scenario: func safeWalkDirRec is callable
    Given the module "core/trusted/stdlib_shield" is loaded
    Then func safeWalkDirRec should return a valid value

  # +3 more scenarios (types+funcs) omitted to stay under 50 lines
