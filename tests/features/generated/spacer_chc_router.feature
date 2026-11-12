@generated @high
Feature: spacer_chc_router
  # generated | src/verification/spacer_chc_router.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/spacer_chc_router" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types SpacerChcResult, success, invariantSource, leanHint, solverTimeMs, status
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/spacer_chc_router" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type SpacerChcResult is instantiable
    Given the module "verification/spacer_chc_router" is loaded
    Then type SpacerChcResult should be instantiable

  Scenario: type success is instantiable
    Given the module "verification/spacer_chc_router" is loaded
    Then type success should be instantiable

  Scenario: type invariantSource is instantiable
    Given the module "verification/spacer_chc_router" is loaded
    Then type invariantSource should be instantiable

  Scenario: type leanHint is instantiable
    Given the module "verification/spacer_chc_router" is loaded
    Then type leanHint should be instantiable

  Scenario: type solverTimeMs is instantiable
    Given the module "verification/spacer_chc_router" is loaded
    Then type solverTimeMs should be instantiable

  Scenario: type status is instantiable
    Given the module "verification/spacer_chc_router" is loaded
    Then type status should be instantiable

  # +1 more scenarios (types+funcs) omitted to stay under 50 lines
