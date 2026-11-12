@generated @medium
Feature: cli_io
  # generated | src/cli/cli_io.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/cli_io" is loaded
    Then all exported types should be instantiable
