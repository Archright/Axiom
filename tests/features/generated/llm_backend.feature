@generated @high
Feature: llm_backend
  # generated | src/verification/llm_backend.nim | verification | high

  Scenario: module compiles without errors
    Given the module "verification/llm_backend" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types LLMRequest, prompt, model, temperature, maxTokens, timeoutMs
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "verification/llm_backend" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"

  Scenario: type LLMRequest is instantiable
    Given the module "verification/llm_backend" is loaded
    Then type LLMRequest should be instantiable

  Scenario: type prompt is instantiable
    Given the module "verification/llm_backend" is loaded
    Then type prompt should be instantiable

  Scenario: type model is instantiable
    Given the module "verification/llm_backend" is loaded
    Then type model should be instantiable

  Scenario: type temperature is instantiable
    Given the module "verification/llm_backend" is loaded
    Then type temperature should be instantiable

  Scenario: type maxTokens is instantiable
    Given the module "verification/llm_backend" is loaded
    Then type maxTokens should be instantiable

  Scenario: type timeoutMs is instantiable
    Given the module "verification/llm_backend" is loaded
    Then type timeoutMs should be instantiable

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
