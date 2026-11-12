@generated @medium
Feature: sieve_engine
  # generated | src/sieve/sieve_engine.nim | sieve | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "sieve/sieve_engine" is loaded
    Then all exported types should be instantiable
