@generated @medium
Feature: subjective_logic
  # generated | src/sieve/subjective_logic.nim | sieve | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "sieve/subjective_logic" is loaded
    Then all exported types should be instantiable
