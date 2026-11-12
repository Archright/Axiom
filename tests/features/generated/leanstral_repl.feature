@generated @high
Feature: leanstral_repl
  # generated | src/verification/leanstral_repl.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/leanstral_repl" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types TacticModeEntry, proofState, env, goals
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/leanstral_repl" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type TacticModeEntry is instantiable
    Given the module "verification/leanstral_repl" is loaded
    Then type TacticModeEntry should be instantiable

  Scenario: type proofState is instantiable
    Given the module "verification/leanstral_repl" is loaded
    Then type proofState should be instantiable

  Scenario: type env is instantiable
    Given the module "verification/leanstral_repl" is loaded
    Then type env should be instantiable

  Scenario: type goals is instantiable
    Given the module "verification/leanstral_repl" is loaded
    Then type goals should be instantiable
