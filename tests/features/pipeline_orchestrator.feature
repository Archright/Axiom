Feature: runHermeticPipeline and HermeticPipelineConfig
  As the Hermetic Build Engine
  I want a pipeline orchestrator that manages store, cache, and environment
  So that hermetic gate execution is isolated, reproducible, and GC-safe

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: initHermeticConfig initializes store/cache/env
    Given a base directory for the hermetic pipeline
    When initHermeticConfig is called with the base directory
    Then the returned config contains a valid store path
    And the returned config contains a valid action cache path
    And the returned config contains a sandboxed environment map

  Scenario: hermeticGateRunnerCallback uses action cache
    Given a HermeticPipelineConfig with a populated action cache
    And a gate request whose inputs hash matches a cached entry
    When hermeticGateRunnerCallback is invoked for the gate
    Then the cached result is returned without re-executing the gate
    And the cache hit is logged

  Scenario: runHermeticPipeline registers GC root on success
    Given a HermeticPipelineConfig and a pipeline with one gate
    When runHermeticPipeline completes successfully
    Then a GC root is registered for the pipeline output
    And the GC root path matches the declared output location
