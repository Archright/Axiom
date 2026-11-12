@generated @critical
Feature: judge_hub
  # generated | src/core/types/hubs/judge_hub.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/types/hubs/judge_hub" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types JudgeVerdict
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/types/hubs/judge_hub" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs (none)
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type JudgeVerdict is instantiable
    Given the module "core/types/hubs/judge_hub" is loaded
    Then type JudgeVerdict should be instantiable
