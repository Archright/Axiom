@generated @medium
Feature: frontend_interface
  # generated | src/frontend/frontend_interface.nim | frontend | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "frontend/frontend_interface" is loaded
    Then all exported types should be instantiable
