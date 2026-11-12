@generated @medium
Feature: sieve_rules
  # generated | src/sieve/sieve_rules.nim | sieve | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "sieve/sieve_rules" is loaded
    Then all exported types should be instantiable
