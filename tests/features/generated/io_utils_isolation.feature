@generated @critical
Feature: io_utils_isolation
  # generated | src/core/utils/io_utils_isolation.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/utils/io_utils_isolation" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/utils/io_utils_isolation" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs isolatedParseXml, isolatedMoveFile, isolatedWriteFile
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func isolatedParseXml is callable
    Given the module "core/utils/io_utils_isolation" is loaded
    Then func isolatedParseXml should return a valid value

  Scenario: func isolatedMoveFile is callable
    Given the module "core/utils/io_utils_isolation" is loaded
    Then func isolatedMoveFile should return a valid value

  Scenario: func isolatedWriteFile is callable
    Given the module "core/utils/io_utils_isolation" is loaded
    Then func isolatedWriteFile should return a valid value
