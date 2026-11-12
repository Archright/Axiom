@generated @medium
Feature: sieve_types
  # generated | src/sieve/sieve_types.nim | sieve | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "sieve/sieve_types" is loaded
    Then all exported types should be instantiable
