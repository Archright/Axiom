@generated @medium
Feature: nim_frontend
  # generated | src/frontend/nim/nim_frontend.nim | frontend | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "frontend/nim/nim_frontend" is loaded
    Then all exported types should be instantiable
