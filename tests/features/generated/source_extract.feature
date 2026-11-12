@generated @high
Feature: source_extract
  # generated | src/gate/runners/spec_binding/private/source_extract.nim | gate | high

  Scenario: module compiles without errors
    Given the module "gate/runners/spec_binding/private/source_extract" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "gate/runners/spec_binding/private/source_extract" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
