@generated @medium
Feature: cli_io_input
  # generated | src/cli/cli_io_input.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/cli_io_input" is loaded
    Then all exported types should be instantiable
