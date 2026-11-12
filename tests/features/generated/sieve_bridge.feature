@generated @medium
Feature: sieve_bridge
  # generated | src/sieve/sieve_bridge.nim | sieve | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "sieve/sieve_bridge" is loaded
    Then all exported types should be instantiable
