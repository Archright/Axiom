@generated @medium
Feature: axiom_engine
  # generated | src/cli/axiom_engine.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/axiom_engine" is loaded
    Then all exported types should be instantiable
