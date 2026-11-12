@generated @critical
Feature: lean_replay
  # generated | src/core/judge/lean_replay.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/judge/lean_replay" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types LeanReplayResult, isValid, proofTerm, compilerOutput, compilerStderr, exitCode
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/judge/lean_replay" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sanitizeAndWriteLeanSource, runLeanReplay
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type LeanReplayResult is instantiable
    Given the module "core/judge/lean_replay" is loaded
    Then type LeanReplayResult should be instantiable

  Scenario: type isValid is instantiable
    Given the module "core/judge/lean_replay" is loaded
    Then type isValid should be instantiable

  Scenario: type proofTerm is instantiable
    Given the module "core/judge/lean_replay" is loaded
    Then type proofTerm should be instantiable

  Scenario: type compilerOutput is instantiable
    Given the module "core/judge/lean_replay" is loaded
    Then type compilerOutput should be instantiable

  Scenario: type compilerStderr is instantiable
    Given the module "core/judge/lean_replay" is loaded
    Then type compilerStderr should be instantiable

  Scenario: type exitCode is instantiable
    Given the module "core/judge/lean_replay" is loaded
    Then type exitCode should be instantiable

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
