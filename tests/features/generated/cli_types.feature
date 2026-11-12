@generated @medium
Feature: cli_types
  # generated | src/cli/cli_types.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/cli_types" is loaded
    Then all exported types should be instantiable
