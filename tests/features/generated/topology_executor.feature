@generated @medium
Feature: topology_executor
  # generated | src/infrastructure/topology_executor.nim | infrastructure | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "infrastructure/topology_executor" is loaded
    Then all exported types should be instantiable
