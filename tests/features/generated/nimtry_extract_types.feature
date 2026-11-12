@generated @high
Feature: nimtry_extract_types
  # generated | src/gate/nimtry/nimtry_extract_types.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/nimtry/nimtry_extract_types" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types DeclKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/nimtry/nimtry_extract_types" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type DeclKind is instantiable
    Given the module "gate/nimtry/nimtry_extract_types" is loaded
    Then type DeclKind should be instantiable
