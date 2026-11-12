@generated @medium
Feature: cli_surface_generated
  # generated | src/cli/cli_surface_generated.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/cli_surface_generated" is loaded
    Then all exported types should be instantiable
